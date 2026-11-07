import Foundation
import SwiftUI

@MainActor
final class WorkoutStore: ObservableObject {
    @Published private(set) var sessions: [WorkoutSession] = []
    @Published private(set) var revisions: [Revision] = []
    @Published private(set) var profile = Profile()
    @Published var importRequested = 0
    @Published var checkDateRequest: Date?
    @Published var progressRequest: String?
    @Published var pageRequest: Page?
    @Published var trainingMuscleFilter: String?
    @Published var errorMessage: String?
    @Published var newRequested = 0
    @Published var exportRequested = 0

    static let backupLimit = 50
    var backupDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }

    let fileURL: URL
    var directory: URL { fileURL.deletingLastPathComponent() }

    /// 数据目录：环境变量 MUSCLEOS_DATA_DIR（测试用）优先，否则 ~/Library/Application Support/MuscleOS
    init() {
        let fm = FileManager.default
        let dir: URL
        if let custom = ProcessInfo.processInfo.environment["MUSCLEOS_DATA_DIR"], !custom.isEmpty {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            dir = base.appendingPathComponent("MuscleOS", isDirectory: true)
        }
        fileURL = dir.appendingPathComponent("workouts.json")
        load()
    }

    private func sorted(_ s: [WorkoutSession]) -> [WorkoutSession] {
        s.sorted { a, b in a.date != b.date ? a.date > b.date : a.updatedAt > b.updatedAt }
    }

    func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            let file = try dec.decode(StoreFile.self, from: data)
            sessions = sorted(file.sessions)
            revisions = file.revisions
            profile = file.profile ?? Profile()
        } catch {
            // 不覆盖无法读取的文件：改名备份，再从空记录开始
            let backup = directory.appendingPathComponent("workouts.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fm.moveItem(at: fileURL, to: backup)
            errorMessage = "无法读取旧记录，已备份到 \(backup.lastPathComponent)。"
        }
    }

    private func persist(_ new: [WorkoutSession], _ revs: [Revision]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            backupCurrent()
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(StoreFile(sessions: new, revisions: revs, profile: profile))
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: 自动备份：每次写入前把上一版复制到 Backups/，只保留最近 backupLimit 份

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss-SSS"; return f
    }()

    func backupCurrent() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        // 连续点选时（1 分钟内）只留一份备份，避免把旧备份挤掉
        if let newest = backups().first, let d = Self.backupDate(newest), Date().timeIntervalSince(d) < 60 { return }
        do {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let dest = backupDirectory.appendingPathComponent("workouts-\(Self.stampFormatter.string(from: Date())).json")
            if !fm.fileExists(atPath: dest.path) { try fm.copyItem(at: fileURL, to: dest) }
            let old = backups().dropFirst(Self.backupLimit)
            for u in old { try? fm.removeItem(at: u) }
        } catch {
            // 备份失败不阻止保存，但要让用户知道
            errorMessage = "自动备份失败：\(error.localizedDescription)"
        }
    }

    /// 备份文件，新的在前
    func backups() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("workouts-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func backupDate(_ u: URL) -> Date? {
        let name = u.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "workouts-", with: "")
        return stampFormatter.date(from: name)
    }

    /// 用某个备份替换当前数据（替换前当前数据也会先备份）
    @discardableResult
    func restoreBackup(_ url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            _ = try dec.decode(StoreFile.self, from: data)          // 先确认备份可读
            backupCurrent()
            try data.write(to: fileURL, options: .atomic)
            load()
            return true
        } catch {
            errorMessage = "无法从备份恢复：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: 个人资料

    @discardableResult
    func saveProfile(_ p: Profile) -> Bool {
        let old = profile
        profile = p
        if persist(sessions, revisions) { return true }
        profile = old
        return false
    }

    // MARK: 最近删除

    /// 删除时留下的快照里，当前不存在的记录（同一条只取最近一次删除）
    var deletedItems: [Revision] {
        var seen = Set<String>(), out: [Revision] = []
        let live = Set(sessions.map { $0.id })
        for r in revisions.reversed() where r.at.hasSuffix("（已删除）") && !live.contains(r.entry.id) {
            if seen.insert(r.entry.id).inserted { out.append(r) }
        }
        return out
    }

    @discardableResult
    func restoreDeleted(_ r: Revision) -> Bool { save(r.entry) }

    @discardableResult
    func save(_ session: WorkoutSession, keepRevision: Bool = true) -> Bool {
        var s = session
        s.updatedAt = Date()
        var list = sessions
        var revs = revisions
        if let i = list.firstIndex(where: { $0.id == s.id }) {
            if keepRevision && list[i].signature != s.signature {
                revs.append(Revision(at: ISO8601DateFormatter().string(from: Date()), entry: list[i]))
            }
            list[i] = s
        } else { list.append(s) }
        list = sorted(list)
        guard persist(list, revs) else { return false }
        sessions = list; revisions = revs
        return true
    }

    func delete(_ id: String) {
        guard let old = sessions.first(where: { $0.id == id }) else { return }
        let list = sessions.filter { $0.id != id }
        // 删除前留一份快照到修订里，文件里仍能找回
        let revs = revisions + [Revision(at: ISO8601DateFormatter().string(from: Date()) + "（已删除）", entry: old)]
        if persist(list, revs) { sessions = list; revisions = revs }
    }

    /// 一次性写入整批记录与修订（迁移工具用）
    @discardableResult
    func replaceAll(sessions newSessions: [WorkoutSession], revisions newRevisions: [Revision]) -> Bool {
        let list = sorted(newSessions)
        guard persist(list, newRevisions) else { return false }
        sessions = list; revisions = newRevisions
        return true
    }

    /// 应用导入计划：新增记录与修订一次性写入；冲突与重复不动本机数据
    @discardableResult
    func apply(_ plan: ImportPlan) -> Bool {
        let list = sorted(sessions + plan.toAdd)
        let revs = revisions + plan.newRevisions
        guard persist(list, revs) else { return false }
        sessions = list; revisions = revs
        return true
    }
}

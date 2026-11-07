import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ExportDoc: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// 数据与备份：导出/导入、自动备份、最近删除
struct DataPageView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var pendingRestore: URL?

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M 月 d 日 HH:mm:ss"; return f
    }()

    var body: some View {
        let backups = store.backups()
        let deleted = store.deletedItems
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("数据只存在这台 Mac 上").font(.subheadline).foregroundStyle(.secondary)
                    Text("数据与备份").font(.system(size: 30, weight: .bold, design: .rounded))
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("导出与导入", systemImage: "arrow.up.arrow.down.square").font(.callout.weight(.semibold))
                        Text("导出全部记录和历史版本为 JSON（网页版兼容格式），换电脑或留档用；用「导入」可以读回，不会产生重复记录。")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button { store.exportRequested += 1 } label: { Label("导出数据…", systemImage: "square.and.arrow.up") }
                                .buttonStyle(.borderedProminent)
                            Button { store.importRequested += 1 } label: { Label("导入…", systemImage: "square.and.arrow.down") }
                        }
                        Text("当前共 \(store.sessions.count) 条记录、\(store.revisions.count) 条历史版本").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("自动备份", systemImage: "clock.arrow.circlepath").font(.callout.weight(.semibold))
                            Spacer()
                            Button("在 Finder 中显示") {
                                try? FileManager.default.createDirectory(at: store.backupDirectory, withIntermediateDirectories: true)
                                NSWorkspace.shared.activateFileViewerSelecting([backups.first ?? store.backupDirectory])
                            }.buttonStyle(.link)
                        }
                        Text("每次保存前自动把上一版复制一份，保留最近 \(WorkoutStore.backupLimit) 份。恢复某一版前，当前数据也会先备份。")
                            .font(.callout).foregroundStyle(.secondary)
                        if backups.isEmpty {
                            Text("还没有备份。第一次修改记录后会自动生成。").font(.callout).foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(backups.prefix(10), id: \.self) { u in
                                    HStack {
                                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                                        Text(WorkoutStore.backupDate(u).map { Self.timeFmt.string(from: $0) } ?? u.lastPathComponent)
                                            .monospacedDigit()
                                        Spacer()
                                        Button("恢复到这一版…") { pendingRestore = u }.buttonStyle(.link)
                                    }
                                    .padding(.vertical, 6)
                                    Divider()
                                }
                            }
                            if backups.count > 10 {
                                Text("另有 \(backups.count - 10) 份更早的备份，可在 Finder 中查看").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("最近删除", systemImage: "trash").font(.callout.weight(.semibold))
                        if deleted.isEmpty {
                            Text("没有删除过的记录。").font(.callout).foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(deleted, id: \.at) { r in
                                    HStack {
                                        SessionRow(session: r.entry)
                                        Spacer()
                                        Text("删除于 " + r.at.replacingOccurrences(of: "（已删除）", with: "").prefix(10))
                                            .font(.caption).foregroundStyle(.secondary)
                                        Button("恢复") { store.restoreDeleted(r) }
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .navigationTitle("数据与备份")
        .confirmationDialog("用这份备份替换当前数据？", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                            presenting: pendingRestore) { u in
            Button("恢复") { store.restoreBackup(u) }
        } message: { u in
            Text("将恢复到 \(WorkoutStore.backupDate(u).map { Self.timeFmt.string(from: $0) } ?? u.lastPathComponent) 的状态。当前数据会先自动备份，可以再恢复回来。")
        }
    }
}

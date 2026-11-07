import Foundation

struct ImportConflict: Identifiable {
    var id: String { incoming.id }
    let local: WorkoutSession
    let incoming: WorkoutSession
    let fields: [String]
}

struct ImportPlan {
    var fileName = ""
    var totalEntries = 0
    var toAdd: [WorkoutSession] = []
    var duplicates: [WorkoutSession] = []     // 同 ID 且内容相同
    var conflicts: [ImportConflict] = []      // 同 ID 内容不同，保留本机
    var invalid: [String] = []                // 无法识别而跳过的记录
    var warnings: [String] = []               // 字段无法识别，已留空
    var newRevisions: [Revision] = []
    var duplicateRevisions = 0

    var skippedCount: Int { duplicates.count + conflicts.count + invalid.count }
    var hasChanges: Bool { !toAdd.isEmpty || !newRevisions.isEmpty }
}

enum ImportError: LocalizedError {
    case notJSON, notMuscleOS
    var errorDescription: String? {
        switch self {
        case .notJSON: return "文件不是有效的 JSON。"
        case .notMuscleOS: return "不是 MuscleOS 网页版导出的文件（缺少 entries 列表）。"
        }
    }
}

/// 读取网页版 `导出 JSON` 的文件：{ version, profile, entries: [...], revisions: [{at, entry}] }
enum WebImporter {
    static let kinds: Set<String> = ["strength", "check", "cardio", "tennis"]

    private static func str(_ v: Any?) -> String? {
        if let s = v as? String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return Fmt.number(n.doubleValue) }
        return nil
    }
    private static func num(_ v: Any?, _ label: String, _ warns: inout [String]) -> Double? {
        if v == nil || v is NSNull { return nil }
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite { return n.doubleValue }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return nil }
            if let d = Double(t), d.isFinite { return d }
        }
        warns.append("\(label) 的值无法识别，已留空")
        return nil
    }
    private static func int(_ v: Any?, _ label: String, _ warns: inout [String]) -> Int? {
        guard let d = num(v, label, &warns) else { return nil }
        if d == d.rounded() { return Int(d) }
        warns.append("\(label) 不是整数，已留空"); return nil
    }

    static func parseEntry(_ o: [String: Any], _ warns: inout [String]) -> WorkoutSession? {
        guard let id = str(o["id"]), let type = str(o["type"]), kinds.contains(type) else { return nil }
        let tag = "「\(id)」"
        var s = WorkoutSession(id: id, date: str(o["date"]) ?? "", title: str(o["title"]) ?? "", note: str(o["note"]))
        s.type = type
        s.status = str(o["status"])
        s.updatedAt = Date(timeIntervalSince1970: 0)
        switch type {
        case "strength":
            for (i, r) in ((o["rows"] as? [[String: Any]]) ?? []).enumerated() {
                let rt = "\(tag)动作 \(i + 1)"
                guard let name = str(r["name"]) else { warns.append("\(rt) 没有名称，已跳过"); continue }
                s.exercises.append(ExerciseRecord(
                    name: name, muscle: str(r["muscle"]), unit: str(r["unit"]),
                    weight: num(r["weight"], rt + " 重量", &warns),
                    sets: int(r["sets"], rt + " 组数", &warns),
                    reps: str(r["reps"]),
                    rir: int(r["rir"], rt + " RIR", &warns),
                    feel: str(r["feel"]), pain: str(r["pain"]), recovery: str(r["recovery"]), note: str(r["note"]),
                    setLog: (r["setLog"] as? [[String: Any]]).map { log in log.map { SetEntry(weight: num($0["weight"], rt + " 逐组重量", &warns), reps: int($0["reps"], rt + " 逐组次数", &warns), rir: int($0["rir"], rt + " 逐组 RIR", &warns)) } }))
            }
        case "cardio", "tennis":
            s.duration = num(o["duration"], tag + "时长", &warns)
            s.distance = num(o["distance"], tag + "距离", &warns)
        default: // check
            s.sleep = num(o["sleep"], tag + "睡眠", &warns)
            s.weight = num(o["weight"], tag + "体重", &warns)
            s.protein = num(o["protein"], tag + "蛋白质", &warns)
            s.fatigue = str(o["fatigue"]); s.painState = str(o["painState"])
            s.symptoms = str(o["symptoms"]); s.recovery = str(o["recovery"])
            s.painAreas = (o["painAreas"] as? [String]).flatMap { $0.isEmpty ? nil : $0 }
            s.painLevel = str(o["painLevel"])
            s.soreness = (o["soreness"] as? [String: String]).flatMap { $0.isEmpty ? nil : $0 }
            s.proteinTaken = o["proteinTaken"] as? Bool
        }
        if s.title.isEmpty { s.title = ["strength": "力量", "check": "状态", "cardio": "有氧", "tennis": "网球"][type]! }
        return s
    }

    static func diffFields(_ a: WorkoutSession, _ b: WorkoutSession) -> [String] {
        var f: [String] = []
        if a.date != b.date { f.append("日期") }
        if a.title != b.title { f.append("标题") }
        if a.kind != b.kind { f.append("类型") }
        if (a.status ?? "") != (b.status ?? "") { f.append("状态") }
        if (a.note ?? "") != (b.note ?? "") { f.append("备注") }
        func sig(_ s: WorkoutSession) -> [ExerciseRecord] { s.exercises.map { var r = $0; r.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!; return r } }
        if sig(a) != sig(b) { f.append("动作") }
        if a.distance != b.distance { f.append("距离") }
        if a.duration != b.duration { f.append("用时") }
        if a.sleep != b.sleep || a.weight != b.weight || a.protein != b.protein { f.append("睡眠/体重/蛋白") }
        if a.fatigue != b.fatigue || a.painState != b.painState || a.symptoms != b.symptoms || a.recovery != b.recovery { f.append("疲劳/疼痛/恢复") }
        return f.isEmpty ? ["其他字段"] : f
    }

    static func plan(data: Data, fileName: String, existing: [WorkoutSession], existingRevisions: [Revision]) throws -> ImportPlan {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw ImportError.notJSON }
        guard let obj = root as? [String: Any], let entries = obj["entries"] as? [Any] else { throw ImportError.notMuscleOS }

        var plan = ImportPlan(fileName: fileName, totalEntries: entries.count)
        var local = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for (i, raw) in entries.enumerated() {
            guard let o = raw as? [String: Any], let e = parseEntry(o, &plan.warnings) else {
                plan.invalid.append("第 \(i + 1) 条：缺少有效的 id 或类型")
                continue
            }
            if let mine = local[e.id] {
                if mine.signature == e.signature { plan.duplicates.append(e) }
                else { plan.conflicts.append(ImportConflict(local: mine, incoming: e, fields: diffFields(mine, e))) }
            } else {
                plan.toAdd.append(e)
                local[e.id] = e          // 同一文件内的重复 ID 也不会重复新增
            }
        }

        var seen = Set(existingRevisions.map { "\($0.at)|\($0.entry.id)|\($0.entry.signature)" })
        for raw in (obj["revisions"] as? [Any]) ?? [] {
            guard let r = raw as? [String: Any], let at = str(r["at"]),
                  let eo = r["entry"] as? [String: Any], let e = parseEntry(eo, &plan.warnings) else {
                plan.warnings.append("有一条历史修订无法识别，已跳过"); continue
            }
            let key = "\(at)|\(e.id)|\(e.signature)"
            if seen.insert(key).inserted { plan.newRevisions.append(Revision(at: at, entry: e)) }
            else { plan.duplicateRevisions += 1 }
        }
        return plan
    }
}


/// 导出为网页版兼容格式（entries + revisions），可以再用「导入」读回
enum DataExporter {
    static func entry(_ s: WorkoutSession) -> [String: Any] {
        var e: [String: Any] = ["id": s.id, "date": s.date, "type": s.kind, "title": s.title]
        func put(_ k: String, _ v: Any?) { if let v { e[k] = v } }
        put("status", s.status); put("note", s.note)
        put("distance", s.distance); put("duration", s.duration)
        put("sleep", s.sleep); put("weight", s.weight); put("protein", s.protein)
        put("fatigue", s.fatigue); put("painState", s.painState); put("symptoms", s.symptoms); put("recovery", s.recovery)
        put("painAreas", s.painAreas); put("painLevel", s.painLevel); put("soreness", s.soreness); put("proteinTaken", s.proteinTaken)
        if s.kind == "strength" {
            e["rows"] = s.exercises.map { r -> [String: Any] in
                var d: [String: Any] = ["name": r.name]
                func p(_ k: String, _ v: Any?) { if let v { d[k] = v } }
                p("muscle", r.muscle); p("unit", r.unit); p("weight", r.weight); p("sets", r.sets); p("reps", r.reps)
                p("rir", r.rir); p("feel", r.feel); p("pain", r.pain); p("recovery", r.recovery); p("note", r.note)
                if let log = r.setLog {
                    d["setLog"] = log.map { s -> [String: Any] in
                        var x: [String: Any] = [:]
                        if let w = s.weight { x["weight"] = w }; if let n = s.reps { x["reps"] = n }; if let i = s.rir { x["rir"] = i }
                        return x
                    }
                }
                return d
            }
        }
        return e
    }

    static func data(sessions: [WorkoutSession], revisions: [Revision], profile: Profile = Profile()) throws -> Data {
        let root: [String: Any] = [
            "version": 1,
            "source": "MuscleOS Mac",
            "profile": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))) ?? [:],
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "entries": sessions.map(entry),
            "revisions": revisions.map { ["at": $0.at, "entry": entry($0.entry)] },
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
}

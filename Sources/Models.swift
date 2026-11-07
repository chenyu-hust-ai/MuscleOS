import Foundation

/// 一个动作记录。除动作名外所有字段可选；nil 表示"未填写"，与 0 区分。
struct ExerciseRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var muscle: String?
    var unit: String?        // 重量口径：每手 / 每侧加片 / 配重 / 额外负重
    var weight: Double?      // kg，0 是有效值
    var sets: Int?
    var reps: String?        // 可填 12 或 12 / 11 / 10
    var rir: Int?            // 末组 RIR
    var feel: String?        // 发力感
    var pain: String?        // 疼痛
    var recovery: String?    // 恢复
    var note: String?        // 备注 / 待核项 / 来源
    var setLog: [SetEntry]?  // 逐组明细；有它时上面的重量/组数/次数/RIR 是由它汇总出来的
}

struct SetEntry: Codable, Equatable {
    var weight: Double?
    var reps: Int?
    var rir: Int?
}

struct WorkoutSession: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString   // Mac 端为 UUID；网页版为 "legs" 这类字符串
    var date: String                     // yyyy-MM-dd；空字符串 = 日期待核对
    var title: String
    var note: String?
    var exercises: [ExerciseRecord] = []
    var updatedAt: Date = Date()
    // 以下为网页版导入的其他记录类型（nil type 视为力量训练）
    var type: String?                    // strength / check / cardio / tennis
    var status: String?                  // done / plan
    var distance: Double?                // 米
    var duration: Double?                // 秒
    var sleep: Double?
    var weight: Double?
    var protein: Double?
    var fatigue: String?
    var painState: String?
    var symptoms: String?
    var recovery: String?
    // 签到（点选）
    var painAreas: [String]?             // 疼痛部位
    var painLevel: String?               // 轻微 / 明显 / 影响训练
    var soreness: [String: String]?      // 肌肉酸痛：部位 -> 轻 / 明显
    var proteinTaken: Bool?              // 今天喝了蛋白粉

    var kind: String { type ?? "strength" }
    var isPlan: Bool { status == "plan" }
    /// 计入实绩统计：状态为空或 done；计划、历史基线、取消、未确认都不计入
    var isActual: Bool { status == nil || status == "done" }

    /// 内容签名：忽略行 ID 与更新时间，用于判断"同 ID 内容是否相同"
    var signature: String {
        var c = self
        c.updatedAt = Date(timeIntervalSince1970: 0)
        c.type = c.kind                      // 未写类型 = 力量
        c.exercises = c.exercises.map { var r = $0; r.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!; return r }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]; enc.dateEncodingStrategy = .iso8601
        return String(data: (try? enc.encode(c)) ?? Data(), encoding: .utf8) ?? ""
    }
}

struct Revision: Codable, Equatable {
    var at: String
    var entry: WorkoutSession
}

struct Injury: Codable, Identifiable, Equatable {
    var id = UUID()
    var area: String              // 腰 / 肩 / 膝 …
    var note: String              // 比如：深蹲时膝盖不适
    var status: String            // 已恢复，需留意 / 仍有不适 / 已痊愈
}

struct Profile: Codable, Equatable {
    var nickname = ""
    var height: Int?
    var age: Int?
    var weight: Double?           // 没秤就留空
    var weeklySessions: String?
    var avatar: Data?             // 头像：256 像素见方的 JPEG
    var injuries: [Injury] = []

    static let statuses = ["已恢复，需留意", "仍有不适", "已痊愈"]
    var activeInjuries: [Injury] { injuries.filter { $0.status != "已痊愈" } }
    var initial: String { String(nickname.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased().isEmpty ? "我" : String(nickname.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
}

struct StoreFile: Codable {
    var version = 1
    var sessions: [WorkoutSession] = []
    var revisions: [Revision] = []
    var profile: Profile?
    init(sessions: [WorkoutSession], revisions: [Revision], profile: Profile? = nil) { self.sessions = sessions; self.revisions = revisions; self.profile = profile }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        sessions = try c.decodeIfPresent([WorkoutSession].self, forKey: .sessions) ?? []
        revisions = try c.decodeIfPresent([Revision].self, forKey: .revisions) ?? []
        profile = try c.decodeIfPresent(Profile.self, forKey: .profile)
    }
}

enum Fmt {
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func day(_ d: Date) -> String { dayFormatter.string(from: d) }
    static func date(_ s: String) -> Date? { dayFormatter.date(from: s) }

    static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }
    static func dateText(_ s: String) -> String { s.isEmpty ? "日期待核对" : s }
    static func fatigueLabel(_ f: String?) -> String {
        switch f { case "低": return "精力好"; case "中": return "一般"; case "高": return "很累"; default: return Fmt.orDash(f) }
    }
    static let sorenessOrder = ["肩", "胸", "背", "手臂", "核心", "臀", "大腿", "小腿"]
    static func sorenessText(_ s: [String: String]?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return sorenessOrder.compactMap { k in s[k].map { "\(k)\($0 == "明显" ? "明显" : "")酸" } }.joined(separator: "、")
    }
    static func painText(_ s: WorkoutSession) -> String? {
        if let a = s.painAreas, !a.isEmpty { return a.joined(separator: "、") + (s.painLevel.map { " · \($0)" } ?? "") }
        if s.painState == "有不适" { return s.symptoms ?? "有不适" }
        return nil
    }

    static func statusLabel(_ s: WorkoutSession) -> String? {
        ["plan": "计划", "baseline": "历史基线", "cancelled": "已取消", "unconfirmed": "未确认"][s.status ?? ""]
    }
    static func typeLabel(_ s: WorkoutSession) -> String {
        let k = ["strength": "力量", "check": "状态", "cardio": "有氧", "tennis": "网球"][s.kind] ?? s.kind
        let st = ["plan": "计划", "baseline": "历史基线", "cancelled": "已取消", "unconfirmed": "未确认"][s.status ?? ""]
        return st.map { k + " · " + $0 } ?? k
    }
    static func summary(_ s: WorkoutSession) -> String {
        switch s.kind {
        case "strength": return "\(s.exercises.count) 个动作"
        case "check": return "签到"
        default: return s.distance.map { number($0) + " m" } ?? "—"
        }
    }
    static func clock(_ seconds: Double) -> String {
        let t = Int(seconds.rounded()); return "\(t / 60):" + String(format: "%02d", t % 60)
    }
    static func pace(_ s: WorkoutSession) -> String? {
        guard let d = s.distance, let t = s.duration, d > 0, t > 0 else { return nil }
        return clock(t / (d / 1000)) + " / km"
    }
    static func orDash(_ s: String?) -> String {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return "—" }
        return s
    }
}

extension ExerciseRecord {
    var weightText: String {
        guard let w = weight else { return "—" }
        var t = Fmt.number(w) + " kg"
        if let u = unit, !u.isEmpty { t += " · " + u }
        return t
    }
    var setsText: String { sets.map(String.init) ?? "—" }
    var rirText: String { rir.map(String.init) ?? "—" }
}

// MARK: - 编辑草稿（全部用字符串，便于校验）

struct SetDraft: Identifiable, Equatable {
    var id = UUID()
    var weight: Double?
    var reps: Int?
    var rir: Int?
    var confirmed = true      // false = 带出的参考值，保存前要确认
    var isBlank: Bool { weight == nil && reps == nil && rir == nil }
}

struct ExerciseDraft: Identifiable {
    var id = UUID()
    var name = ""
    var muscle = ""
    var unit = ""
    // 逐组模式
    var perSet = true
    var rows: [SetDraft] = []          // 默认没有组，选组数后生成
    // 汇总模式（旧记录：组数未知，或次数是 8–12 这类文字）
    var weight = ""
    var sets = ""
    var reps = ""
    var rir = ""
    var feel = ""
    var pain = ""
    var recovery = ""
    var note = ""

    init() {}
    init(_ r: ExerciseRecord) {
        id = r.id; name = r.name; muscle = r.muscle ?? ""; unit = r.unit ?? ""
        feel = r.feel ?? ""; pain = r.pain ?? ""; recovery = r.recovery ?? ""; note = r.note ?? ""
        weight = r.weight.map(Fmt.number) ?? ""
        sets = r.sets.map(String.init) ?? ""
        reps = r.reps ?? ""
        rir = r.rir.map(String.init) ?? ""
        if let log = r.setLog, !log.isEmpty {
            rows = log.map { SetDraft(weight: $0.weight, reps: $0.reps, rir: $0.rir) }
        } else if let expanded = Self.expand(r, defaultCount: nil) {
            rows = expanded
        } else if r.weight == nil && r.sets == nil && r.reps == nil && r.rir == nil {
            rows = []
        } else {
            perSet = false; rows = []
        }
    }

    /// 次数文本拆成整数；"12 / 11 / 10" -> [12,11,10]；含"–""每侧"等文字时返回 nil
    static func repNumbers(_ reps: String?) -> [Int]? {
        guard let t = reps?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return [] }
        let parts = t.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        let nums = parts.compactMap { Int($0) }
        return nums.count == parts.count ? nums : nil
    }

    /// 把汇总记录展开成逐组；组数未知时用 defaultCount（nil 表示不展开）
    static func expand(_ r: ExerciseRecord, defaultCount: Int?) -> [SetDraft]? {
        if let log = r.setLog, !log.isEmpty { return log.map { SetDraft(weight: $0.weight, reps: $0.reps, rir: $0.rir) } }
        guard let n = r.sets ?? defaultCount, n >= 1, let nums = repNumbers(r.reps) else { return nil }
        return (0..<n).map { i in
            let reps: Int? = nums.count == n ? nums[i] : nums.first
            return SetDraft(weight: r.weight, reps: reps, rir: i == n - 1 ? r.rir : nil)
        }
    }

    /// 用上次记录生成"待确认"的组
    mutating func prefill(from r: ExerciseRecord) {
        if let rows = Self.expand(r, defaultCount: 3) {
            perSet = true
            self.rows = rows.map { var x = $0; x.confirmed = false; return x }
        }
        if let u = r.unit { unit = u }
        if let m = r.muscle { muscle = m }
    }

    mutating func setCount(_ n: Int) {
        if n > rows.count {
            let base = rows.last
            for _ in rows.count..<n {
                rows.append(SetDraft(weight: base?.weight, reps: base?.reps, rir: base?.rir, confirmed: base?.confirmed ?? true))   // 复制自己填的组直接算确认；复制带出的组仍待确认
            }
        } else if n < rows.count {
            rows.removeLast(rows.count - n)
        }
    }

    /// 改第 i 组的某一项；syncDown 时，后面各组里和旧值相同的也一起改（向下填充）
    mutating func set<T: Equatable>(_ i: Int, _ kp: WritableKeyPath<SetDraft, T>, _ value: T, syncDown: Bool) {
        guard rows.indices.contains(i) else { return }
        let old = rows[i][keyPath: kp]
        rows[i][keyPath: kp] = value; rows[i].confirmed = true
        guard syncDown, old != value else { return }
        for j in rows.indices where j > i && rows[j][keyPath: kp] == old {
            rows[j][keyPath: kp] = value; rows[j].confirmed = true
        }
    }

    /// 在第 i 组后面插入一份相同的组
    mutating func duplicate(_ i: Int) {
        guard rows.indices.contains(i) else { return }
        var copy = rows[i]; copy.id = UUID(); copy.confirmed = true
        rows.insert(copy, at: i + 1)
    }

    mutating func confirmAll() { for i in rows.indices { rows[i].confirmed = true } }
    var pending: Int { rows.filter { !$0.confirmed }.count }

    private static func clean(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    func errors(index: Int) -> [String] {
        var e: [String] = []
        let p = "动作 \(index + 1)："
        if Self.clean(name) == nil { e.append(p + "请填写动作名称") }
        if perSet {
            if pending > 0 { e.append(p + "有 \(pending) 组是带出的上次数值，请改动、点「确认」或删除") }
            return e
        }
        if let w = Self.clean(weight) {
            if let v = Double(w.replacingOccurrences(of: ",", with: ".")), v >= 0, v.isFinite {} else { e.append(p + "重量需为不小于 0 的数字") }
        }
        if let s = Self.clean(sets) {
            if let v = Int(s), v >= 1 {} else { e.append(p + "组数需为不小于 1 的整数") }
        }
        if let r = Self.clean(rir) {
            if let v = Int(r), v >= 0 {} else { e.append(p + "RIR 需为不小于 0 的整数") }
        }
        return e
    }

    func record() -> ExerciseRecord {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var r = ExerciseRecord(
            id: id,
            name: cleanName,
            muscle: Self.clean(muscle) ?? exerciseCatalog.first { $0.name == cleanName }?.muscle,
            unit: Self.clean(unit) ?? exerciseCatalog.first { $0.name == cleanName }?.unit,
            weight: Self.clean(weight).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) },
            sets: Self.clean(sets).flatMap { Int($0) },
            reps: Self.clean(reps),
            rir: Self.clean(rir).flatMap { Int($0) },
            feel: Self.clean(feel), pain: Self.clean(pain), recovery: Self.clean(recovery), note: Self.clean(note))
        if perSet {
            // 由逐组汇总：重量取最重一组，次数相同写一个数、不同按组列出，RIR 取最后一组
            let rs = rows
            r.setLog = rs.isEmpty ? nil : rs.map { SetEntry(weight: $0.weight, reps: $0.reps, rir: $0.rir) }
            r.sets = rs.isEmpty ? nil : rs.count
            r.weight = rs.compactMap { $0.weight }.max()
            let reps = rs.map { $0.reps }
            if reps.allSatisfy({ $0 == nil }) { r.reps = nil }
            else if let f = reps.first!, reps.allSatisfy({ $0 == f }) { r.reps = String(f) }
            else { r.reps = reps.map { $0.map(String.init) ?? "—" }.joined(separator: " / ") }
            r.rir = rs.last?.rir
        }
        return r
    }

    /// 不同口径的常用重量
    static func weightPresets(unit: String) -> [Double] {
        switch unit {
        case "每手":
            return [1, 2, 2.5, 3, 4, 5, 6, 7, 7.5, 8, 9, 10, 12, 12.5, 14, 15, 16, 17.5, 20, 22.5, 25, 27.5, 30, 32.5, 35, 37.5, 40]
        case "每侧加片", "额外加片", "额外负重":
            return [0, 1.25, 2.5, 5, 7.5, 10, 12.5, 15, 17.5, 20, 22.5, 25, 30, 35, 40, 45, 50]
        default:
            return stride(from: 2.5, through: 150, by: 2.5).map { $0 }
        }
    }
    static let units = ["每手", "每侧", "配重", "每侧加片", "额外加片", "额外负重"]
}

struct SessionDraft {
    var base: WorkoutSession?
    var id = UUID().uuidString
    var date = Date()
    var dateUnknown = false
    var title = ""
    var note = ""
    var exercises: [ExerciseDraft] = [ExerciseDraft()]

    init() {}
    init(_ s: WorkoutSession) {
        base = s
        id = s.id
        if let d = Fmt.date(s.date) { date = d } else { dateUnknown = true }
        title = s.title
        note = s.note ?? ""
        exercises = s.exercises.map(ExerciseDraft.init)
    }

    var errors: [String] {
        var e: [String] = []
        if exercises.isEmpty { e.append("至少添加一个动作") }
        for (i, x) in exercises.enumerated() { e += x.errors(index: i) }
        return e
    }

    func session() -> WorkoutSession {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = base ?? WorkoutSession(date: "", title: "")
        s.id = id
        s.date = dateUnknown ? "" : Fmt.day(date)
        s.title = t.isEmpty ? "力量训练" : t
        s.note = n.isEmpty ? nil : n
        s.exercises = exercises.map { $0.record() }
        return s
    }
}

/// 动作库（主练肌群；协同系数见 Muscles.synergy）
struct CatalogItem { let name: String; let muscle: String; let unit: String }
let exerciseCatalog: [CatalogItem] = [
    ("坐姿推胸","胸肌中下部","配重"),("上斜推胸","胸肌上部","配重"),("推肩机","三角肌前束","配重"),("坐姿推肩","三角肌前束","每手"),
    ("哑铃侧平举","三角肌中束","每手"),("绳索侧平举","三角肌中束","每侧"),("反向蝴蝶机","三角肌后束","配重"),
    ("三头下压","肱三头肌","配重"),("直臂下压","背阔肌","配重"),("高位下拉","背阔肌","配重"),
    ("坐姿绳索划船","中斜方肌／菱形肌","配重"),("面拉","三角肌后束","配重"),("Y字上举","下斜方肌","每手"),
    ("哑铃弯举","肱二头肌","每手"),("锤式弯举","肱肌／肱桡肌","每手"),
    ("腕弯举","前臂屈肌群","每手"),("反握腕弯举","前臂伸肌群","每手"),("腕屈伸","前臂屈肌群","每手"),
    ("俯卧撑加强","前锯肌","额外负重"),("绳索前推","前锯肌","每侧"),
    ("臀推","臀大肌","每侧加片"),("哈克深蹲","股四头肌","每侧加片"),
    ("哑铃RDL","腘绳肌","每手"),("45°倒蹬","股四头肌","额外加片"),("坐姿腿弯举","腘绳肌","配重"),
    ("坐姿髋外展","臀中小肌","配重"),("坐姿髋内收","髋内收肌","配重"),
    ("站姿提踵","腓肠肌","配重"),("坐姿提踵","比目鱼肌","配重"),
    ("哑铃耸肩","上斜方肌","每手"),("罗马椅背伸","竖脊肌","额外负重"),
    ("器械卷腹","腹直肌","配重"),("绳索提膝","腹直肌","每侧"),("绳索伐木","深层核心","每侧"),("死虫","深层核心","额外负重"),
].map { CatalogItem(name: $0.0, muscle: $0.1, unit: $0.2) }

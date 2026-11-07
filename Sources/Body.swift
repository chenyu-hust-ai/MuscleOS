import SwiftUI

// MARK: - 几何（视图坐标 420×410；正面 x∈[0,200]，背面平移 220；左半边画好后镜像）

enum SVGPath {
    static func parse(_ d: String) -> Path {
        let re = try! NSRegularExpression(pattern: "[MCLZ]|-?[0-9]*\\.?[0-9]+")
        let toks = re.matches(in: d, range: NSRange(d.startIndex..., in: d)).map { String(d[Range($0.range, in: d)!]) }
        var p = Path(), cmd = "M", nums: [CGFloat] = []
        func flush() {
            switch cmd {
            case "M" where nums.count == 2: p.move(to: CGPoint(x: nums[0], y: nums[1])); nums = []; cmd = "L"
            case "L" where nums.count == 2: p.addLine(to: CGPoint(x: nums[0], y: nums[1])); nums = []
            case "C" where nums.count == 6:
                p.addCurve(to: CGPoint(x: nums[4], y: nums[5]), control1: CGPoint(x: nums[0], y: nums[1]), control2: CGPoint(x: nums[2], y: nums[3])); nums = []
            default: break
            }
        }
        for t in toks {
            if t == "Z" { p.closeSubpath(); continue }
            if ["M", "C", "L"].contains(t) { cmd = t; nums = []; continue }
            nums.append(CGFloat(Double(t)!)); flush()
        }
        return p
    }
}

struct BodyPart: Identifiable {
    let id: String
    let muscle: String      // 与动作库主练肌群同名
    let path: Path
}

enum BodyGeometry {
    static let mirror = CGAffineTransform(translationX: 200, y: 0).scaledBy(x: -1, y: 1)
    static let back = CGAffineTransform(translationX: 220, y: 0)

    static func both(_ p: Path) -> Path { var r = p; r.addPath(p.applying(mirror)); return r }

    static let silhouette: Path = {
        let half = SVGPath.parse("M100,12 C88,12 82,22 82,34 C82,46 88,54 92,56 L92,62 C86,68 76,72 66,74 C54,77 48,88 48,102 C46,120 48,140 52,150 C48,170 44,192 42,214 C40,222 38,230 40,236 C44,240 48,234 50,226 C54,206 60,182 64,158 C66,148 68,130 68,118 C70,134 72,152 72,170 C70,180 68,186 70,192 C66,224 66,262 70,300 C70,330 72,360 74,384 C72,392 74,398 82,398 C86,396 86,390 85,384 C84,360 86,330 88,300 C92,270 96,236 100,214 Z")
        let one = half.union(half.applying(mirror))          // 合并左右，去掉中线接缝
        var r = one; r.addPath(one.applying(back)); return r
    }()

    private static func absRects() -> Path {
        var p = Path()
        for y in [115.0, 132, 149, 166] { p.addRoundedRect(in: CGRect(x: 89, y: y, width: 9.5, height: y == 166 ? 14 : 15), cornerSize: CGSize(width: 3.5, height: 3.5)) }
        return p
    }

    // (id, 肌群, 正面路径, 背面路径)
    private static let defs: [(String, String, String?, String?)] = [
        ("utrap", "上斜方肌", "M93,62 C88,67 80,71 72,73 L78,78 C86,75 92,71 97,67 Z", "M99,58 C92,62 82,68 71,72 C80,77 90,81 99,85 Z"),
        ("mdelt", "三角肌中束", "M70,75 C58,77 50,88 51,104 C55,106 59,104 61,100 C61,90 64,82 70,75 Z", nil),
        ("fdelt", "三角肌前束", "M72,77 C67,83 64,92 63,102 C67,104 73,96 77,87 C78,81 76,78 72,77 Z", nil),
        ("rdelt", "三角肌后束", nil, "M69,75 C58,77 50,88 51,103 C58,101 66,93 73,83 Z"),
        ("upec", "胸肌上部", "M79,80 C86,78 94,78 99,79 L99,90 C92,90 84,92 77,94 C76,88 77,84 79,80 Z", nil),
        ("pec", "胸肌中下部", "M77,96 C84,94 92,93 99,93 L99,110 C92,114 84,114 79,110 C75,106 75,100 77,96 Z", nil),
        ("bic", "肱二头肌", "M61,108 C57,118 55,132 56,146 C59,150 63,150 65,146 C67,134 67,120 65,110 Z", nil),
        ("brach", "肱肌／肱桡肌", "M57,126 C55,134 54,142 55,150 C57,152 59,151 60,149 C59,141 59,133 58,126 Z", nil),
        ("foreF", "前臂屈肌群", "M55,158 C51,172 47,190 45,210 C48,212 51,211 53,208 C57,190 61,174 63,158 Z", nil),
        ("foreE", "前臂伸肌群", nil, "M55,153 C51,168 47,188 45,210 C48,212 51,211 53,208 C57,190 61,172 63,155 Z"),
        ("serr", "前锯肌", "M74,100 C71,108 71,118 73,126 C76,124 79,116 79,106 C78,102 76,100 74,100 Z", nil),
        ("abs", "腹直肌", "", nil),
        ("quad", "股四头肌", "M78,194 C70,216 68,248 72,282 C76,292 84,294 90,290 C94,262 96,232 96,207 C92,199 86,194 78,194 Z", nil),
        ("tfl", "阔筋膜张肌／髂胫束", "M72,182 C69,194 69,206 71,218 C74,216 77,206 78,196 C77,189 75,185 72,182 Z", nil),
        ("add", "髋内收肌", "M97,200 C99,212 99.5,232 98.5,252 C95.5,242 94,224 94,208 Z", nil),
        ("rhom", "中斜方肌／菱形肌", nil, "M99,87 C92,85 85,85 81,88 C83,99 90,108 99,114 Z"),
        ("ltrap", "下斜方肌", nil, "M99,116 C93,119 87,123 84,127 C88,132 94,139 99,147 Z"),
        ("teres", "大圆肌", nil, "M69,84 C67,88 68,94 71,97 C74,95 77,91 78,88 C75,85 72,84 69,84 Z"),
        ("lat", "背阔肌", nil, "M79,92 C73,98 70,110 70,124 C76,140 86,154 97,162 C95,146 92,130 90,114 C88,105 84,97 79,92 Z"),
        ("erec", "竖脊肌", nil, "M93,150 C91,160 91,170 93,180 L99,182 L99,149 Z"),
        ("tri", "肱三头肌", nil, "M59,107 C55,118 53,132 55,146 C59,148 63,146 65,142 C67,130 67,118 65,109 Z"),
        ("gmed", "臀中小肌", nil, "M74,185 C80,181 88,181 95,185 C90,191 82,193 74,191 Z"),
        ("glute", "臀大肌", nil, "M74,193 C81,191 92,191 99,193 L99,222 C90,228 80,226 75,218 C71,210 71,200 74,193 Z"),
        ("ham", "腘绳肌", nil, "M76,229 C72,251 72,273 76,295 C82,299 90,297 94,291 C96,269 96,249 96,231 C90,233 82,233 76,229 Z"),
        ("gas", "腓肠肌", nil, "M76,307 C72,319 72,333 76,345 C80,347 86,345 88,341 C90,329 90,317 88,307 C84,305 80,305 76,307 Z"),
        ("sol", "比目鱼肌", nil, "M77,348 C76,357 77,366 79,374 L85,374 C86,365 87,355 87,346 C84,349 80,349 77,346 Z"),
    ]

    static let parts: [BodyPart] = defs.map { id, muscle, f, b in
        var p = Path()
        if id == "abs" { p.addPath(both(absRects())) }
        else if let f, !f.isEmpty { p.addPath(both(SVGPath.parse(f))) }
        if let b { p.addPath(both(SVGPath.parse(b)).applying(back)) }
        return BodyPart(id: id, muscle: muscle, path: p)
    }

    /// 鼠标位置落在哪块肌肉上（后画的在上层，所以倒序找）
    static func hit(_ p: CGPoint, in rect: CGRect) -> String? {
        for part in parts.reversed() where FittedShape(path: part.path).path(in: rect).contains(p) { return part.muscle }
        return nil
    }

    /// 图上画不出的肌群
    static let hidden = ["深层核心"]
}

/// 把固定坐标路径缩放进实际尺寸
struct FittedShape: Shape {
    let path: Path
    static let box = CGSize(width: 420, height: 410)
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / Self.box.width, rect.height / Self.box.height)
        let dx = rect.minX + (rect.width - Self.box.width * s) / 2, dy = rect.minY + (rect.height - Self.box.height * s) / 2
        return path.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: dx, ty: dy))
    }
}

// MARK: - 数据

struct MuscleRecord: Identifiable {
    let id = UUID()
    let day: String
    let name: String
    let detail: String
    let pain: Bool
    var coef: Double = 1          // 1 = 主练；0.5 = 协同
}

struct MuscleStat {
    var lastDay: String?
    var trainedAt: Date?           // 估计的训练时间
    var weekSets = 0               // 直接组数（只算主练）
    var weekSynergy: Double = 0    // 含协同
    var lastWeekSets = 0
    var trend: [Int] = []          // 近 6 周组数（旧→新）
    var recent: [MuscleRecord] = []   // 最近 3 次
    var pain: String?              // 最近一次疼痛记录
    var latestExercise: String?
}

enum BodyStats {
    static let goals: [String: Int] = ["三角肌中束": 12]
    static func region(_ m: String) -> String { Muscles.region(m) }
    /// 建议恢复间隔（小时）：大肌群 72，其余 48。产品规则，不是医学结论
    static func window(_ m: String) -> Double { ["股四头肌", "腘绳肌", "臀大肌", "竖脊肌"].contains(m) ? 72 : 48 }
    static func exercises(for m: String) -> [String] { exerciseCatalog.filter { $0.muscle == m }.map { $0.name } }

    static func muscle(of x: ExerciseRecord) -> String? { Muscles.primary(x) }

    /// 训练时间：保存时间和训练日期同一天就用保存时间，否则按当天 18:00 估计
    static func trainedAt(_ s: WorkoutSession) -> Date? {
        guard let d = Fmt.date(s.date) else { return nil }
        if Calendar.current.isDate(s.updatedAt, inSameDayAs: d) { return s.updatedAt }
        return Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: d)
    }

    static func compute(_ sessions: [WorkoutSession], weekOf anchor: Date, today: Date = Date()) -> [String: MuscleStat] {
        var r: [String: MuscleStat] = [:]
        let todayStr = Fmt.day(today)
        for s in sessions where History.isActualStrength(s) && s.date <= todayStr {      // 已按日期倒序
            // 主练或主要协同（≥0.5）都算"练到了"，用于恢复和最近记录
            for x in s.exercises {
              for (m, c) in Muscles.contributions(x) where c >= 0.5 {
                var st = r[m] ?? MuscleStat()
                if st.lastDay == nil { st.lastDay = s.date; st.trainedAt = trainedAt(s); st.latestExercise = x.name }
                if st.recent.count < 3 { st.recent.append(MuscleRecord(day: s.date, name: x.name, detail: History.describe(x), pain: x.hasPain, coef: c)) }
                if st.pain == nil, x.hasPain {
                    st.pain = "\(String(s.date.suffix(5))) \(x.name)：\(x.pain ?? "")" + (x.recovery.map { " → \($0)" } ?? "")
                }
                r[m] = st
              }
            }
        }
        let weeks = (0..<6).map { Weekly.summarize(sessions, weekOf: Weekly.shift(Weekly.monday(of: anchor), days: ($0 - 5) * 7)) }
        let names = Set(r.keys).union(weeks.flatMap { $0.byMuscle.map { $0.muscle } }).union(weeks.last?.synergy.keys ?? [:].keys)
        for m in names {
            var st = r[m] ?? MuscleStat()
            st.trend = weeks.map { w in w.byMuscle.first { $0.muscle == m }?.sets ?? 0 }
            st.weekSets = st.trend.last ?? 0
            st.weekSynergy = weeks.last?.synergy[m] ?? 0
            st.lastWeekSets = st.trend.count >= 2 ? st.trend[st.trend.count - 2] : 0
            r[m] = st
        }
        return r
    }
}

// MARK: - 视图

struct BodyMapView: View {
    enum Mode: Hashable { case recovery, volume }
    @EnvironmentObject var store: WorkoutStore
    @State var mode: Mode
    var weekOf: Date = Date()
    var showModePicker = true

    @State private var hover: String?
    @State private var hoverPoint: CGPoint = .zero
    @State private var pinned: String?

    private var stats: [String: MuscleStat] { BodyStats.compute(store.sessions, weekOf: weekOf) }

    static let teal = Color(red: 0.365, green: 0.792, blue: 0.647)
    static let amber = Color(red: 0.980, green: 0.780, blue: 0.459)
    static let coral = Color(red: 0.941, green: 0.600, blue: 0.482)
    static let coralLight = Color(red: 0.961, green: 0.769, blue: 0.702)

    struct Recovery {
        var label: String; var color: Color; let hours: Double; let window: Double
        var timeBased = true          // false = 没有训练记录，只有签到
        var timeLabel = ""            // 只按时间的状态
        var soreNote: String?         // 签到：大腿明显酸
        var pain: String?             // 签到：腰 · 轻微
    }

    /// 时间判断 + 今天签到：明显酸 → 至少「恢复中」；轻微酸只注明；疼痛不改状态，单独提示
    static func adjusted(_ m: String, _ st: MuscleStat?, check: WorkoutSession?, now: Date = Date()) -> Recovery? {
        var r = recovery(m, st, now: now)
        let sore = Muscles.soreness(m, check), pain = Muscles.pain(m, check)
        if r == nil {
            guard sore != nil || pain != nil else { return nil }
            r = Recovery(label: "无记录", color: Color.primary.opacity(0.12), hours: 0, window: BodyStats.window(m), timeBased: false)
        }
        r!.timeLabel = r!.label
        if let (part, lv) = sore {
            if lv == "明显" {
                r!.soreNote = "今天签到：\(part)明显酸 → 按「恢复中」处理"
                if r!.label == "可练" || r!.label == "无记录" { r!.label = "恢复中"; r!.color = amber }
            } else {
                r!.soreNote = "今天签到：\(part)轻微酸"
            }
        }
        if let p = pain { r!.pain = "今天签到：\(p)" }
        return r
    }

    /// 恢复状态：24 小时内 = 刚练过；未到建议间隔 = 恢复中；之后 = 可练
    static func recovery(_ m: String, _ st: MuscleStat?, now: Date = Date()) -> Recovery? {
        guard let t = st?.trainedAt else { return nil }
        let h = max(0, now.timeIntervalSince(t) / 3600), w = BodyStats.window(m)
        if h < 24 { return Recovery(label: "刚练过", color: coral, hours: h, window: w) }
        if h < w { return Recovery(label: "恢复中", color: amber, hours: h, window: w) }
        return Recovery(label: "可练", color: teal, hours: h, window: w)
    }
    static func ago(_ h: Double, _ day: String?) -> String {
        if h < 1 { return "刚刚" }
        if h < 24 { return "\(Int(h)) 小时前" }
        let d = Int(h / 24)
        return d == 1 ? "昨天" : "\(d) 天前"
    }

    private func fill(_ m: String) -> Color? {
        let st = stats[m]
        switch mode {
        case .recovery:
            let r = Self.adjusted(m, st, check: Muscles.todayCheck(store.sessions))
            return r?.label == "无记录" ? nil : r?.color
        case .volume:
            let n = st?.weekSynergy ?? 0          // 含协同
            return n <= 0 ? nil : n <= 3 ? Self.coralLight : n <= 6 ? Self.coral : Brand.accent
        }
    }

    private var defaultMuscle: String {
        stats.filter { $0.value.trainedAt != nil }.max { ($0.value.trainedAt ?? .distantPast) < ($1.value.trainedAt ?? .distantPast) }?.key ?? "三角肌中束"
    }

    var body: some View {
        let focus = hover
        let st = stats
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if showModePicker {
                    Picker("着色", selection: $mode) { Text("恢复状态").tag(Mode.recovery); Text("本周组数").tag(Mode.volume) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Spacer()
                legend
            }
            HStack(alignment: .top, spacing: 16) {
                GeometryReader { geo in
                    let rect = CGRect(origin: .zero, size: geo.size)
                    ZStack(alignment: .topLeading) {
                        FittedShape(path: BodyGeometry.silhouette).fill(Color.primary.opacity(0.045))
                        FittedShape(path: BodyGeometry.silhouette).stroke(Color.primary.opacity(0.14), lineWidth: 0.8)
                        let check = Muscles.todayCheck(store.sessions)
                        ForEach(BodyGeometry.parts) { part in
                            let c = fill(part.muscle)
                            let isFocus = focus == part.muscle
                            let hurt = Muscles.pain(part.muscle, check) != nil
                            FittedShape(path: part.path)
                                .fill(c ?? Color.primary.opacity(0.10))
                                .overlay(FittedShape(path: part.path).stroke(isFocus ? Brand.accent : Color(nsColor: .windowBackgroundColor), lineWidth: isFocus ? 1.6 : 0.8))
                                .overlay(hurt ? FittedShape(path: part.path).stroke(Brand.pain, style: StrokeStyle(lineWidth: 1.8, dash: [3, 2])) : nil)
                                .opacity(focus == nil || isFocus ? 1 : 0.28)
                                .allowsHitTesting(false)
                        }
                        if let m = focus {
                            tooltip(m, st[m])
                                .fixedSize()
                                .offset(x: min(hoverPoint.x + 14, max(0, rect.width - 220)), y: min(hoverPoint.y + 14, rect.height - 30))
                                .allowsHitTesting(false)
                        }
                    }
                    // 整张图只用一个鼠标追踪区，按鼠标位置判断落在哪块肌肉上
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p): hover = BodyGeometry.hit(p, in: rect); hoverPoint = p
                        case .ended: hover = nil
                        }
                    }
                    .onTapGesture(coordinateSpace: .local) { p in
                        if let m = BodyGeometry.hit(p, in: rect) { pinned = m }
                    }
                }
                .animation(.easeOut(duration: 0.18), value: focus)
                .animation(.easeInOut(duration: 0.3), value: mode)
                .aspectRatio(420 / 410, contentMode: .fit)
                .frame(minHeight: 320, maxHeight: 460)
                .overlay(alignment: .bottom) {
                    HStack { Text("正面").frame(maxWidth: .infinity); Text("背面").frame(maxWidth: .infinity) }
                        .font(.caption2).foregroundStyle(.secondary).offset(y: 14)
                }
                MuscleDetailPanel(muscle: focus ?? pinned ?? defaultMuscle, stat: st[focus ?? pinned ?? defaultMuscle])
                    .frame(width: 270)
            }
            HStack(spacing: 6) {
                Text("图上看不到：").font(.caption).foregroundStyle(.secondary)
                ForEach(BodyGeometry.hidden, id: \.self) { m in
                    let name = m == "肩袖" ? "肩袖" : m
                    Text("\(name) · \(st[m]?.weekSets ?? 0) 组").font(.caption)
                        .help("深层核心在体表看不到")
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background((pinned == m ? Brand.accent.opacity(0.18) : Color.primary.opacity(0.07)), in: Capsule())
                        .onTapGesture { pinned = m }
                }
                Spacer()
                Text("点击肌肉可固定显示").font(.caption).foregroundStyle(.tertiary)
            }.padding(.top, 12)
        }
    }

    private func tooltip(_ m: String, _ s: MuscleStat?) -> some View {
        let rec = Self.adjusted(m, s, check: Muscles.todayCheck(store.sessions))
        return HStack(spacing: 6) {
            Circle().fill(rec?.color ?? Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
            Text(m).font(.caption.weight(.semibold))
            Text("· " + (rec.map { r in r.timeBased ? "\(r.label) · \(Self.ago(r.hours, s?.lastDay))" : r.label } ?? "无记录")
                 + (rec?.soreNote != nil ? " · 有酸痛" : "")).font(.caption).foregroundStyle(.secondary)
            if rec?.pain != nil { Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Brand.pain) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private var legend: some View {
        let items: [(Color, String)] = mode == .recovery
            ? [(Self.teal, "可练"), (Self.amber, "恢复中"), (Self.coral, "刚练过"), (Color.primary.opacity(0.12), "无记录"), (Brand.pain, "虚线 = 签到有疼痛")]
            : [(Self.coralLight, "≤3 组"), (Self.coral, "3–6 组"), (Brand.accent, "6 组以上 · 含协同")]
        return HStack(spacing: 12) {
            ForEach(items, id: \.1) { c, t in
                HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(t) }
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

/// 右侧详情：恢复倒计时、本周组数、近 6 周、疼痛、最近记录、常用动作
struct MuscleDetailPanel: View {
    @EnvironmentObject var store: WorkoutStore
    let muscle: String
    let stat: MuscleStat?

    var body: some View {
        let st = stat ?? MuscleStat()
        let rec = BodyMapView.adjusted(muscle, stat, check: Muscles.todayCheck(store.sessions))
        let goal = BodyStats.goals[muscle]
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(BodyStats.region(muscle)).font(.caption2).foregroundStyle(.secondary)
                        Text(muscle).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                        if let n = Muscles.notes[muscle] {
                            Text(n).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Text(rec?.label ?? "无记录").font(.caption2.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background((rec?.color ?? .secondary).opacity(0.22), in: Capsule())
                }

                if let r = rec, r.timeBased {
                    VStack(alignment: .leading, spacing: 4) {
                        let pct = Int((min(r.hours, r.window) / r.window * 100).rounded(.down))
                        let timeColor: Color = r.timeLabel == "刚练过" ? BodyMapView.coral : r.timeLabel == "恢复中" ? BodyMapView.amber : BodyMapView.teal
                        HStack(alignment: .firstTextBaseline) {
                            Text("恢复进度").font(.caption.weight(.semibold))
                            Text("\(pct)%").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(timeColor == BodyMapView.amber ? Brand.pain : timeColor)
                            Spacer()
                            Text((r.label != r.timeLabel ? "按时间" : "") + (r.hours >= r.window ? "已恢复" : "约 \(Int((r.window - r.hours).rounded(.up))) 小时后恢复"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(r.hours, r.window), total: r.window).tint(timeColor)
                        Text("上次 \(BodyMapView.ago(r.hours, st.lastDay)) · 建议间隔 \(Int(r.window)) 小时")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                } else {
                    Text("还没有这个肌群的训练记录").font(.caption).foregroundStyle(.secondary)
                }
                if let n = rec?.soreNote {
                    Label(n, systemImage: "flame").font(.caption).foregroundStyle(Color(red: 0.39, green: 0.22, blue: 0.02))
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(BodyMapView.amber.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                if let p = rec?.pain {
                    Label(p + "，相关动作先降重量或换动作", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Brand.pain)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.pain.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(st.weekSets)").font(.system(size: 38, weight: .regular, design: .serif)).monospacedDigit()
                        VStack(alignment: .leading, spacing: 0) {
                            Text(goal.map { "/ \($0) 组目标 · 本周" } ?? "组 · 本周").font(.caption).foregroundStyle(.secondary)
                            Text("含协同 \(Fmt.number((st.weekSynergy * 100).rounded() / 100)) 组").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if st.weekSets != st.lastWeekSets {
                            Text("上周 \(st.lastWeekSets)  " + (st.weekSets > st.lastWeekSets ? "↑\(st.weekSets - st.lastWeekSets)" : "↓\(st.lastWeekSets - st.weekSets)"))
                                .font(.caption2).foregroundStyle(st.weekSets > st.lastWeekSets ? .green : .secondary)
                        }
                    }
                    if let g = goal { ProgressView(value: Double(min(st.weekSets, g)), total: Double(g)).tint(Brand.accent) }
                    let trend = st.trend.isEmpty ? Array(repeating: 0, count: 6) : st.trend
                    let mx = max(4, trend.max() ?? 0)
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(Array(trend.enumerated()), id: \.offset) { i, v in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i == trend.count - 1 ? Brand.accent : Color.primary.opacity(0.15))
                                .frame(height: max(3, CGFloat(v) / CGFloat(mx) * 32))
                        }
                    }.frame(height: 34, alignment: .bottom)
                    Text("近 6 周组数（最右为本周）").font(.caption2).foregroundStyle(.tertiary)
                }

                if let p = st.pain {
                    Label(p, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Brand.pain)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.pain.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("最近记录").font(.caption2).foregroundStyle(.secondary)
                    if st.recent.isEmpty { Text("—").font(.caption).foregroundStyle(.secondary) }
                    ForEach(st.recent) { r in
                        HStack(alignment: .top, spacing: 8) {
                            Text(String(r.day.suffix(5))).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(r.name).font(.caption.weight(.semibold))
                                    if r.coef < 1 { Text("协同 ×\(Fmt.number(r.coef))").font(.caption2).foregroundStyle(.secondary) }
                                    if r.pain { Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Brand.pain) }
                                }
                                Text(r.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                            }
                        }
                    }
                }

                let common = BodyStats.exercises(for: muscle)
                if !common.isEmpty {
                    Text("常用动作：" + common.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let ex = st.latestExercise {
                        Button("看进步曲线") { store.progressRequest = ex; store.pageRequest = .progress }
                    }
                    if !st.recent.isEmpty {
                        Button("相关训练") { store.trainingMuscleFilter = muscle; store.pageRequest = .training }
                    }
                }.controlSize(.small)
            }
        }
    }
}

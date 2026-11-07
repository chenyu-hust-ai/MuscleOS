import Foundation
import SwiftUI
import Charts

/// 点选按钮
struct ChoiceChip: View {
    let label: String
    var selected = false
    var hint = false                 // 虚线 = 昨天的选择
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout.monospacedDigit())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Brand.accent : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Brand.accent : Color.primary.opacity(0.25),
                                                style: StrokeStyle(lineWidth: 1, dash: hint && !selected ? [4, 3] : [])))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 简单换行布局
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

struct RecoveryView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var date = Date()
    @State private var savedAt: Date?
    @State private var showMore = false
    @State private var proteinText = ""
    @State private var recoveryText = ""
    @State private var noteText = ""

    static let sleepOptions: [Double] = [5, 5.5, 6, 6.5, 7, 7.5, 8, 8.5, 9]
    static let painParts = ["肩", "肘", "手腕", "腰", "髋", "膝", "脚踝"]
    static let painLevels = ["轻微", "明显", "影响训练"]

    private var day: String { Fmt.day(date) }
    private func existing(_ d: String) -> WorkoutSession? { store.sessions.first { $0.kind == "check" && $0.date == d } }
    private var today: WorkoutSession? { existing(day) }
    private var yesterday: WorkoutSession? { existing(Fmt.day(Weekly.shift(Calendar.current.startOfDay(for: date), days: -1))) }

    /// 改一项就保存；同一条签到 10 分钟内的连续修改不再逐次留历史版本
    private func update(_ change: (inout WorkoutSession) -> Void) {
        var s = today ?? WorkoutSession(date: day, title: "状态签到")
        s.type = "check"; s.status = nil
        change(&s)
        if let a = s.painAreas, !a.isEmpty { s.painState = "有不适" }
        s.symptoms = s.painState == "有不适" ? Fmt.painText(s) : nil
        let keep = today.map { Date().timeIntervalSince($0.updatedAt) > 600 } ?? false
        if store.save(s, keepRevision: keep) { savedAt = Date() }
    }

    private func loadTexts() {
        let s = today
        proteinText = s?.protein.map(Fmt.number) ?? ""
        recoveryText = s?.recovery ?? ""
        noteText = s?.note ?? ""
    }
    private func saveTexts() {
        let p = proteinText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let protein = p.isEmpty ? nil : Double(p).flatMap { $0 >= 0 ? $0 : nil }
        let r = recoveryText.trimmingCharacters(in: .whitespacesAndNewlines), n = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard protein != today?.protein || (r.isEmpty ? nil : r) != today?.recovery || (n.isEmpty ? nil : n) != today?.note else { return }
        update { s in
            s.protein = protein; s.recovery = r.isEmpty ? nil : r; s.note = n.isEmpty ? nil : n
            if protein != nil { s.proteinTaken = true }
        }
    }

    private func sleepLabel(_ v: Double) -> String { v <= 5 ? "≤5" : v >= 9 ? "≥9 小时" : Fmt.number(v) }

    private var content: some View {
        let s = today, y = yesterday
        return VStack(alignment: .leading, spacing: 14) {
                header

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        title("moon.stars", "睡眠", "虚线 = 昨天的选择")
                        let opts = Self.sleepOptions + ([s?.sleep].compactMap { $0 }.filter { !Self.sleepOptions.contains($0) })
                        WrapLayout {
                            ForEach(opts.sorted(), id: \.self) { v in
                                ChoiceChip(label: sleepLabel(v), selected: s?.sleep == v, hint: y?.sleep == v) {
                                    update { $0.sleep = ($0.sleep == v ? nil : v) }
                                }
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        title("battery.50", "疲劳", nil)
                        HStack(spacing: 10) {
                            fatigueButton("低", "bolt.fill", "精力好", s)
                            fatigueButton("中", "face.dashed", "一般", s)
                            fatigueButton("高", "zzz", "很累", s)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        title("exclamationmark.triangle", "疼痛", "关节、腰这类不正常的痛")
                        HStack(spacing: 6) {
                            ChoiceChip(label: "没有不适", selected: s?.painState == "无不适") {
                                update { $0.painState = "无不适"; $0.painAreas = nil; $0.painLevel = nil }
                            }
                            ChoiceChip(label: "有不适", selected: s?.painState == "有不适") {
                                update { $0.painState = "有不适" }
                            }
                        }
                        if s?.painState == "有不适" {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("部位（可多选）").font(.caption).foregroundStyle(.secondary)
                                WrapLayout {
                                    ForEach(Self.painParts, id: \.self) { p in
                                        ChoiceChip(label: p, selected: s?.painAreas?.contains(p) == true) {
                                            update { x in
                                                var a = x.painAreas ?? []
                                                if let i = a.firstIndex(of: p) { a.remove(at: i) } else { a.append(p) }
                                                x.painAreas = a.isEmpty ? nil : Self.painParts.filter { a.contains($0) }
                                            }
                                        }
                                    }
                                }
                                Text("程度").font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    ForEach(Self.painLevels, id: \.self) { l in
                                        ChoiceChip(label: l, selected: s?.painLevel == l) { update { $0.painLevel = ($0.painLevel == l ? nil : l) } }
                                    }
                                }
                                if let t = s.flatMap(Fmt.painText) {
                                    Text("将记录为：\(t)").font(.caption).foregroundStyle(Brand.pain)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        title("flame", "肌肉酸痛", "现在还酸的部位（之前训练留下的），会影响今天建议练哪里")
                        WrapLayout {
                            ForEach(Fmt.sorenessOrder, id: \.self) { part in
                                let lv = s?.soreness?[part]
                                ChoiceChip(label: lv.map { "\(part) · \($0)" } ?? part, selected: lv != nil) {
                                    update { x in
                                        var d = x.soreness ?? [:]
                                        switch d[part] { case nil: d[part] = "轻"; case "轻": d[part] = "明显"; default: d[part] = nil }
                                        x.soreness = d.isEmpty ? nil : d
                                    }
                                }
                            }
                        }
                        Text("点一次 = 轻，再点 = 明显，第三次取消").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Toggle("今天喝了蛋白粉", isOn: Binding(get: { s?.proteinTaken == true },
                                                                set: { v in update { $0.proteinTaken = v } }))
                                .toggleStyle(.switch)
                            Spacer()
                            Button { withAnimation { showMore.toggle() } } label: {
                                Label("更多（克数、备注）", systemImage: showMore ? "chevron.up" : "chevron.down")
                            }.buttonStyle(.borderless).foregroundStyle(.secondary)
                        }
                        if showMore {
                            HStack(spacing: 12) {
                                labeled("蛋白质（g）") { TextField("—", text: $proteinText).textFieldStyle(.roundedBorder).onSubmit(saveTexts) }
                                labeled("恢复反馈") { TextField("—", text: $recoveryText).textFieldStyle(.roundedBorder).onSubmit(saveTexts) }
                            }
                            labeled("备注") { TextField("—", text: $noteText).textFieldStyle(.roundedBorder).onSubmit(saveTexts) }
                            Text("按回车保存，离开页面时也会保存").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }

                weekCard
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)

    }

    var scrollable = true

    var body: some View {
        Group {
            if scrollable { ScrollView { content } } else { content }
        }
        .navigationTitle("恢复")
        .onAppear {
            if let d = store.checkDateRequest { date = d; store.checkDateRequest = nil }
            loadTexts()
        }
        .onChange(of: day) { _, _ in loadTexts(); savedAt = nil }
        .onDisappear(perform: saveTexts)
        .tint(Brand.accent)
    }

    private var header: some View {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M 月 d 日 · EEEE"
        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(f.string(from: date)).font(.subheadline).foregroundStyle(.secondary)
                    DatePicker("日期", selection: $date, displayedComponents: .date).labelsHidden().datePickerStyle(.field).fixedSize()
                }
                Text(Calendar.current.isDateInToday(date) ? "今天感觉怎么样" : "补记这一天的状态")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
            Spacer()
            if let y = yesterday {
                Button {
                    update { s in
                        s.sleep = y.sleep; s.fatigue = y.fatigue; s.painState = y.painState
                        s.painAreas = y.painAreas; s.painLevel = y.painLevel; s.soreness = y.soreness; s.proteinTaken = y.proteinTaken
                    }
                } label: { Label("复制昨天", systemImage: "doc.on.doc") }
                    .help("把昨天的睡眠、疲劳、疼痛、酸痛、蛋白粉带过来，再改有变化的")
            }
            if savedAt != nil || today != nil {
                Label(savedAt != nil ? "已自动保存" : "已签到", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
            }
        }
    }

    private func title(_ icon: String, _ t: String, _ sub: String?) -> some View {
        HStack(spacing: 8) {
            Label(t, systemImage: icon).font(.callout.weight(.semibold))
            if let sub { Text(sub).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func labeled<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(t).font(.caption).foregroundStyle(.secondary); c() }
    }

    private func fatigueButton(_ value: String, _ icon: String, _ label: String, _ s: WorkoutSession?) -> some View {
        let on = s?.fatigue == value
        return Button { update { $0.fatigue = ($0.fatigue == value ? nil : value) } } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title2)
                Text(label).font(.callout)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .foregroundStyle(on ? Brand.accent : .primary)
            .background(on ? Brand.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Brand.accent : Color.primary.opacity(0.2), lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: 近 7 天

    private struct DayBar: Identifiable { let id: String; let label: String; let sleep: Double; let fatigue: String; let pain: Bool }

    private var weekCard: some View {
        let days = (0..<7).map { Fmt.day(Weekly.shift(Calendar.current.startOfDay(for: date), days: $0 - 6)) }
        let bars: [DayBar] = days.compactMap { d in
            guard let c = existing(d), let sl = c.sleep else { return nil }
            return DayBar(id: d, label: d == day ? "当天" : String(d.suffix(5)), sleep: sl,
                          fatigue: c.fatigue == nil ? "未填" : Fmt.fatigueLabel(c.fatigue), pain: c.painState == "有不适")
        }
        let labels = days.map { $0 == day ? "当天" : String($0.suffix(5)) }
        let checks = store.sessions.filter { $0.kind == "check" && !$0.date.isEmpty && $0.date <= day }.prefix(10)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                title("calendar", "近 7 天", nil)
                if bars.isEmpty {
                    Text("这 7 天还没有睡眠记录").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    Chart {
                        ForEach(bars) { b in
                            BarMark(x: .value("日期", b.label), y: .value("睡眠", b.sleep), width: .fixed(26))
                                .foregroundStyle(by: .value("疲劳", b.fatigue))
                                .cornerRadius(5)
                                .annotation(position: .top) { Text(Fmt.number(b.sleep)).font(.caption2).foregroundStyle(.secondary) }
                        }
                        ForEach(bars.filter { $0.pain }) { b in
                            PointMark(x: .value("日期", b.label), y: .value("睡眠", b.sleep * 0.85))
                                .symbol(.circle).symbolSize(60).foregroundStyle(Brand.pain)
                        }
                    }
                    .chartXScale(domain: labels)
                    .chartYScale(domain: 0...10)
                    .chartForegroundStyleScale(["精力好": BodyMapView.teal, "一般": BodyMapView.amber, "很累": BodyMapView.coral, "未填": Color.gray.opacity(0.4)])
                    .chartLegend(.hidden)
                    .frame(height: 170)
                    Text("柱高 = 睡眠（小时）· 颜色 = 疲劳（绿 精力好 / 黄 一般 / 橙 很累）· 圆点 = 有疼痛")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !checks.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow { Text("日期"); Text("睡眠"); Text("疲劳"); Text("疼痛 / 酸痛") }
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(checks)) { c in
                            GridRow {
                                Text(String(c.date.suffix(5))).monospacedDigit()
                                Text(c.sleep.map { Fmt.number($0) + " h" } ?? "—").monospacedDigit()
                                Text(Fmt.fatigueLabel(c.fatigue))
                                HStack(spacing: 4) {
                                    if let p = Fmt.painText(c) { Text(p).foregroundStyle(Brand.pain); Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Brand.pain) } else { Text("—") }
                                    Text("/").foregroundStyle(.tertiary)
                                    Text(Fmt.sorenessText(c.soreness) ?? "—")
                                }
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
    }
}

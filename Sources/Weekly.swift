import Foundation
import SwiftUI
import Charts

/// 周统计，规则对照网页版 model.js 的 summarize()：
/// 周一起算 7 天；只统计有日期、非计划的实绩；只有填了组数的动作计入组数，缺失的只计"待补"。
struct WeekSummary {
    var start: String
    var end: String
    var sessions = 0
    var knownSets: Int?                 // 没有任何已知组数时为 nil（显示「—」）
    var byMuscle: [(muscle: String, sets: Int)] = []
    var missingSets = 0
    var missingItems: [String] = []
    var cardio = 0
    var tennis = 0
    var plans = 0                       // 本周计划（不计入实绩）
    var load = 0                        // 训练负荷分 = Σ 组数 × (10 − RIR)，RIR 缺失按 3
    var rirAssumed = 0                  // 负荷分里按 3 计的动作条数
    var avgRIR: Double?                 // 已填 RIR 的动作按组数加权平均
    var synergy: [String: Double] = [:] // 含协同组数：主练 1 + 协同系数
}

enum Weekly {
    static let unlabeled = "未标注肌群"
    static var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }()

    static func monday(of d: Date) -> Date {
        let wd = cal.component(.weekday, from: d)           // 1=周日 … 7=周六
        return cal.date(byAdding: .day, value: -((wd + 5) % 7), to: cal.startOfDay(for: d))!
    }
    static func shift(_ d: Date, days: Int) -> Date { cal.date(byAdding: .day, value: days, to: d)! }

    /// 已完成实绩：有日期、不是计划、不是状态签到
    static func isActual(_ s: WorkoutSession) -> Bool {
        !s.date.isEmpty && s.isActual && s.kind != "check"
    }

    static func summarize(_ all: [WorkoutSession], weekOf anchor: Date) -> WeekSummary {
        let start = monday(of: anchor)
        let sStart = Fmt.day(start), sEnd = Fmt.day(shift(start, days: 6))
        var r = WeekSummary(start: sStart, end: sEnd)
        let inWeek = all.filter { !$0.date.isEmpty && $0.date >= sStart && $0.date <= sEnd }
        r.plans = inWeek.filter { $0.isPlan && $0.kind == "strength" }.count
        var by: [String: Int] = [:]
        var anyKnown = false
        var rirSum = 0.0, rirSets = 0
        for s in inWeek where isActual(s) {
            switch s.kind {
            case "strength":
                r.sessions += 1
                for x in s.exercises {
                    if let n = x.sets {
                        anyKnown = true
                        by[Muscles.primary(x) ?? unlabeled, default: 0] += n
                        for (m, c) in Muscles.contributions(x) { r.synergy[m, default: 0] += Double(n) * c }
                        if let rir = x.rir { rirSum += Double(n * rir); rirSets += n } else { r.rirAssumed += 1 }
                        r.load += n * max(0, 10 - (x.rir ?? 3))
                    } else {
                        r.missingSets += 1
                        r.missingItems.append("\(s.date) \(x.name)")
                    }
                }
            case "cardio": r.cardio += 1
            case "tennis": r.tennis += 1
            default: break
            }
        }
        r.avgRIR = rirSets > 0 ? rirSum / Double(rirSets) : nil
        r.knownSets = anyKnown ? by.values.reduce(0, +) : nil
        r.byMuscle = by.map { ($0.key, $0.value) }.sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.muscle < $1.muscle }
        return r
    }
}

struct WeeklyReportView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var anchor = Weekly.monday(of: Date())

    private var summary: WeekSummary { Weekly.summarize(store.sessions, weekOf: anchor) }
    private var previous: WeekSummary { Weekly.summarize(store.sessions, weekOf: Weekly.shift(anchor, days: -7)) }

    private struct MuscleBar: Identifiable { let id = UUID(); let muscle: String; let week: String; let sets: Int }
    private func delta(_ a: Int, _ b: Int) -> String { a - b == 0 ? "持平" : (a > b ? "+\(a - b)" : "\(a - b)") }
    private var undated: Int { store.sessions.filter { $0.date.isEmpty && $0.kind != "check" && $0.isActual }.count }

    var body: some View {
        let s = summary
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { anchor = Weekly.shift(anchor, days: -7) } label: { Label("上一周", systemImage: "chevron.left") }
                        .accessibilityIdentifier("prev-week")
                    Text("\(s.start) – \(s.end)").font(.title2.bold()).monospacedDigit()
                    Button { anchor = Weekly.shift(anchor, days: 7) } label: { Label("下一周", systemImage: "chevron.right") }
                        .accessibilityIdentifier("next-week")
                    Button("本周") { anchor = Weekly.monday(of: Date()) }
                    Spacer()
                    DatePicker("跳转到", selection: Binding(get: { anchor }, set: { anchor = Weekly.monday(of: $0) }),
                               displayedComponents: .date)
                        .fixedSize()
                }
                Text("每周从周一开始").font(.caption).foregroundStyle(.secondary)

                let p = previous
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    metric("力量训练", "\(s.sessions) 次", "上周 \(p.sessions) 次 · \(delta(s.sessions, p.sessions))", id: "m-sessions")
                    metric("已知力量组", s.knownSets.map { "\($0) 组" } ?? "—", "上周 \(p.knownSets.map { "\($0) 组" } ?? "—")" + (s.knownSets != nil && p.knownSets != nil ? " · \(delta(s.knownSets!, p.knownSets!))" : ""), id: "m-sets")
                    metric("训练负荷分", s.load > 0 ? "\(s.load)" : "—", "上周 \(p.load > 0 ? "\(p.load)" : "—")" + (s.load > 0 && p.load > 0 ? " · \(delta(s.load, p.load))" : ""), id: "m-load")
                    metric("平均 RIR", s.avgRIR.map { String(format: "%.1f", $0) } ?? "—", "上周 \(p.avgRIR.map { String(format: "%.1f", $0) } ?? "—")", id: "m-rir")
                    metric("有氧", "\(s.cardio) 次", "上周 \(p.cardio) 次", id: "m-cardio")
                    metric("网球", "\(s.tennis) 次", "上周 \(p.tennis) 次", id: "m-tennis")
                }
                if s.rirAssumed > 0 {
                    Text("负荷分 = Σ 组数 × (10 − RIR)；有 \(s.rirAssumed) 条动作没填 RIR，按 3 计。").font(.caption).foregroundStyle(.secondary)
                }

                if s.missingSets > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("有 \(s.missingSets) 条动作组数待补，未计入合计", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).accessibilityIdentifier("missing-note")
                        ForEach(s.missingItems, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                }

                MuscleAnalysisCard(weekOf: anchor)

                GroupBox("本周肌群分布") {
                    BodyMapView(mode: .volume, weekOf: anchor, showModePicker: false)
                        .id(s.start)
                        .padding(6)
                }

                GroupBox("各主练肌群组数：本周 与 上周") {
                    let order = Array(Set(s.byMuscle.map { $0.muscle } + p.byMuscle.map { $0.muscle }))
                        .sorted { (a, b) in
                            let sa = s.byMuscle.first { $0.muscle == a }?.sets ?? 0, sb = s.byMuscle.first { $0.muscle == b }?.sets ?? 0
                            return sa != sb ? sa > sb : a < b
                        }
                    if order.isEmpty {
                        Text("—").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        let data: [MuscleBar] = order.flatMap { m in [
                            MuscleBar(muscle: m, week: "本周", sets: s.byMuscle.first { $0.muscle == m }?.sets ?? 0),
                            MuscleBar(muscle: m, week: "上周", sets: p.byMuscle.first { $0.muscle == m }?.sets ?? 0)] }
                        Chart(data) { d in
                            BarMark(x: .value("组数", d.sets), y: .value("肌群", d.muscle))
                                .foregroundStyle(by: .value("周", d.week))
                                .position(by: .value("周", d.week))
                                .annotation(position: .trailing) { Text("\(d.sets)").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .chartYScale(domain: order)
                        .chartForegroundStyleScale(["本周": Color.blue, "上周": Color.gray])
                        .frame(height: CGFloat(order.count) * 44 + 40)
                        .accessibilityIdentifier("muscle-compare")
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("统计口径").font(.caption.bold())
                    Text("仅统计有日期的已完成记录；训练计划、状态签到和历史修订不计入。组数只算入动作标注的主练肌群。").font(.caption)
                    if s.plans > 0 { Text("本周另有 \(s.plans) 条训练计划，未计入。").font(.caption) }
                    if undated > 0 { Text("另有 \(undated) 条日期待核对的记录，未计入任何一周。").font(.caption) }
                }.foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func metric(_ title: String, _ value: String, _ sub: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title.bold()).monospacedDigit().accessibilityIdentifier(id)
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

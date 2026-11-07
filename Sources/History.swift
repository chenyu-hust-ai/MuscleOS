import Foundation
import SwiftUI
import Charts

extension ExerciseRecord {
    /// 估算 1RM（Epley）：重量 × (1 + 次数 / 30)。次数取"12 / 11 / 10"中的第一个数；重量为 0 或缺失时不估算。
    var e1rm: Double? {
        guard let w = weight, w > 0, let r = reps,
              let first = r.split(whereSeparator: { !$0.isNumber }).first, let n = Double(first), n > 0 else { return nil }
        return w * (1 + n / 30)
    }
    var hasPain: Bool { !(pain ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    var repsText: String { Fmt.orDash(reps) }
}

struct ProgressPoint: Identifiable {
    let id: String
    let day: String
    let date: Date
    let record: ExerciseRecord
}

/// 历史查询：只用有日期、非计划的力量实绩
enum History {
    static func isActualStrength(_ s: WorkoutSession) -> Bool { s.kind == "strength" && s.isActual && !s.date.isEmpty }

    /// 按"有记录的训练次数"从多到少排序（次数相同保持最近使用在前）
    static func exerciseNames(_ sessions: [WorkoutSession]) -> [String] {
        var counts: [String: Int] = [:], order: [String] = []
        for s in sessions where isActualStrength(s) {          // sessions 已按日期倒序
            for n in Set(s.exercises.map { $0.name }) {
                if counts[n] == nil { order.append(n) }
                counts[n, default: 0] += 1
            }
        }
        return order.enumerated().sorted { a, b in
            let ca = counts[a.element]!, cb = counts[b.element]!
            return ca != cb ? ca > cb : a.offset < b.offset
        }.map { $0.element }
    }
    static func sessionCount(_ name: String, _ sessions: [WorkoutSession]) -> Int {
        sessions.filter { isActualStrength($0) && $0.exercises.contains { $0.name == name } }.count
    }

    static func points(name: String, sessions: [WorkoutSession]) -> [ProgressPoint] {
        var out: [ProgressPoint] = []
        for s in sessions where isActualStrength(s) {
            guard let d = Fmt.date(s.date) else { continue }
            let rows = s.exercises.filter { $0.name == name }
            guard let r = rows.max(by: { ($0.weight ?? -1) < ($1.weight ?? -1) }) else { continue }
            out.append(ProgressPoint(id: s.id, day: s.date, date: d, record: r))
        }
        return out.sorted { $0.day < $1.day }
    }

    static func lastRecord(name: String, onOrBefore day: String?, excluding id: String, sessions: [WorkoutSession]) -> (day: String, record: ExerciseRecord)? {
        for s in sessions where isActualStrength(s) && s.id != id && (day == nil || s.date <= day!) {
            if let r = s.exercises.first(where: { $0.name == name }) { return (s.date, r) }
        }
        return nil
    }

    static func lastSession(onOrBefore day: String?, excluding id: String, sessions: [WorkoutSession]) -> WorkoutSession? {
        sessions.first { isActualStrength($0) && $0.id != id && !$0.exercises.isEmpty && (day == nil || $0.date <= day!) }
    }

    static func describe(_ r: ExerciseRecord) -> String {
        "\(r.weightText) × \(r.setsText) × \(r.repsText) · RIR \(r.rirText)"
    }
}

struct ProgressPageView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var name = ""
    @State private var metric = 0       // 0 重量, 1 估算 1RM

    private var names: [String] { History.exerciseNames(store.sessions) }
    private var points: [ProgressPoint] { History.points(name: name, sessions: store.sessions) }

    private func value(_ p: ProgressPoint) -> Double? { metric == 0 ? p.record.weight : p.record.e1rm }

    var body: some View {
        let pts = points
        let painPts = pts.filter { $0.record.hasPain }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if names.isEmpty {
                    ContentUnavailableView("还没有可画曲线的训练", systemImage: "chart.xyaxis.line",
                                           description: Text("保存或导入带日期的力量训练后，这里会按动作显示进步曲线"))
                } else {
                    HStack {
                        Picker("动作", selection: $name) { ForEach(names, id: \.self) { Text("\($0)（\(History.sessionCount($0, store.sessions)) 次）").tag($0) } }
                            .frame(maxWidth: 280).accessibilityIdentifier("progress-exercise")
                        Picker("指标", selection: $metric) {
                            Text("重量").tag(0); Text("估算 1RM").tag(1)
                        }.pickerStyle(.segmented).fixedSize()
                        Spacer()
                    }
                    if let u = pts.last?.record.unit, !u.isEmpty {
                        Text("重量口径：\(u)。曲线只在同一动作内比较。").font(.caption).foregroundStyle(.secondary)
                    }
                    if metric == 1 {
                        Text("估算 1RM = 重量 × (1 + 次数 ÷ 30)，次数取第一个数；0 kg 或缺次数的记录不画点。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    let plotted = pts.filter { value($0) != nil }
                    if pts.count < 2 {
                        Label("这个动作只有 \(pts.count) 次记录，还画不出进步曲线。再练一次并保存，就会连成线。", systemImage: "info.circle")
                            .foregroundStyle(.secondary).accessibilityIdentifier("need-more")
                    }
                    if plotted.isEmpty {
                        Text("—  这个动作暂无可画的数据").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        Chart {
                            ForEach(plotted) { p in
                                LineMark(x: .value("日期", p.date), y: .value(metric == 0 ? "重量 kg" : "估算 1RM kg", value(p)!))
                                    .foregroundStyle(.blue)
                                PointMark(x: .value("日期", p.date), y: .value("值", value(p)!)).foregroundStyle(.blue)
                            }
                            ForEach(plotted.filter { $0.record.hasPain }) { p in
                                PointMark(x: .value("日期", p.date), y: .value("值", value(p)!))
                                    .symbol(.triangle).symbolSize(150).foregroundStyle(.red)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month().day()) } }
                        .frame(height: pts.count < 2 ? 140 : 260)
                        .accessibilityIdentifier("progress-chart")
                        HStack(spacing: 14) {
                            Label("蓝色：记录", systemImage: "circle.fill").foregroundStyle(.blue)
                            Label("红色三角：当次有疼痛记录", systemImage: "triangle.fill").foregroundStyle(.red)
                        }.font(.caption)
                    }
                    if painPts.count >= 2 {
                        Label("这个动作有 \(painPts.count) 次训练记录了疼痛，最近一次 \(painPts.last!.day)。", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).accessibilityIdentifier("pain-repeat")
                    }
                    Table(pts.reversed()) {
                        TableColumn("日期") { Text($0.day) }.width(90)
                        TableColumn("重量") { Text($0.record.weightText) }.width(min: 80, ideal: 120)
                        TableColumn("组数") { Text($0.record.setsText) }.width(50)
                        TableColumn("次数") { Text($0.record.repsText) }.width(70)
                        TableColumn("RIR") { Text($0.record.rirText) }.width(40)
                        TableColumn("估算 1RM") { Text($0.record.e1rm.map { String(format: "%.1f", $0) } ?? "—") }.width(70)
                        TableColumn("疼痛") { p in Text(Fmt.orDash(p.record.pain)).foregroundStyle(p.record.hasPain ? .orange : .primary) }
                        TableColumn("恢复") { Text(Fmt.orDash($0.record.recovery)) }
                    }
                    .frame(minHeight: 220)
                }
            }
            .padding()
        }
        .onAppear {
            if let r = store.progressRequest, names.contains(r) { name = r; store.progressRequest = nil }
            else if name.isEmpty || !names.contains(name) { name = names.first ?? "" }
        }
        .onChange(of: store.sessions) { _, _ in if !names.contains(name) { name = names.first ?? "" } }
    }
}

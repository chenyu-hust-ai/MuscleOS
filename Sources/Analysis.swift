import SwiftUI

/// 周报里的肌群分析（规则判断，仅供参考）
struct MuscleAnalysis {
    var ignored: [String] = []
    var push = 0, pull = 0
    var front = 0, mid = 0, rear = 0
    var upper = 0, lower = 0
    var midGoal = 12

    static func compute(_ sessions: [WorkoutSession], weekOf anchor: Date, today: Date = Date()) -> MuscleAnalysis {
        let w = Weekly.summarize(sessions, weekOf: anchor)
        func direct(_ ms: [String]) -> Int { w.byMuscle.filter { ms.contains($0.muscle) }.reduce(0) { $0 + $1.sets } }
        var a = MuscleAnalysis()
        a.push = direct(Muscles.push); a.pull = direct(Muscles.pull)
        a.front = direct(["三角肌前束"]); a.mid = direct(["三角肌中束"]); a.rear = direct(["三角肌后束"])
        a.lower = direct(Muscles.lower)
        a.upper = direct(Muscles.all.filter { !Muscles.lower.contains($0) && !Muscles.core.contains($0) })
        // 最近 14 天（截至所选周的周日或今天，取较早者）没有任何参与（含协同）的肌群
        let weekEnd = Weekly.shift(Weekly.monday(of: anchor), days: 6)
        let end = min(weekEnd, today)
        let endStr = Fmt.day(end), startStr = Fmt.day(Weekly.shift(Calendar.current.startOfDay(for: end), days: -13))
        var touched = Set<String>()
        for s in sessions where History.isActualStrength(s) && s.date >= startStr && s.date <= endStr {
            for x in s.exercises where (x.sets ?? 0) > 0 || x.sets == nil {
                for (m, _) in Muscles.contributions(x) { touched.insert(m) }
            }
        }
        a.ignored = Muscles.all.filter { !touched.contains($0) }
        return a
    }

    var pushPullVerdict: String {
        if push == 0 && pull == 0 { return "本周还没有推拉动作" }
        if push == 0 { return "本周只有拉" }
        if pull == 0 { return "本周只有推" }
        let r = Double(pull) / Double(push)
        return r < 0.75 ? "拉偏少" : r > 1.33 ? "推偏少" : "基本平衡"
    }
    var shoulderVerdict: String {
        if front + mid + rear == 0 { return "本周还没练肩" }
        var v: [String] = []
        if mid < midGoal { v.append("中束距目标还差 \(midGoal - mid) 组") } else { v.append("中束已达标") }
        if front > 0 && rear * 2 < front { v.append("后束偏少") }
        return v.joined(separator: "，")
    }
    var lowerVerdict: String {
        let t = upper + lower
        if t == 0 { return "—" }
        let p = Int((Double(lower) / Double(t) * 100).rounded())
        return "下肢占 \(p)%" + (p < 20 ? "，偏少" : "")
    }
}

struct MuscleAnalysisCard: View {
    @EnvironmentObject var store: WorkoutStore
    let weekOf: Date

    var body: some View {
        let a = MuscleAnalysis.compute(store.sessions, weekOf: weekOf)
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("肌群分析", systemImage: "chart.bar.doc.horizontal").font(.callout.weight(.semibold))
                    Spacer()
                    Text("按直接组数判断，规则仅供参考").font(.caption).foregroundStyle(.secondary)
                }
                row("推拉平衡", a.pushPullVerdict) {
                    ratioBar([("推", a.push, Brand.accent), ("拉", a.pull, Color(red: 0.11, green: 0.62, blue: 0.46))])
                }
                row("肩三束", a.shoulderVerdict) {
                    ratioBar([("前束", a.front, Brand.accent.opacity(0.55)), ("中束", a.mid, Brand.accent), ("后束", a.rear, Brand.accent.opacity(0.8))])
                }
                row("上下肢", a.lowerVerdict) {
                    ratioBar([("上肢", a.upper, Color.blue.opacity(0.7)), ("下肢", a.lower, Color.purple.opacity(0.6))])
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("被忽略的肌群").font(.callout.weight(.medium))
                        Text("最近 14 天没有任何参与（含协同）").font(.caption).foregroundStyle(.secondary)
                    }
                    if a.ignored.isEmpty {
                        Text("全部肌群都练到了").font(.callout).foregroundStyle(.green)
                    } else {
                        FlowChips(items: a.ignored)
                    }
                }
            }
        }
    }

    private func row<C: View>(_ title: String, _ verdict: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Text(verdict).font(.callout).foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func ratioBar(_ parts: [(String, Int, Color)]) -> some View {
        let total = max(1, parts.reduce(0) { $0 + $1.1 })
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(parts.indices, id: \.self) { i in
                        let p = parts[i]
                        if p.1 > 0 {
                            Rectangle().fill(p.2).frame(width: max(4, g.size.width * CGFloat(p.1) / CGFloat(total) - 2))
                        }
                    }
                    if parts.allSatisfy({ $0.1 == 0 }) { Rectangle().fill(Color.primary.opacity(0.08)) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 8)
            HStack(spacing: 14) {
                ForEach(parts.indices, id: \.self) { i in
                    HStack(spacing: 4) {
                        Circle().fill(parts[i].2).frame(width: 7, height: 7)
                        Text("\(parts[i].0) \(parts[i].1) 组").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// 简单的换行标签
struct FlowChips: View {
    let items: [String]
    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 6).map { Array(items[$0..<min($0 + 6, items.count)]) }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.self) { m in
                        Text(m).font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                }
            }
        }
    }
}

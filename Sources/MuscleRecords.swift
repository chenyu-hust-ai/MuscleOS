import SwiftUI

/// 某块肌肉的相关动作记录（从人体图「相关训练」进入）
struct MuscleRecordsView: View {
    @EnvironmentObject var store: WorkoutStore
    let muscle: String
    let onEdit: (WorkoutSession) -> Void
    let onDelete: (WorkoutSession) -> Void
    @State private var openSession: String?

    struct Item: Identifiable {
        let id: String
        let session: WorkoutSession
        let record: ExerciseRecord
        var coef: Double = 1
        var progress: String?
    }

    private var items: [Item] { Self.items(muscle: muscle, sessions: store.sessions) }

    static func items(muscle: String, sessions: [WorkoutSession]) -> [Item] {
        var out: [Item] = []
        for s in sessions where History.isActualStrength(s) {          // 已按日期倒序
            for (i, x) in s.exercises.enumerated() where Muscles.coefficient(x, muscle) >= 0.5 {
                out.append(Item(id: "\(s.id)#\(i)", session: s, record: x, coef: Muscles.coefficient(x, muscle)))
            }
        }
        // 和同一动作的上一次比较
        for i in out.indices {
            guard let prev = out[(i + 1)...].first(where: { $0.record.name == out[i].record.name })?.record else { continue }
            let cur = out[i].record
            if let w = cur.weight, let pw = prev.weight, w > pw { out[i].progress = "重量 ↑" }
            else if cur.weight == prev.weight, let r = maxReps(cur), let pr = maxReps(prev), r > pr { out[i].progress = "次数 ↑" }
        }
        return out
    }
    static func maxReps(_ r: ExerciseRecord) -> Int? {
        if let log = r.setLog { return log.compactMap { $0.reps }.max() }
        return ExerciseDraft.repNumbers(r.reps)?.max()
    }

    var body: some View {
        if let id = openSession, let s = store.sessions.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 0) {
                Button { openSession = nil } label: { Label("返回\(muscle)相关记录", systemImage: "chevron.left") }
                    .buttonStyle(.borderless).padding(.horizontal, 22).padding(.top, 14)
                SessionDetail(session: s, revisions: store.revisions.filter { $0.entry.id == s.id }.reversed(),
                              onEdit: { onEdit(s) }, onDelete: { onDelete(s) }, highlightMuscle: muscle)
            }
            .navigationTitle("训练")
        } else {
            list
        }
    }

    private var list: some View {
        let all = items
        let week = Weekly.summarize(store.sessions, weekOf: Date()).byMuscle.first { $0.muscle == muscle }?.sets ?? 0
        let heaviest = all.compactMap { $0.record.weight }.max()
        let stat = BodyStats.compute(store.sessions, weekOf: Date())[muscle]
        let rec = BodyMapView.recovery(muscle, stat)   // 只看时间
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(Brand.accent)
                    Text(muscle).font(.headline)
                    Text("· 相关记录 \(all.count) 条 · 主练和主要协同（×0.5）的动作").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button { store.trainingMuscleFilter = nil } label: { Label("退出", systemImage: "xmark") }
                        .buttonStyle(.borderless).foregroundStyle(Brand.accent)
                }
                .padding(12)
                .background(Brand.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 12) {
                    StatTile(label: "本周组数", value: "\(week)", unit: "组")
                    StatTile(label: "最重一组", value: heaviest.map(Fmt.number) ?? "—", unit: heaviest == nil ? "" : "kg")
                    StatTile(label: "上次", value: rec.map { BodyMapView.ago($0.hours, stat?.lastDay) } ?? "—", unit: "")
                }

                if all.isEmpty {
                    ContentUnavailableView("还没有\(muscle)的记录", systemImage: "figure.arms.open",
                                           description: Text("常用动作：" + BodyStats.exercises(for: muscle).joined(separator: "、")))
                }
                ForEach(all) { it in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(String(it.session.date.suffix(5))).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(width: 46, alignment: .leading)
                                Text(it.record.name).font(.headline)
                                Text([it.record.unit, it.session.title].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if it.coef < 1 { Text("协同 ×\(Fmt.number(it.coef))").font(.caption).foregroundStyle(.secondary) }
                                if let p = it.progress { Text(p).font(.caption.weight(.medium)).foregroundStyle(.green) }
                                if it.record.hasPain { Chip(icon: "exclamationmark.triangle.fill", text: it.record.pain ?? "疼痛", tint: Brand.pain) }
                                Spacer()
                                Button("查看整次训练 ›") { openSession = it.session.id }.buttonStyle(.link)
                            }
                            HStack(spacing: 6) {
                                ForEach(Array(Self.chips(it.record).enumerated()), id: \.offset) { _, t in
                                    Text(t).font(.callout.monospacedDigit())
                                        .padding(.horizontal, 9).padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                            }
                            .padding(.leading, 54)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("训练")
    }

    static func chips(_ r: ExerciseRecord) -> [String] {
        func w(_ v: Double?) -> String { v.map { Fmt.number($0) + " kg" } ?? "—" }
        if let log = r.setLog, !log.isEmpty {
            return log.map { s in "\(w(s.weight)) × \(s.reps.map(String.init) ?? "—")" + (s.rir.map { " · RIR \($0)" } ?? "") }
        }
        return ["\(w(r.weight)) × \(r.setsText) 组 · 次数 \(r.repsText)" + (r.rir.map { " · RIR \($0)" } ?? "")]
    }
}

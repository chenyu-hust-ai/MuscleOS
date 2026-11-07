import SwiftUI

/// 今日页（第一阶段）：签到、本周、上次训练；规划模块上线前推荐区显示说明
struct TodayView: View {
    @EnvironmentObject var store: WorkoutStore
    let goTo: (Page) -> Void
    let openSession: (WorkoutSession) -> Void
    let newSession: () -> Void

    private var today: String { Fmt.day(Date()) }
    private var dateTitle: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M 月 d 日 · EEEE"
        return f.string(from: Date())
    }
    private var check: WorkoutSession? { store.sessions.first { $0.kind == "check" && $0.date == today } }
    private var trainedToday: [WorkoutSession] { store.sessions.filter { $0.date == today && $0.isActual && $0.kind != "check" } }
    private var last: WorkoutSession? { History.lastSession(onOrBefore: today, excluding: "", sessions: store.sessions) }
    private var week: WeekSummary { Weekly.summarize(store.sessions, weekOf: Date()) }

    /// 签到给出的提示（规则同网页版：睡眠 < 6 小时或疲劳高 → 优先恢复）
    private var needRest: Bool {
        guard let c = check else { return false }
        return (c.sleep.map { $0 < 6 } ?? false) || c.fatigue == "高"
    }
    private var reasons: [String] {
        guard let c = check else { return [] }
        var r: [String] = []
        if let s = c.sleep, s < 6 { r.append("睡眠 \(Fmt.number(s)) 小时 < 6") }
        if c.fatigue == "高" { r.append("疲劳：很累") }
        if let p = Fmt.painText(c) { r.append("疼痛：\(p)") }
        for part in Fmt.sorenessOrder where c.soreness?[part] == "明显" { r.append("\(part)明显酸") }
        return r
    }
    private var headline: String {
        if let t = trainedToday.first { return "今天已完成：\(t.title)" }
        if check == nil { return "先签到，看看今天的状态" }
        if needRest { return "今天优先恢复" }
        if check?.painLevel == "影响训练" { return "今天先避开不适的部位" }
        return "今天还没有训练记录"
    }

    var scrollable = true

    private var content: some View {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateTitle).font(.subheadline).foregroundStyle(.secondary)
                    Text(headline).font(.system(size: 30, weight: .bold, design: .rounded))
                }

                if !reasons.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: needRest ? "moon.zzz.fill" : "exclamationmark.triangle.fill").font(.title3)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(needRest ? (trainedToday.isEmpty ? "状态偏差。今天建议休息或只做轻松活动，明天签到后再评估。"
                                                                  : "状态偏差。今天已经练过了，今晚注意休息，明天签到后再评估。")
                                          : "今天注意下面这些情况，人体图已标出相关肌肉。")
                                .font(.callout)
                            HStack(spacing: 6) {
                                ForEach(reasons, id: \.self) { r in
                                    Text(r).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.25)))
                                }
                            }
                        }
                        Spacer()
                    }
                    .foregroundStyle(Color(red: 0.39, green: 0.22, blue: 0.02))
                    .padding(12)
                    .background(BodyMapView.amber.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("今日签到", systemImage: "moon.stars").font(.callout.weight(.semibold))
                            if let c = check {
                                HStack(spacing: 22) {
                                    mini(c.sleep.map(Fmt.number) ?? "—", c.sleep == nil ? "" : "h", "睡眠")
                                    mini(Fmt.fatigueLabel(c.fatigue), "", "疲劳")
                                    mini(c.painState == "有不适" ? "有" : (c.painState == nil ? "—" : "无"), "", "疼痛")
                                }
                                Button("修改签到") { goTo(.recovery) }.buttonStyle(.link)
                            } else {
                                Text("还没签到。睡眠、疲劳和疼痛会决定今天练多少。").font(.callout).foregroundStyle(.secondary)
                                Button("去签到") { goTo(.recovery) }.buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("本周", systemImage: "flame").font(.callout.weight(.semibold))
                            HStack(spacing: 22) {
                                mini("\(week.sessions)", "次", "力量")
                                mini(week.knownSets.map(String.init) ?? "—", week.knownSets == nil ? "" : "组", "已知组数")
                                mini(week.load > 0 ? "\(week.load)" : "—", "", "负荷分")
                            }
                            Button("看周报") { goTo(.weekly) }.buttonStyle(.link)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("上次训练", systemImage: "clock.arrow.circlepath").font(.callout.weight(.semibold))
                            if let l = last {
                                Text(l.title).font(.title3.weight(.semibold))
                                Text("\(l.date) · \(l.exercises.count) 个动作").font(.callout).foregroundStyle(.secondary)
                                Button("查看") { openSession(l) }.buttonStyle(.link)
                            } else {
                                Text("还没有记录").font(.callout).foregroundStyle(.secondary)
                                Button("记第一次训练", action: newSession).buttonStyle(.link)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("肌群恢复", systemImage: "figure.arms.open").font(.callout.weight(.semibold))
                        BodyMapView(mode: .recovery)
                    }
                }

            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
    }

    var body: some View {
        Group { if scrollable { ScrollView { content } } else { content } }
        .navigationTitle("今日")
    }

    private func mini(_ v: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(v).font(Brand.number(24))
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

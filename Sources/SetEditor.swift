import SwiftUI

/// 重量下拉：按口径给常用重量，标出上次，支持「— 未记录」和自定义
struct WeightMenu: View {
    @Binding var value: Double?
    let unit: String
    let last: Double?
    @State private var customOpen = false
    @State private var customText = ""

    private var options: [Double] {
        var o = ExerciseDraft.weightPresets(unit: unit)
        for v in [value, last].compactMap({ $0 }) where !o.contains(v) { o.append(v) }
        return o.sorted()
    }
    private func label(_ v: Double?) -> String { v.map { Fmt.number($0) + " kg" } ?? "—" }

    var body: some View {
        Menu {
            Button("— 未记录") { value = nil }
            Divider()
            ForEach(options, id: \.self) { v in
                Button {
                    value = v
                } label: {
                    if v == value { Label(label(v) + (v == last ? " · 上次" : ""), systemImage: "checkmark") }
                    else { Text(label(v) + (v == last ? " · 上次" : "")) }
                }
            }
            Divider()
            Button("自定义…") { customText = value.map(Fmt.number) ?? ""; customOpen = true }
        } label: {
            Text(label(value)).monospacedDigit()
        }
        .menuIndicator(.visible)
        .popover(isPresented: $customOpen, arrowEdge: .bottom) {
            HStack {
                TextField("重量", text: $customText).frame(width: 80)
                    .onSubmit(applyCustom)
                Text("kg").foregroundStyle(.secondary)
                Button("好", action: applyCustom).keyboardShortcut(.defaultAction)
            }.padding(12)
        }
    }

    private func applyCustom() {
        let t = customText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if t.isEmpty { value = nil; customOpen = false; return }
        if let v = Double(t), v >= 0, v.isFinite { value = v; customOpen = false }
    }
}

/// 一个动作的逐组录入：组数、口径、每组重量/次数/RIR 下拉
struct SetEditor: View {
    @Binding var ex: ExerciseDraft
    let last: ExerciseRecord?
    @AppStorage("syncDownSets") private var syncDown = true

    private func binding<T: Equatable>(_ i: Int, _ kp: WritableKeyPath<SetDraft, T>) -> Binding<T> {
        Binding(get: { ex.rows.indices.contains(i) ? ex.rows[i][keyPath: kp] : SetDraft()[keyPath: kp] },
                set: { ex.set(i, kp, $0, syncDown: syncDown) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Picker("组数", selection: Binding(get: { ex.rows.count }, set: { ex.setCount($0) })) {
                    ForEach(0...10, id: \.self) { n in Text(n == 0 ? "—" : "\(n)").tag(n) }
                }
                .fixedSize()
                .help("选组数会生成同样数量的行；新增的组默认带出上一组")
                Picker("口径", selection: $ex.unit) {
                    Text("—").tag("")
                    ForEach(ExerciseDraft.units, id: \.self) { Text($0).tag($0) }
                    if !ex.unit.isEmpty && !ExerciseDraft.units.contains(ex.unit) { Text(ex.unit).tag(ex.unit) }
                }
                .fixedSize()
                Toggle("改动同步到后面的组", isOn: $syncDown)
                    .toggleStyle(.checkbox)
                    .help("开启时，改某一组的重量/次数/RIR，后面数值相同的组会一起改")
                Spacer()
                if ex.pending > 0 {
                    Button { ex.confirmAll() } label: { Label("确认 \(ex.pending) 组", systemImage: "checkmark.circle") }
                        .help("确认带出的上次数值就是这次做的")
                }
            }
            if !ex.rows.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("组"); Text("重量"); Text("次数"); Text("RIR"); Text("")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(ex.rows.indices), id: \.self) { i in
                        GridRow {
                            Text("\(i + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
                            WeightMenu(value: binding(i, \.weight), unit: ex.unit, last: last?.weight)
                                .frame(width: 120)
                            Picker("次数", selection: binding(i, \.reps)) {
                                Text("—").tag(Int?.none)
                                ForEach(1...30, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                            }.labelsHidden().frame(width: 80)
                            Picker("RIR", selection: binding(i, \.rir)) {
                                Text("—").tag(Int?.none)
                                ForEach(0...5, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                            }.labelsHidden().frame(width: 70)
                            HStack(spacing: 8) {
                                Button { ex.duplicate(i) } label: { Image(systemName: "plus.square.on.square") }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("复制这一组，插在下面")
                                Button { ex.rows.remove(at: i) } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("删除这一组")
                            }
                        }
                        .opacity(ex.rows[i].confirmed ? 1 : 0.45)
                    }
                }
                if ex.pending > 0 {
                    Text("浅色的组是带出的上次数值：改动任意一项或点「确认」后才算这次的记录。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)        // 下拉菜单用中性色，主色只留给主按钮
    }
}

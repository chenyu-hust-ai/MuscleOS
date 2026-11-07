import SwiftUI
import UniformTypeIdentifiers

enum Page: String, CaseIterable, Identifiable {
    case today = "今日", training = "训练", progress = "进步", weekly = "周报", recovery = "恢复", plans = "计划", data = "数据与备份", me = "我的"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .training: return "dumbbell"
        case .progress: return "chart.xyaxis.line"
        case .weekly: return "calendar"
        case .recovery: return "heart.text.square"
        case .plans: return "list.bullet.clipboard"
        case .data: return "externaldrive"
        case .me: return "person.crop.circle"
        }
    }
}

enum Brand {
    static let accent = Color(red: 0.847, green: 0.353, blue: 0.188)      // #D85A30
    static let pain = Color(red: 0.729, green: 0.459, blue: 0.090)        // #BA7517
    static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

struct PlanBox: Identifiable { let id = UUID(); let plan: ImportPlan }

struct EditorTarget: Identifiable {
    let id = UUID()
    var session: WorkoutSession?
}

struct ContentView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var page: Page? = .today
    @State private var selection: String?
    @State private var editing: EditorTarget?
    @State private var pendingDelete: WorkoutSession?
    @State private var pickingFile = false
    @State private var importPlan: ImportPlan?
    @State private var importError: String?
    @State private var exportDoc: ExportDoc?

    private func edit(_ s: WorkoutSession) {
        if s.kind == "check" { store.checkDateRequest = Fmt.date(s.date); page = .recovery }
        else { editing = EditorTarget(session: s) }
    }
    private func open(_ s: WorkoutSession) {
        page = s.isPlan ? .plans : (s.kind == "check" ? .recovery : .training)
        selection = s.id
    }

    private var layout: some View {
        NavigationSplitView {
            List(selection: $page) {
                Section {
                    ForEach([Page.today, .training, .progress, .weekly, .recovery]) { p in
                        Label(p.rawValue, systemImage: p.icon).tag(p)
                    }
                }
                Section("规划") {
                    Label(Page.plans.rawValue, systemImage: Page.plans.icon).tag(Page.plans)
                }
                Section("数据") {
                    Label(Page.data.rawValue, systemImage: Page.data.icon).tag(Page.data)
                }
            }
            .safeAreaInset(edge: .bottom) {
                SidebarUserChip(selected: page == .me) { page = .me }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            switch page ?? .today {
            case .today:
                TodayView(goTo: { page = $0 }, openSession: open, newSession: { editing = EditorTarget(session: nil) })
            case .training:
                SessionBrowser(mode: .training, selection: $selection, onEdit: edit, onDelete: { pendingDelete = $0 })
            case .plans:
                SessionBrowser(mode: .plans, selection: $selection, onEdit: edit, onDelete: { pendingDelete = $0 })
            case .progress: ProgressPageView()
            case .weekly: WeeklyReportView()
            case .recovery: RecoveryView()
            case .data: DataPageView()
            case .me: ProfilePageView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { pickingFile = true } label: { Label("导入记录", systemImage: "square.and.arrow.down") }
                    .help("导入网页版或历史库导出的 JSON")
                    .accessibilityIdentifier("import-web")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { editing = EditorTarget(session: nil) } label: { Label("新建训练", systemImage: "plus") }
                    .help("新建训练（⌘N）")
                    .accessibilityIdentifier("new-session")
            }
        }
        .sheet(item: $editing) { target in
            Group {
                if let t = target.session, t.kind == "cardio" || t.kind == "tennis" {
                    ActivityEditor(session: t) { saved in open(saved); editing = nil } onCancel: { editing = nil }
                } else {
                    EditorView(session: target.session) { saved in
                        open(saved)
                        editing = nil
                    } onCancel: { editing = nil }
                }
            }
            .environmentObject(store)
        }
    }

    private var withSheets: some View {
        layout
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.json]) { result in
            switch result {
            case .failure(let e): importError = "无法打开文件：\(e.localizedDescription)"
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    importPlan = try WebImporter.plan(data: data, fileName: url.lastPathComponent,
                                                      existing: store.sessions, existingRevisions: store.revisions)
                } catch { importError = error.localizedDescription }
            }
        }
        .sheet(item: Binding(get: { importPlan.map { PlanBox(plan: $0) } }, set: { if $0 == nil { importPlan = nil } })) { box in
            ImportPreview(plan: box.plan) {
                if store.apply(box.plan) { importPlan = nil }
            } onCancel: { importPlan = nil }
        }
    }

    var body: some View {
        withSheets
        .onChange(of: store.importRequested) { _, _ in pickingFile = true }
        .onChange(of: store.exportRequested) { _, _ in
            do { exportDoc = ExportDoc(data: try DataExporter.data(sessions: store.sessions, revisions: store.revisions, profile: store.profile)) }
            catch { store.errorMessage = "导出失败：\(error.localizedDescription)" }
        }
        .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
                      document: exportDoc, contentType: .json, defaultFilename: "MuscleOS-\(Fmt.day(Date())).json") { result in
            if case .failure(let e) = result { store.errorMessage = "导出失败：\(e.localizedDescription)" }
            exportDoc = nil
        }
        .alert("导入失败", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("好") { importError = nil }
        } message: { Text(importError ?? "") }
        .onChange(of: store.newRequested) { _, _ in editing = EditorTarget(session: nil) }
        .onChange(of: store.pageRequest) { _, p in if let p { page = p; store.pageRequest = nil } }
        .onChange(of: page) { _, p in if p != .training { store.trainingMuscleFilter = nil } }
        .confirmationDialog("删除这条记录？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { s in
            Button("删除", role: .destructive) { store.delete(s.id); if selection == s.id { selection = nil } }
        } message: { s in Text("\(Fmt.dateText(s.date)) · \(s.title)，此操作无法撤销。") }
        .alert("提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .tint(Brand.accent)
    }
}

/// 训练 / 计划 两页共用：左列表右详情
struct SessionBrowser: View {
    enum Mode { case training, plans }
    @EnvironmentObject var store: WorkoutStore
    let mode: Mode
    @Binding var selection: String?
    let onEdit: (WorkoutSession) -> Void
    let onDelete: (WorkoutSession) -> Void
    @State private var showAll = false

    private var items: [WorkoutSession] {
        store.sessions.filter { s in
            switch mode {
            case .plans: return s.isPlan
            case .training:
                guard s.kind != "check" && !s.isPlan && (showAll || s.isActual) else { return false }
                return true
            }
        }
    }
    private var selected: WorkoutSession? { items.first { $0.id == selection } }

    var body: some View {
        if mode == .training, let m = store.trainingMuscleFilter {
            MuscleRecordsView(muscle: m, onEdit: onEdit, onDelete: onDelete)
                .id(m)
        } else {
            browser
        }
    }

    private var browser: some View {
        HSplitView {
            VStack(spacing: 0) {
                if mode == .training {
                    Picker("范围", selection: $showAll) {
                        Text("实绩").tag(false); Text("全部").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().padding(10)
                    .help("「全部」还包括历史基线、已取消、未确认的记录")
                }
                List(selection: $selection) {
                    ForEach(items) { s in
                        SessionRow(session: s)
                            .tag(s.id)
                            .accessibilityIdentifier("session-row")
                            .contextMenu {
                                Button("编辑") { onEdit(s) }
                                Button("删除…", role: .destructive) { onDelete(s) }
                            }
                    }
                }
                .onDeleteCommand { if let s = selected { onDelete(s) } }
                .overlay {
                    if items.isEmpty {
                        ContentUnavailableView(mode == .plans ? "还没有训练计划" : "还没有训练记录",
                                               systemImage: mode == .plans ? "list.bullet.clipboard" : "dumbbell",
                                               description: Text(mode == .plans ? "以后可以从今日推荐存为计划" : "点右上角 ＋ 记录第一次训练"))
                    }
                }
            }
            .frame(minWidth: 230, idealWidth: 260, maxWidth: 340)

            Group {
                if let s = selected {
                    SessionDetail(session: s, revisions: store.revisions.filter { $0.entry.id == s.id }.reversed(),
                                  onEdit: { onEdit(s) }, onDelete: { onDelete(s) })
                } else {
                    ContentUnavailableView(mode == .plans ? "选择一个计划" : "选择一次训练",
                                           systemImage: mode == .plans ? "list.bullet.clipboard" : "dumbbell")
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(mode == .plans ? "计划" : "训练")
    }
}

struct SessionRow: View {
    let session: WorkoutSession
    private var icon: String {
        switch session.kind {
        case "cardio": return "figure.run"
        case "tennis": return "figure.tennis"
        case "check": return "heart.text.square"
        default: return "dumbbell"
        }
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(session.isActual ? Brand.accent : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.headline).lineLimit(1)
                Text("\(Fmt.dateText(session.date)) · \(Fmt.summary(session))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if !session.isActual, let st = Fmt.statusLabel(session) {
                Text(st).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 3)
    }
}

struct SessionDetail: View {
    let session: WorkoutSession
    let revisions: [Revision]
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var highlightMuscle: String? = nil
    @State private var showOthers = false

    private var knownSets: Int? {
        let s = session.exercises.compactMap { $0.sets }
        return s.isEmpty ? nil : s.reduce(0, +)
    }
    private var load: Int {
        session.exercises.reduce(0) { acc, x in acc + (x.sets ?? 0) * max(0, 10 - (x.rir ?? 3)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Fmt.dateText(session.date)) · \(Fmt.typeLabel(session))").font(.subheadline).foregroundStyle(.secondary)
                        Text(session.title).font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Button { onEdit() } label: { Label(session.kind == "check" ? "去恢复页修改" : "编辑", systemImage: "pencil") }
                        .accessibilityIdentifier("edit-session")
                    Button(role: .destructive) { onDelete() } label: { Label("删除", systemImage: "trash") }
                        .accessibilityIdentifier("delete-session")
                }

                switch session.kind {
                case "strength":
                    HStack(spacing: 12) {
                        StatTile(label: "动作", value: "\(session.exercises.count)", unit: "个")
                        StatTile(label: "已知组数", value: knownSets.map(String.init) ?? "—", unit: knownSets == nil ? "" : "组")
                        StatTile(label: "负荷分", value: knownSets == nil ? "—" : "\(load)", unit: "")
                    }
                    if let m = highlightMuscle {
                        let related = session.exercises.filter { Muscles.coefficient($0, m) >= 0.5 }
                        let others = session.exercises.filter { Muscles.coefficient($0, m) < 0.5 }
                        ForEach(related) { r in
                            ExerciseCard(record: r)
                                .overlay(alignment: .topTrailing) {
                                    Text("与\(m)相关").font(.caption2.weight(.medium)).foregroundStyle(Brand.accent)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Brand.accent.opacity(0.12), in: Capsule())
                                        .padding(12).offset(y: -2)
                                }
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.accent.opacity(0.6), lineWidth: 1.2))
                        }
                        if !others.isEmpty {
                            DisclosureGroup(isExpanded: $showOthers) {
                                VStack(spacing: 12) { ForEach(others) { ExerciseCard(record: $0) } }.padding(.top, 8)
                            } label: {
                                Text("其他 \(others.count) 个动作：" + others.map { $0.name }.joined(separator: "、"))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        ForEach(session.exercises) { ExerciseCard(record: $0) }
                    }
                case "check":
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        StatTile(label: "睡眠", value: session.sleep.map(Fmt.number) ?? "—", unit: session.sleep == nil ? "" : "h")
                        StatTile(label: "疲劳", value: Fmt.fatigueLabel(session.fatigue), unit: "")
                        StatTile(label: "当前疼痛", value: Fmt.orDash(session.painState), unit: "")
                        StatTile(label: "蛋白质", value: session.protein.map(Fmt.number) ?? "—", unit: session.protein == nil ? "" : "g")
                    }
                    InfoCard(items: [("疼痛", Fmt.painText(session)), ("肌肉酸痛", Fmt.sorenessText(session.soreness)), ("蛋白粉", session.proteinTaken.map { $0 ? "喝了" : "没喝" }), ("恢复反馈", session.recovery)])
                default:
                    HStack(spacing: 12) {
                        StatTile(label: "用时", value: session.duration.map { Fmt.clock($0) } ?? "—", unit: "")
                        StatTile(label: "距离", value: session.distance.map(Fmt.number) ?? "—", unit: session.distance == nil ? "" : "m")
                        if session.kind == "cardio" { StatTile(label: "平均配速", value: Fmt.pace(session)?.replacingOccurrences(of: " / km", with: "") ?? "—", unit: Fmt.pace(session) == nil ? "" : "/km") }
                    }
                }

                if let n = session.note, !n.isEmpty {
                    InfoCard(items: [("备注", n)])
                }

                if !revisions.isEmpty {
                    DisclosureGroup("历史版本（\(revisions.count)）") {
                        ForEach(Array(revisions.enumerated()), id: \.offset) { _, r in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(r.at) · \(Fmt.dateText(r.entry.date)) · \(r.entry.title)").font(.callout.bold())
                                if r.entry.kind == "strength" {
                                    ExerciseTable(rows: r.entry.exercises).frame(height: CGFloat(60 + 28 * r.entry.exercises.count))
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let unit: String
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(Brand.number(26)).lineLimit(1).minimumScaleFactor(0.6)
                    if !unit.isEmpty { Text(unit).font(.callout).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

struct InfoCard: View {
    let items: [(String, String?)]
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.orDash(item.1)).textSelection(.enabled)
                    }
                }
            }
        }
    }
}

struct Chip: View {
    let icon: String
    let text: String
    var tint: Color = .secondary
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct ExerciseCard: View {
    let record: ExerciseRecord
    @State private var showNote = false

    private func stat(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(Brand.number(24))
                if !unit.isEmpty && value != "—" { Text(unit).font(.callout).foregroundStyle(.secondary) }
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(record.name).font(.title3.weight(.semibold))
                    if let m = Muscles.primary(record) { Chip(icon: "figure.arms.open", text: m) }
                    if let u = record.unit { Chip(icon: "scalemass", text: u) }
                    Spacer()
                    if record.hasPain { Chip(icon: "exclamationmark.triangle.fill", text: "有疼痛", tint: Brand.pain) }
                }
                HStack(alignment: .top, spacing: 28) {
                    stat(record.weight.map(Fmt.number) ?? "—", "kg", "重量")
                    stat(record.setsText, "组", "组数")
                    stat(record.repsText, "次", "次数")
                    stat(record.rirText, "", "末组 RIR")
                    if let e = record.e1rm { stat(String(format: "%.1f", e), "kg", "估算 1RM") }
                }
                if let log = record.setLog, log.count > 1 {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                        ForEach(Array(log.enumerated()), id: \.offset) { i, s in
                            GridRow {
                                Text("第 \(i + 1) 组").foregroundStyle(.secondary)
                                Text(s.weight.map { Fmt.number($0) + " kg" } ?? "—")
                                Text("× " + (s.reps.map(String.init) ?? "—"))
                                Text("RIR " + (s.rir.map(String.init) ?? "—")).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.callout.monospacedDigit())
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                let chips: [(String, String, String?, Color)] = [
                    ("hand.raised", "发力", record.feel, .secondary),
                    ("bandage", "疼痛", record.pain, Brand.pain),
                    ("arrow.counterclockwise", "恢复", record.recovery, .secondary)]
                let shown = chips.filter { !($0.2 ?? "").isEmpty }
                if !shown.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(shown, id: \.1) { c in Chip(icon: c.0, text: "\(c.1)：\(c.2!)", tint: c.3) }
                    }
                }
                if let n = record.note, !n.isEmpty {
                    DisclosureGroup("备注", isExpanded: $showNote) {
                        Text(n).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }.font(.callout)
                }
            }
        }
    }
}

struct ExerciseTable: View {
    let rows: [ExerciseRecord]
    var body: some View {
        Table(rows) {
            TableColumn("动作") { Text($0.name).bold() }.width(min: 90, ideal: 120)
            TableColumn("重量") { Text($0.weightText) }.width(min: 80, ideal: 110)
            TableColumn("组数") { Text($0.setsText) }.width(50)
            TableColumn("次数") { Text(Fmt.orDash($0.reps)) }.width(min: 50, ideal: 70)
            TableColumn("末组 RIR") { Text($0.rirText) }.width(60)
            TableColumn("发力感") { Text(Fmt.orDash($0.feel)) }
            TableColumn("疼痛") { Text(Fmt.orDash($0.pain)) }
            TableColumn("恢复") { Text(Fmt.orDash($0.recovery)) }
            TableColumn("备注") { Text(Fmt.orDash($0.note)) }.width(min: 120, ideal: 220)
        }
        .frame(minHeight: 200)
    }
}

struct ImportPreview: View {
    let plan: ImportPlan
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("文件：\(plan.fileName)") {
                    LabeledContent("文件内记录", value: "\(plan.totalEntries) 条")
                    LabeledContent("将新增", value: "\(plan.toAdd.count) 条").foregroundStyle(.green)
                    LabeledContent("将跳过", value: "\(plan.skippedCount) 条（已存在 \(plan.duplicates.count)，冲突 \(plan.conflicts.count)，无法识别 \(plan.invalid.count)）")
                    LabeledContent("历史修订", value: "新增 \(plan.newRevisions.count) 条，已存在 \(plan.duplicateRevisions) 条")
                }
                if !plan.toAdd.isEmpty {
                    Section("新增记录") {
                        ForEach(plan.toAdd) { e in
                            Text("\(Fmt.dateText(e.date)) · \(Fmt.typeLabel(e)) · \(e.title) · \(Fmt.summary(e))")
                        }
                    }
                }
                if !plan.conflicts.isEmpty {
                    Section("冲突（保留本机版本，不会覆盖）") {
                        ForEach(plan.conflicts) { c in
                            VStack(alignment: .leading) {
                                Text("\(c.incoming.id)：本机「\(c.local.title)」\(Fmt.dateText(c.local.date)) ／ 网页「\(c.incoming.title)」\(Fmt.dateText(c.incoming.date))")
                                Text("不同之处：" + c.fields.joined(separator: "、")).font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                if !plan.invalid.isEmpty || !plan.warnings.isEmpty {
                    Section("提示") {
                        ForEach(plan.invalid + plan.warnings, id: \.self) { Text($0).foregroundStyle(.secondary) }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if !plan.hasChanges { Text("没有需要导入的新内容").foregroundStyle(.secondary) }
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("确认导入", action: onConfirm).keyboardShortcut(.defaultAction)
                    .disabled(!plan.hasChanges).accessibilityIdentifier("confirm-import")
            }.padding(12)
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

struct EditorView: View {
    @EnvironmentObject var store: WorkoutStore
    let isNew: Bool
    let onSaved: (WorkoutSession) -> Void
    let onCancel: () -> Void
    var scrollable = true
    @State private var draft: SessionDraft
    @State private var showErrors = false
    @State private var confirmCopy = false

    private var dayRef: String? { draft.dateUnknown ? nil : Fmt.day(draft.date) }
    private var lastSession: WorkoutSession? { History.lastSession(onOrBefore: dayRef, excluding: draft.id, sessions: store.sessions) }
    private func copyLast(_ s: WorkoutSession) {
        draft.exercises = s.exercises.map { r in
            var d = ExerciseDraft(r); d.id = UUID(); d.feel = ""; d.pain = ""; d.recovery = ""
            for i in d.rows.indices { d.rows[i].confirmed = false }     // 复制来的数值都要确认
            return d
        }
        if draft.title.trimmingCharacters(in: .whitespaces).isEmpty { draft.title = s.title }
    }
    private func lastRecord(_ name: String) -> (day: String, record: ExerciseRecord)? {
        History.lastRecord(name: name.trimmingCharacters(in: .whitespaces), onOrBefore: dayRef, excluding: draft.id, sessions: store.sessions)
    }

    init(session: WorkoutSession?, scrollable: Bool = true, onSaved: @escaping (WorkoutSession) -> Void, onCancel: @escaping () -> Void) {
        isNew = session == nil
        self.scrollable = scrollable
        _draft = State(initialValue: session.map(SessionDraft.init) ?? SessionDraft())
        self.onSaved = onSaved; self.onCancel = onCancel
    }

    private func field(_ label: String, _ text: Binding<String>, _ prompt: String = "—") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text, prompt: Text(prompt)).textFieldStyle(.roundedBorder).labelsHidden()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "新建训练" : "编辑训练").font(.system(size: 24, weight: .bold, design: .rounded))

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("训练日期").font(.caption).foregroundStyle(.secondary)
                            DatePicker("训练日期", selection: $draft.date, displayedComponents: .date)
                                .labelsHidden().datePickerStyle(.field).disabled(draft.dateUnknown)
                        }
                        Toggle("日期待核对", isOn: $draft.dateUnknown).toggleStyle(.checkbox).padding(.top, 16)
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        field("标题（可选）", $draft.title, "比如：肩部强化")
                        field("备注（可选）", $draft.note)
                    }
                }
            }

            if isNew, let last = lastSession {
                HStack {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Brand.accent)
                    Text("上次训练：\(last.date) · \(last.title) · \(last.exercises.count) 个动作").font(.callout)
                    Spacer()
                    Button("复制上次训练") {
                        if draft.exercises.contains(where: { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }) { confirmCopy = true }
                        else { copyLast(last) }
                    }.accessibilityIdentifier("copy-last")
                }
                .padding(12)
                .background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            ForEach($draft.exercises) { $ex in
                let idx = draft.exercises.firstIndex { $0.id == ex.id } ?? 0
                let autoFill = { (name: String) in
                    guard ex.perSet, ex.rows.allSatisfy({ $0.isBlank }), let l = lastRecord(name) else { return }
                    ex.prefill(from: l.record)
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Text("\(idx + 1)").font(Brand.number(15)).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(Brand.accent, in: Circle())
                            TextField("动作名称", text: $ex.name, prompt: Text("动作名称（必填）"))
                                .textFieldStyle(.roundedBorder).labelsHidden()
                                .font(.title3)
                                .onSubmit { autoFill(ex.name) }
                                .accessibilityIdentifier("exercise-name")
                            Menu("动作库") {
                                ForEach(exerciseCatalog, id: \.name) { item in
                                    Button(item.name) { ex.name = item.name; ex.muscle = item.muscle; ex.unit = item.unit; autoFill(item.name) }
                                }
                            }.fixedSize().tint(.primary)
                            Button(role: .destructive) { draft.exercises.removeAll { $0.id == ex.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).help("移除这个动作")
                        }
                        if let last = lastRecord(ex.name) {
                            HStack(spacing: 8) {
                                Text("上次 \(last.day) · \(History.describe(last.record))").font(.caption).foregroundStyle(.secondary)
                                if last.record.hasPain { Chip(icon: "bandage", text: "上次疼痛：\(last.record.pain ?? "")", tint: Brand.pain) }
                                Spacer()
                                Button("带入上次") { ex.prefill(from: last.record) }.buttonStyle(.link).font(.caption)
                            }.accessibilityIdentifier("last-hint")
                        }
                        let warns = ProfileStats.injuryWarnings(ex.name, store.profile)
                        if !warns.isEmpty {
                            ForEach(warns) { w in
                                Label("注意：\(w.area) · \(w.note.isEmpty ? w.status : w.note)（\(w.status)），留意动作和重量", systemImage: "bandage.fill")
                                    .font(.caption).foregroundStyle(Brand.pain)
                                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Brand.pain.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        Divider()
                        if ex.perSet {
                            SetEditor(ex: $ex, last: lastRecord(ex.name)?.record)
                        } else {
                            HStack(spacing: 10) {
                                field("重量 kg", $ex.weight); field("组数", $ex.sets); field("次数", $ex.reps); field("末组 RIR", $ex.rir)
                            }
                            field("重量口径", $ex.unit)
                            HStack {
                                Text("这条旧记录组数未知或次数是文字，保留原样。").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("改为逐组录入") { ex.prefill(from: ex.record()) }.buttonStyle(.link).font(.caption)
                            }
                        }
                        Divider()
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow { field("发力感", $ex.feel); field("疼痛", $ex.pain) }
                            GridRow { field("恢复", $ex.recovery); field("备注", $ex.note) }
                        }
                    }
                }
            }

            Button { draft.exercises.append(ExerciseDraft()) } label: { Label("添加动作", systemImage: "plus") }
                .controlSize(.large)

            if showErrors, !draft.errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(draft.errors, id: \.self) { Label($0, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(24)
    }

    var body: some View {
        VStack(spacing: 0) {
            if scrollable { ScrollView { content } } else { content }
            Divider()
            HStack {
                Text(draft.exercises.isEmpty ? "" : "\(draft.exercises.count) 个动作 · \(draft.exercises.reduce(0) { $0 + ($1.perSet ? $1.rows.count : (Int($1.sets) ?? 0)) }) 组")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") {
                    if draft.errors.isEmpty {
                        let s = draft.session()
                        if store.save(s) { onSaved(s) }
                    } else { showErrors = true }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("save")
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(minWidth: 760, idealWidth: 800, minHeight: 640, idealHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Brand.accent)
        .confirmationDialog("用上次训练替换当前动作？", isPresented: $confirmCopy) {
            Button("替换", role: .destructive) { if let l = lastSession { copyLast(l) } }
        }
    }
}


struct ActivityEditor: View {
    @EnvironmentObject var store: WorkoutStore
    let base: WorkoutSession
    let onSaved: (WorkoutSession) -> Void
    let onCancel: () -> Void
    @State private var date: Date
    @State private var dateUnknown: Bool
    @State private var title: String
    @State private var duration: String
    @State private var distance: String
    @State private var note: String
    @State private var error = ""

    init(session: WorkoutSession, onSaved: @escaping (WorkoutSession) -> Void, onCancel: @escaping () -> Void) {
        base = session; self.onSaved = onSaved; self.onCancel = onCancel
        _date = State(initialValue: Fmt.date(session.date) ?? Date())
        _dateUnknown = State(initialValue: Fmt.date(session.date) == nil)
        _title = State(initialValue: session.title)
        _duration = State(initialValue: session.duration.map { Fmt.clock($0) } ?? "")
        _distance = State(initialValue: session.distance.map(Fmt.number) ?? "")
        _note = State(initialValue: session.note ?? "")
    }

    private func parseDuration(_ t: String) -> Double?? {      // nil = 非法；.some(nil) = 留空
        let t = t.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .some(nil) }
        let parts = t.split(separator: ":").map(String.init)
        if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]), m >= 0, s >= 0, s < 60 { return .some(m * 60 + s) }
        if parts.count == 1, let m = Double(parts[0].replacingOccurrences(of: ",", with: ".")), m >= 0 { return .some(m * 60) }
        return nil
    }

    private func save() {
        guard let dur = parseDuration(duration) else { error = "用时请填 13:20 或分钟数"; return }
        var dist: Double?
        let dt = distance.trimmingCharacters(in: .whitespaces)
        if !dt.isEmpty { guard let v = Double(dt.replacingOccurrences(of: ",", with: ".")), v >= 0 else { error = "距离需为不小于 0 的数字（米）"; return }; dist = v }
        var s = base
        s.date = dateUnknown ? "" : Fmt.day(date)
        let t = title.trimmingCharacters(in: .whitespaces)
        s.title = t.isEmpty ? (base.kind == "cardio" ? "有氧" : "网球") : t
        s.duration = dur; s.distance = dist
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines); s.note = n.isEmpty ? nil : n
        if store.save(s) { onSaved(s) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                DatePicker("日期", selection: $date, displayedComponents: .date).disabled(dateUnknown)
                Toggle("日期待核对（暂不填日期）", isOn: $dateUnknown)
                TextField("标题", text: $title, prompt: Text("—"))
                TextField("用时（13:20 或分钟）", text: $duration, prompt: Text("—"))
                TextField("距离（米）", text: $distance, prompt: Text("—"))
                TextField("备注", text: $note, prompt: Text("—"))
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction)
            }.padding(12)
        }
        .frame(minWidth: 460, minHeight: 360)
    }
}

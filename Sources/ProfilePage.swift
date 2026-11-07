import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Avatar: View {
    let profile: Profile
    var size: CGFloat = 28
    var body: some View {
        if let d = profile.avatar, let img = NSImage(data: d) {
            Image(nsImage: img).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
        } else {
            Text(profile.initial)
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Brand.accent, in: Circle())
        }
    }
}

enum AvatarImage {
    /// 居中裁成正方形，缩到 256 像素，存成 JPEG（约几十 KB）
    static func process(_ image: NSImage, side: Int = 256) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height, m = min(w, h)
        guard m > 0, let crop = cg.cropping(to: CGRect(x: (w - m) / 2, y: (h - m) / 2, width: m, height: m)) else { return nil }
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
    static func load(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return NSImage(contentsOf: url).flatMap { process($0) }
    }
}

enum ProfileStats {
    static func trainings(_ s: [WorkoutSession]) -> [WorkoutSession] { s.filter { $0.isActual && $0.kind != "check" && !$0.date.isEmpty } }
    static func summary(_ s: [WorkoutSession]) -> String {
        let t = trainings(s)
        guard let first = t.map({ $0.date }).min(), let d = Fmt.date(first) else { return "还没有训练记录" }
        let weeks = max(1, (Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0) / 7 + 1)
        return "\(first) 开始记录 · 共 \(t.count) 次训练 · \(weeks) 周"
    }
    /// 录入某动作时要提醒的伤病：伤病部位对应的肌群被这个动作主练或主要协同，或备注里提到这个动作
    static func injuryWarnings(_ name: String, _ profile: Profile) -> [Injury] {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return [] }
        let probe = ExerciseRecord(name: n)
        let ms = Set(Muscles.contributions(probe).filter { $0.1 >= 0.5 }.map { $0.0 })
        return profile.activeInjuries.filter { inj in
            inj.note.contains(n) || !(Set(Muscles.painMap[inj.area] ?? []).isDisjoint(with: ms))
        }
    }
}

/// 侧边栏左下角的用户入口
struct SidebarUserChip: View {
    @EnvironmentObject var store: WorkoutStore
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Avatar(profile: store.profile, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.profile.nickname.isEmpty ? "我" : store.profile.nickname).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("第 \(ProfileStats.trainings(store.sessions).count) 次训练").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .padding(8)
            .background(selected ? Brand.accent.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(10)
        .help("我的：昵称、基本信息、伤病与注意")
    }
}

struct ProfilePageView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var editingName = false
    @State private var nameText = ""
    @State private var pickingAvatar = false
    @State private var hoverAvatar = false
    @State private var dropTarget = false
    @State private var avatarError: String?
    var scrollable = true

    private func setAvatar(_ data: Data?) {
        guard let data else { avatarError = "这个文件读不出图片，换一张试试"; return }
        avatarError = nil
        update { $0.avatar = data }
    }

    private func update(_ change: (inout Profile) -> Void) {
        var p = store.profile; change(&p); store.saveProfile(p)
    }
    private func binding<T>(_ kp: WritableKeyPath<Profile, T>) -> Binding<T> {
        Binding(get: { store.profile[keyPath: kp] }, set: { v in update { $0[keyPath: kp] = v } })
    }

    private var content: some View {
        let p = store.profile
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Avatar(profile: p, size: 64)
                    .overlay {
                        if hoverAvatar || dropTarget {
                            Circle().fill(.black.opacity(0.45))
                            Image(systemName: "camera.fill").foregroundStyle(.white)
                        }
                    }
                    .overlay(Circle().strokeBorder(Brand.accent, lineWidth: dropTarget ? 2 : 0))
                    .onHover { hoverAvatar = $0 }
                    .onTapGesture { pickingAvatar = true }
                    .help("点击更换头像，也可以把图片拖到这里")
                    .onDrop(of: [.fileURL, .image], isTargeted: $dropTarget) { providers in
                        guard let pr = providers.first else { return false }
                        if pr.canLoadObject(ofClass: URL.self) {
                            _ = pr.loadObject(ofClass: URL.self) { url, _ in
                                let d = url.flatMap { AvatarImage.load($0) }
                                DispatchQueue.main.async { setAvatar(d) }
                            }
                            return true
                        }
                        _ = pr.loadObject(ofClass: NSImage.self) { img, _ in
                            let d = (img as? NSImage).flatMap { AvatarImage.process($0) }
                            DispatchQueue.main.async { setAvatar(d) }
                        }
                        return true
                    }
                VStack(alignment: .leading, spacing: 4) {
                    if editingName {
                        TextField("昵称", text: $nameText).textFieldStyle(.roundedBorder).frame(width: 200)
                            .onSubmit { update { $0.nickname = nameText.trimmingCharacters(in: .whitespaces) }; editingName = false }
                    } else {
                        Text(p.nickname.isEmpty ? "我" : p.nickname).font(.system(size: 26, weight: .bold, design: .rounded))
                    }
                    Text(ProfileStats.summary(store.sessions)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Menu("头像") {
                    Button("从文件选择…") { pickingAvatar = true }
                    if p.avatar != nil { Button("移除头像", role: .destructive) { update { $0.avatar = nil } } }
                }
                .fixedSize()
                Button(editingName ? "完成" : "编辑昵称") {
                    if editingName { update { $0.nickname = nameText.trimmingCharacters(in: .whitespaces) } }
                    else { nameText = p.nickname }
                    editingName.toggle()
                }
            }

            if let e = avatarError { Text(e).font(.caption).foregroundStyle(.red) }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("基本信息", systemImage: "person").font(.callout.weight(.semibold))
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        GridRow {
                            Text("身高").foregroundStyle(.secondary)
                            Picker("身高", selection: binding(\.height)) {
                                Text("—").tag(Int?.none)
                                ForEach(Array(140...220), id: \.self) { Text("\($0) cm").tag(Int?.some($0)) }
                            }.labelsHidden().fixedSize()
                            Text("年龄").foregroundStyle(.secondary)
                            Picker("年龄", selection: binding(\.age)) {
                                Text("—").tag(Int?.none)
                                ForEach(Array(12...80), id: \.self) { Text("\($0) 岁").tag(Int?.some($0)) }
                            }.labelsHidden().fixedSize()
                        }
                        GridRow {
                            Text("体重").foregroundStyle(.secondary)
                            Picker("体重", selection: binding(\.weight)) {
                                Text("— 没秤").tag(Double?.none)
                                ForEach(Array(stride(from: 40.0, through: 130.0, by: 0.5)), id: \.self) { Text(Fmt.number($0) + " kg").tag(Double?.some($0)) }
                            }.labelsHidden().fixedSize()
                            Text("每周训练").foregroundStyle(.secondary)
                            Picker("每周训练", selection: binding(\.weeklySessions)) {
                                Text("—").tag(String?.none)
                                ForEach(["1–2 次", "3 次", "4–5 次", "6 次以上"], id: \.self) { Text($0).tag(String?.some($0)) }
                            }.labelsHidden().fixedSize()
                        }
                    }
                    Text("只做记录展示，不参与任何计算").font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(.primary)

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Label("伤病与注意", systemImage: "exclamationmark.triangle").font(.callout.weight(.semibold))
                        Text("录入相关动作时会提醒").font(.caption).foregroundStyle(.secondary)
                    }
                    if p.injuries.isEmpty {
                        Text("没有需要注意的部位").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(p.injuries) { inj in
                        let idx = p.injuries.firstIndex { $0.id == inj.id }!
                        let healed = inj.status == "已痊愈"
                        HStack(spacing: 10) {
                            Image(systemName: "bandage").foregroundStyle(healed ? Color.secondary : Brand.pain)
                            Picker("部位", selection: binding(\.injuries[idx].area)) {
                                ForEach(RecoveryView.painParts + (RecoveryView.painParts.contains(inj.area) ? [] : [inj.area]), id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().fixedSize()
                            TextField("情况，比如：深蹲时膝盖不适", text: binding(\.injuries[idx].note))
                                .textFieldStyle(.roundedBorder)
                            Picker("状态", selection: binding(\.injuries[idx].status)) {
                                ForEach(Profile.statuses, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().fixedSize()
                            Button { update { $0.injuries.removeAll { $0.id == inj.id } } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("删除")
                        }
                        .padding(10)
                        .background((healed ? Color.primary.opacity(0.04) : Brand.pain.opacity(0.10)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .tint(.primary)
                    }
                    Button { update { $0.injuries.append(Injury(area: "肩", note: "", status: "仍有不适")) } } label: { Label("添加部位", systemImage: "plus") }
                        .buttonStyle(.borderless)
                    Text("「已痊愈」的不再提醒。部位按：肩→三角肌，肘→手臂，手腕→前臂，腰→竖脊肌，髋→臀和大腿内外侧，膝→大腿前后侧，脚踝→小腿；情况里写了动作名的，也会在录入那个动作时提醒。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 820, alignment: .leading)
    }

    var body: some View {
        Group { if scrollable { ScrollView { content } } else { content } }
            .navigationTitle("我的")
            .fileImporter(isPresented: $pickingAvatar, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result { setAvatar(AvatarImage.load(url)) }
            }
    }
}

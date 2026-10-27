import SwiftUI

/// 收藏相关页面的加载状态。
enum CollectStatus: Equatable {
    case loading
    case loaded
    case notLoggedIn
    case failed(String)
}

extension View {
    /// 轻提示（对应 H5 toast）：底部悬浮胶囊，1.8 秒自动消失。
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.8), in: Capsule())
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(1.8))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.snappy, value: message)
    }
}

/// 「我的收藏」收藏盒列表（对应 H5 收藏列表 + 新建收藏）。
struct FavoritesView: View {
    @State private var boxes: [CollectBox] = []
    @State private var status: CollectStatus = .loading
    @State private var toast: String?
    @State private var showCreate = false
    @State private var newBoxName = ""
    @State private var showLogin = false

    var body: some View {
        Group {
            switch status {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notLoggedIn:
                loginPrompt
            case .failed(let message):
                retryView(message)
            case .loaded:
                if boxes.isEmpty {
                    ContentUnavailableView("还没有收藏盒",
                                           systemImage: "star.square.on.square",
                                           description: Text("播放页点星标按钮，即可把歌曲收进收藏盒"))
                } else {
                    boxList
                }
            }
        }
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .toolbar {
            if status == .loaded {
                Button {
                    newBoxName = ""
                    showCreate = true
                } label: {
                    Label("新建收藏盒", systemImage: "plus")
                }
            }
        }
        .alert("新建收藏盒", isPresented: $showCreate) {
            TextField("音乐盒名称", text: $newBoxName)
            Button("创建") { Task { await create() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("给收藏盒取个名字")
        }
        .sheet(isPresented: $showLogin) {
            LoginFlowView { Task { await load() } }
        }
        .toast($toast)
    }

    private var boxList: some View {
        List(boxes) { box in
            NavigationLink {
                CollectBoxDetailView(box: box)
            } label: {
                Label(box.title, systemImage: "folder")
            }
        }
    }

    private var loginPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("登录已过期")
                .font(.headline)
            Text("登录后可查看收藏盒并收藏歌曲")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("重新登录") { showLogin = true }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retryView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") { Task { await load() } }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private func load() async {
        status = .loading
        do {
            boxes = try await DjuuAPI.collectBoxes()
            status = .loaded
        } catch DjuuError.server(DjuuAPI.notLoggedInCode, _) {
            status = .notLoggedIn
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func create() async {
        let name = newBoxName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            toast = try await DjuuAPI.createCollectBox(name: name)
            await load()
        } catch {
            toast = error.localizedDescription
        }
    }
}

/// 播放页收藏面板：选择收藏盒后 addmusic。
/// H5 前端没有「已收藏」状态，按钮不指示收藏与否，结果由服务端返回。
struct CollectPickerSheet: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var boxes: [CollectBox] = []
    @State private var status: CollectStatus = .loading
    @State private var busyBoxID: Int?
    @State private var toast: String?
    @State private var showCreate = false
    @State private var newBoxName = ""
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            Group {
                switch status {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .notLoggedIn:
                    loginPrompt
                case .failed(let message):
                    retryView(message)
                case .loaded:
                    boxList
                }
            }
            .navigationTitle("收藏到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if status == .loaded {
                    Button {
                        newBoxName = ""
                        showCreate = true
                    } label: {
                        Label("新建收藏盒", systemImage: "plus")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
        .alert("新建收藏盒", isPresented: $showCreate) {
            TextField("音乐盒名称", text: $newBoxName)
            Button("创建") { Task { await create() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("给收藏盒取个名字")
        }
        .sheet(isPresented: $showLogin) {
            LoginFlowView { Task { await load() } }
        }
        .toast($toast)
    }

    private var boxList: some View {
        List {
            if player.currentTrack == nil {
                Text("当前没有正在播放的歌曲")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(boxes) { box in
                Button {
                    Task { await addTo(box) }
                } label: {
                    HStack {
                        Label(box.title, systemImage: "folder")
                            .foregroundStyle(.primary)
                        Spacer()
                        if busyBoxID == box.id {
                            ProgressView()
                        }
                    }
                }
                .disabled(player.currentTrack == nil || busyBoxID != nil)
            }
        }
    }

    private var loginPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("登录已过期")
                .font(.headline)
            Text("登录后才能收藏歌曲")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("重新登录") { showLogin = true }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retryView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") { Task { await load() } }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private func load() async {
        status = .loading
        do {
            boxes = try await DjuuAPI.collectBoxes()
            status = .loaded
        } catch DjuuError.server(DjuuAPI.notLoggedInCode, _) {
            status = .notLoggedIn
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func addTo(_ box: CollectBox) async {
        guard let track = player.currentTrack, busyBoxID == nil else { return }
        busyBoxID = box.id
        defer { busyBoxID = nil }
        do {
            toast = try await DjuuAPI.addToCollect(boxID: box.id, musicID: track.id)
            Haptics.success()
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
        } catch {
            // 已收藏等情况由服务端返回错误信息，面板保持打开。
            Haptics.failure()
            toast = error.localizedDescription
        }
    }

    private func create() async {
        let name = newBoxName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            toast = try await DjuuAPI.createCollectBox(name: name)
            await load()
        } catch {
            toast = error.localizedDescription
        }
    }
}

/// 收藏盒内容（H5 /user/collect?action=getlist）：盒内曲目列表，点曲即播。
struct CollectBoxDetailView: View {
    let box: CollectBox

    @Environment(PlayerModel.self) private var player
    @State private var tracks: [Track] = []
    @State private var status: CollectStatus = .loading
    @State private var showLogin = false

    var body: some View {
        Group {
            switch status {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notLoggedIn:
                loginPrompt
            case .failed(let message):
                retryView(message)
            case .loaded:
                if tracks.isEmpty {
                    ContentUnavailableView("盒子还是空的",
                                           systemImage: "square.stack",
                                           description: Text("播放页点星标按钮，即可把歌曲收进这个盒子"))
                } else {
                    List {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(index: index + 1,
                                     track: track,
                                     isCurrent: player.currentTrack?.id == track.id,
                                     onPlay: { player.play(track, in: tracks) },
                                     onPlayNext: nil)
                        }
                    }
                }
            }
        }
        .navigationTitle(box.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showLogin) {
            LoginFlowView { Task { await load() } }
        }
    }

    private var loginPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("登录已过期")
                .font(.headline)
            Text("登录后可查看收藏盒里的歌曲")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("重新登录") { showLogin = true }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retryView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") { Task { await load() } }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private func load() async {
        status = .loading
        do {
            tracks = try await DjuuAPI.collectTracks(boxID: box.id)
            status = .loaded
        } catch DjuuError.server(DjuuAPI.notLoggedInCode, _) {
            status = .notLoggedIn
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

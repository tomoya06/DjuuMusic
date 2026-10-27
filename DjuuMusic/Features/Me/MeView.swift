import SwiftUI

struct MeView: View {
    @Environment(PlayerModel.self) private var player

    @State private var profile: UserProfile?
    @State private var history: [Track] = []
    @State private var collectBoxes: [CollectBox] = []
    @State private var showLogin = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            meList
        }
    }

    private var meList: some View {
        List {
            if let profile {
                profileSection(profile)
                collectSection
                historySection
                Button(role: .destructive) {
                    confirmLogout = true
                } label: {
                    Text("退出登录")
                        .frame(maxWidth: .infinity)
                }
            } else {
                loginPrompt
            }
        }
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            profile = LocalStore.profile
            history = LocalStore.history
        }
        .task { await loadCollectBoxes() }
        .sheet(isPresented: $showLogin) {
            LoginFlowView {
                profile = LocalStore.profile
                Task { await loadCollectBoxes() }
            }
        }
        .confirmationDialog("退出后收藏与服务端会话将失效，确定退出？",
                            isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                LocalStore.logout()
                profile = nil
                collectBoxes = []
            }
        }
    }

    // MARK: - Sections

    /// 收藏歌单直接平铺在个人中心，点击直达盒内容，少一次跳转。
    private var collectSection: some View {
        Section("我的收藏歌单") {
            if collectBoxes.isEmpty {
                NavigationLink {
                    FavoritesView()
                } label: {
                    Label("我的收藏", systemImage: "star")
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(collectBoxes) { box in
                            NavigationLink {
                                CollectBoxDetailView(box: box)
                            } label: {
                                boxCard(icon: "folder.fill", title: box.title)
                            }
                            .buttonStyle(.plain)
                        }
                        NavigationLink {
                            FavoritesView()
                        } label: {
                            boxCard(icon: "folder.badge.plus", title: "全部收藏盒")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func boxCard(icon: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.55)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(width: 112, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    private func loadCollectBoxes() async {
        guard LocalStore.profile != nil else {
            collectBoxes = []
            return
        }
        collectBoxes = (try? await DjuuAPI.collectBoxes()) ?? []
    }

    private func profileSection(_ profile: UserProfile) -> some View {
        Section {
            HStack(spacing: 14) {
                AsyncImage(url: profile.avatar.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(profile.username)
                            .font(.headline)
                        if profile.isVIP {
                            Text("VIP")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text("UID \(profile.uid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    /// 个人中心只露出最近 5 条，全量列表、滑动删除与清空都在 HistoryView。
    private var historySection: some View {
        Section {
            if history.isEmpty {
                Text("暂无播放历史")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history.prefix(5)) { track in
                    TrackRow(index: nil,
                             track: track,
                             isCurrent: player.currentTrack?.id == track.id,
                             onPlay: { player.play(track, in: history) },
                             onPlayNext: nil)
                }
                .onDelete { offsets in
                    for offset in offsets where history.indices.contains(offset) {
                        LocalStore.removeHistory(id: history[offset].id)
                    }
                    history = LocalStore.history
                }
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("查看全部播放历史（共 \(history.count) 条）",
                          systemImage: "clock.arrow.circlepath")
                }
            }
        } header: {
            Text("播放历史")
        }
    }

    private var loginPrompt: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
                Text("登录 DJ呦呦")
                    .font(.headline)
                Text("登录后可同步收藏，畅听全部高音质 DJ 舞曲")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showLogin = true
                } label: {
                    Text("手机号登录")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
            }
            .padding(.vertical, 18)
        }
    }
}

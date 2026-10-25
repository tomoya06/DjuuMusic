import SwiftUI

struct MeView: View {
    @Environment(PlayerModel.self) private var player

    @State private var profile: UserProfile?
    @State private var history: [Track] = []
    @State private var showLogin = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            List {
                if let profile {
                    profileSection(profile)
                    Section {
                        NavigationLink {
                            FavoritesView()
                        } label: {
                            Label("我的收藏", systemImage: "star")
                        }
                    }
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
            .sheet(isPresented: $showLogin) {
                LoginFlowView {
                    profile = LocalStore.profile
                }
            }
            .confirmationDialog("退出后收藏与服务端会话将失效，确定退出？",
                                isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    LocalStore.logout()
                    profile = nil
                }
            }
        }
    }

    // MARK: - Sections

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

    private var historySection: some View {
        Section {
            if history.isEmpty {
                Text("暂无播放历史")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history) { track in
                    TrackRow(index: nil,
                             track: track,
                             isCurrent: player.currentTrack?.id == track.id,
                             onPlay: { player.play(track, in: history) },
                             onPlayNext: nil)
                }
                .onDelete { offsets in
                    for offset in offsets {
                        if history.indices.contains(offset) {
                            LocalStore.removeHistory(id: history[offset].id)
                        }
                    }
                    history = LocalStore.history
                }
                Button(role: .destructive) {
                    LocalStore.clearHistory()
                    history = []
                } label: {
                    Text("清空播放历史")
                        .frame(maxWidth: .infinity)
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

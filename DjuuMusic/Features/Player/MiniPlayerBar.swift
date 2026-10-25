import SwiftUI

/// 常驻迷你播放条：液态玻璃胶囊，悬浮于 Tab 栏上方。
struct MiniPlayerBar: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        @Bindable var player = player

        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                artwork
                    .onTapGesture { player.showFullScreen = true }

                Button {
                    player.showFullScreen = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.currentTrack?.title ?? "未在播放")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let album = player.current?.album?.title, !album.isEmpty {
                            Text(album)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isLoading
                          ? "ellipsis"
                          : player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.bold())
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(player.isLoading)

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .onTapGesture { player.showFullScreen = true }
        }
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                ProgressView(value: player.duration > 0 ? player.elapsed / player.duration : 0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(width: proxy.size.width - 32)
                    .offset(y: 2)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        let cover = player.currentTrack?.cover ?? player.current?.img
        if let cover, let url = URL(string: cover) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())
            .overlay {
                // 待播放资源加载中：封面压暗 + 转圈。
                if player.isLoading {
                    Circle()
                        .fill(.black.opacity(0.45))
                        .overlay(ProgressView().tint(.white))
                }
            }
        } else {
            Image(systemName: "music.note")
                .font(.title3)
                .frame(width: 46, height: 46)
                .background(.quaternary, in: Circle())
                .overlay {
                    if player.isLoading {
                        Circle()
                            .fill(.black.opacity(0.45))
                            .overlay(ProgressView().tint(.white))
                    }
                }
        }
    }
}

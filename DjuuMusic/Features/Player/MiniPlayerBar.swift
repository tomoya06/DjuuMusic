import SwiftUI

/// 常驻迷你播放条：液态玻璃胶囊，悬浮于 Tab 栏上方。
struct MiniPlayerBar: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        @Bindable var player = player

        // tabViewBottomAccessory 自带液态玻璃壳，内容不能再叠 glassEffect：
        // 嵌套玻璃在真机上会让文字/图标出现重影（嵌套 glassEffect 叠影教训）。
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
                Group {
                    if player.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.body.bold())
                    }
                }
                .frame(width: 40, height: 40)
                .background(Color.accentColor, in: .circle)
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(player.isLoading)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .onTapGesture { player.showFullScreen = true }
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                ProgressView(value: player.duration > 0 ? player.elapsed / player.duration : 0)
                    .progressViewStyle(MiniBarProgressStyle())
                    .frame(width: proxy.size.width - 32)
                    .offset(y: 1)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        let theme = TrackTheme.classify(player.currentTrack?.title)
        ZStack {
            Circle()
                .fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            ThemePattern(symbol: theme.symbol, symbolSize: 16, opacity: 0.28)
                .clipShape(Circle())
        }
        // 与右侧两个 40pt 圆形播控按钮同尺寸，形成等大的圆点节奏。
        .frame(width: 40, height: 40)
        .overlay {
            // 待播放资源加载中：压暗 + 转圈。
            if player.isLoading {
                Circle()
                    .fill(.black.opacity(0.45))
                    .overlay(ProgressView().tint(.white))
            }
        }
    }
}

/// 自绘加粗进度条：系统 .linear 样式固定 4pt 高，无法调粗。
private struct MiniBarProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(max(configuration.fractionCompleted ?? 0, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: fraction * proxy.size.width)
            }
        }
        .frame(height: 6)
    }
}

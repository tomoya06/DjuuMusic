import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var player

    @State private var scrubValue: Double?
    @State private var showQueue = false

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingHeader(showQueue: $showQueue)
            artwork
            info
            progress
            controls
            Spacer(minLength: 0)
        }
        // 背景必须用 background 修饰符挂载：scaledToFill 的封面图会返回超出屏幕的
        // 布局尺寸，若作为 ZStack 子视图会把整个 ZStack 撑大（如 778pt 宽），
        // VStack 随之在放大后的坐标空间里居中，头部按钮被推出屏幕外。
        .background { background }
        .sheet(isPresented: $showQueue) {
            QueueSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Pieces

    private var background: some View {
        Group {
            if let cover = player.currentTrack?.cover ?? player.current?.img,
               let url = URL(string: cover) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill().ignoresSafeArea()
                } placeholder: {
                    Color.black.ignoresSafeArea()
                }
                .blur(radius: 60)
                .overlay(Color.black.opacity(0.55))
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }

    private var artwork: some View {
        let cover = player.currentTrack?.cover ?? player.current?.img
        return Group {
            if let cover, let url = URL(string: cover) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 28).fill(.quaternary)
                }
            } else {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "music.note").font(.largeTitle))
            }
        }
        .frame(maxWidth: 320)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .padding(.horizontal, 28)
        .padding(.top, 28)
    }

    private var info: some View {
        VStack(spacing: 4) {
            Text(player.currentTrack?.title ?? "未在播放")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let album = player.current?.album?.title, !album.isEmpty {
                Text(album)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
    }

    private var progress: some View {
        let binding = Binding<Double>(
            get: { scrubValue ?? player.elapsed },
            set: { scrubValue = $0 })
        return VStack(spacing: 4) {
            Slider(value: binding, in: 0...max(player.duration, 0.1)) { editing in
                if !editing {
                    player.seek(to: scrubValue ?? 0)
                    scrubValue = nil
                }
            }
            .tint(.accentColor)
            HStack {
                Text(timeString(scrubValue ?? player.elapsed))
                Spacer()
                Text(timeString(player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                Button {
                    player.cycleMode()
                } label: {
                    Image(systemName: player.mode.iconName)
                        .font(.body)
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                Button {
                    player.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title.bold())
                        .frame(width: 76, height: 76)
                }
                .buttonStyle(.glassProminent)
                .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                // 平衡布局的占位（与模式按钮对称）
                Label(player.mode.label, systemImage: player.mode.iconName)
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .frame(width: 48, height: 48)
                    .opacity(0.001)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, 24)
    }

    private func timeString(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// 播放页头部：不依赖 player 状态（进度刷新时本视图不重绘）。
private struct NowPlayingHeader: View {
    @Binding var showQueue: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            circleButton("chevron.down", bold: true) { dismiss() }
            Spacer()
            Text("正在播放")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            circleButton("list.bullet") { showQueue = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func circleButton(_ systemName: String, bold: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(bold ? .title3.bold() : .title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}

/// 播放队列面板。
struct QueueSheet: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                    Button {
                        player.play(track, in: player.queue)
                    } label: {
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .leading)
                            Text(track.title)
                                .font(.subheadline)
                                .lineLimit(1)
                                .foregroundStyle(index == player.currentIndex ? Color.accentColor : .primary)
                            Spacer()
                            if index == player.currentIndex {
                                Image(systemName: "waveform")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

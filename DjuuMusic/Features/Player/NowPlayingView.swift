import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var player

    @State private var scrubValue: Double?
    @State private var showQueue = false
    @State private var showCollect = false

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingHeader(showQueue: $showQueue)
            themePanel
            info
            progress
            // 音控行贴近拇指热区：下对齐 + 与进度条保持呼吸间距。
            Spacer(minLength: 16)
            controls
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
        .sheet(isPresented: $showCollect) {
            CollectPickerSheet()
        }
    }

    // MARK: - Pieces

    private var background: some View {
        let theme = TrackTheme.classify(player.currentTrack?.title)
        return ZStack {
            Color.black
            LinearGradient(colors: theme.colors, startPoint: .top, endPoint: .bottom)
                .opacity(0.5)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var themePanel: some View {
        let theme = TrackTheme.classify(player.currentTrack?.title)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            ThemePattern(symbol: theme.symbol)
                .clipShape(RoundedRectangle(cornerRadius: 28))
            // 分类标签（站点无作者头像数据，面板不再放任何图片）
            HStack(spacing: 6) {
                Image(systemName: theme.symbol).font(.footnote)
                Text(theme.label).font(.footnote.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.16), in: .capsule)
            .padding(16)
        }
        .frame(maxWidth: 320)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay {
            if player.isLoading {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.black.opacity(0.4))
                    .overlay(ProgressView().controlSize(.large).tint(.white))
            }
        }
        .shadow(color: theme.colors[0].opacity(0.45), radius: 24, y: 12)
        .padding(.horizontal, 28)
        .padding(.top, 24)
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
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                }
                // 不能再叠 buttonStyle(.glassProminent)：它自带胶囊底，与外层
                // glassEffect 的圆嵌套后常态呈扁椭圆（嵌套玻璃叠影同源问题）。
                .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                // 收藏：H5 无「已收藏」状态，仅作操作入口，选中收藏盒后由服务端判断。
                Button {
                    showCollect = true
                } label: {
                    Image(systemName: "star")
                        .font(.body)
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(player.currentTrack == nil)
                .opacity(player.currentTrack == nil ? 0.4 : 1)
            }
        }
        .padding(.bottom, 24)
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
        .padding(.top, 20)
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

// MARK: - 曲目分类主题

/// 从曲目标题关键词判别类别（站点标题自带风格标签，如「全国语 Electro 音乐…串烧」），
/// 每类提供主题色渐变 + 花纹符号，替代大封面的视觉主体。
enum TrackTheme {
    case medley      // 串烧
    case electro     // Electro
    case funkyHouse  // FunkyHouse
    case car         // 车载
    case ktv
    case slowRock    // 慢摇
    case dubstep
    case douyin      // 抖音热歌
    case generic

    static func classify(_ title: String?) -> TrackTheme {
        guard let title, !title.isEmpty else { return .generic }
        // 场景标签比风格标签更具体，优先匹配
        if title.contains("车载") { return .car }
        if title.contains("KTV") || title.contains("ktv") { return .ktv }
        if title.contains("Dubstep") || title.contains("dubstep") { return .dubstep }
        if title.contains("FunkyHouse") || title.contains("Funky") { return .funkyHouse }
        if title.contains("Electro") || title.contains("electro") { return .electro }
        if title.contains("慢摇") { return .slowRock }
        if title.contains("抖音") { return .douyin }
        if title.contains("串烧") { return .medley }
        return .generic
    }

    var label: String {
        switch self {
        case .medley: return "DJ 串烧"
        case .electro: return "Electro 舞曲"
        case .funkyHouse: return "FunkyHouse"
        case .car: return "车载专用"
        case .ktv: return "KTV 精选"
        case .slowRock: return "慢摇"
        case .dubstep: return "Dubstep"
        case .douyin: return "抖音热歌"
        case .generic: return "DJ 呦呦"
        }
    }

    var symbol: String {
        switch self {
        case .medley: return "music.note.list"
        case .electro: return "bolt.fill"
        case .funkyHouse: return "house.fill"
        case .car: return "car.fill"
        case .ktv: return "mic.fill"
        case .slowRock: return "waveform"
        case .dubstep: return "waveform.path"
        case .douyin: return "music.note"
        case .generic: return "music.note"
        }
    }

    var colors: [Color] {
        switch self {
        case .medley: return [Color(hex: 0xE34A85), Color(hex: 0x6E2B77)]
        case .electro: return [Color(hex: 0x2FA7E8), Color(hex: 0x2547B8)]
        case .funkyHouse: return [Color(hex: 0xF2A93B), Color(hex: 0xC25517)]
        case .car: return [Color(hex: 0xE4484F), Color(hex: 0x7C1D2B)]
        case .ktv: return [Color(hex: 0x9B64F2), Color(hex: 0x4B2492)]
        case .slowRock: return [Color(hex: 0x27B8A4), Color(hex: 0x0E6E63)]
        case .dubstep: return [Color(hex: 0x93C83D), Color(hex: 0x3E641C)]
        case .douyin: return [Color(hex: 0x25C4D8), Color(hex: 0xC22B4B)]
        case .generic: return [Color(hex: 0x5C6B84), Color(hex: 0x232B3A)]
        }
    }
}

struct ThemePattern: View {
    var symbol: String
    var symbolSize: CGFloat = 32
    var opacity: Double = 0.09

    var body: some View {
        let spacing = symbolSize * 2.06
        Canvas { context, size in
            var y: CGFloat = -spacing
            var row = 0
            while y < size.height + spacing {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : -spacing / 2
                while x < size.width + spacing {
                    context.draw(
                        Text(Image(systemName: symbol))
                            .font(.system(size: symbolSize, weight: .semibold))
                            .foregroundColor(.white.opacity(opacity)),
                        at: CGPoint(x: x, y: y))
                    x += spacing
                }
                y += spacing * 0.78
                row += 1
            }
        }
        .rotationEffect(.degrees(-10))
        .scaleEffect(1.3)
        .allowsHitTesting(false)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

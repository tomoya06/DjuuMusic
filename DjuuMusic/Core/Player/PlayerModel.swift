import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// 与站点一致的播放模式：1 列表循环 / 2 随机 / 3 单曲循环。
enum PlayMode: Int, Codable, CaseIterable {
    case loopAll = 1
    case shuffle = 2
    case repeatOne = 3

    var next: PlayMode {
        PlayMode(rawValue: rawValue % 3 + 1) ?? .loopAll
    }

    var label: String {
        switch self {
        case .loopAll: return "列表循环"
        case .shuffle: return "随机播放"
        case .repeatOne: return "单曲循环"
        }
    }

    var iconName: String {
        switch self {
        case .loopAll: return "repeat"
        case .shuffle: return "shuffle"
        case .repeatOne: return "repeat.1"
        }
    }
}

@MainActor
@Observable
final class PlayerModel {

    static let shared = PlayerModel()

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private let artworkCache = NSCache<NSString, UIImage>()
    private var lastPublishedDuration: Double = 0
    private var lastPublishedRate: Double = 0

    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var current: MusicDetail?
    private(set) var mode: PlayMode = .loopAll
    private(set) var isPlaying = false
    private(set) var duration: Double = 0
    private(set) var elapsed: Double = 0
    private(set) var isLoading = false
    private(set) var failureMessage: String?
    var showFullScreen = false

    var currentTrack: Track? {
        guard let index = currentIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    var hasCurrent: Bool { currentTrack != nil }

    private init() {
        mode = LocalStore.mode
        queue = LocalStore.lastQueue
        if let last = LocalStore.lastTrackID, let idx = queue.firstIndex(where: { $0.id == last }) {
            currentIndex = idx
        }
        configureAudioSession()
        installObservers()
        setupRemoteCommands()
    }

    // MARK: - Public control

    func play(_ track: Track, in list: [Track]) {
        queue = list
        currentIndex = list.firstIndex(where: { $0.id == track.id }) ?? 0
        LocalStore.lastQueue = list
        resolveAndPlay(track)
    }

    /// 将曲目追加到当前队列之后（“下一首播放”）。
    func playNext(_ track: Track) {
        guard !queue.contains(where: { $0.id == track.id }) else { return }
        if let index = currentIndex {
            queue.insert(track, at: index + 1)
        } else {
            queue.append(track)
            play(track, in: queue)
        }
    }

    func toggle() {
        if isPlaying {
            pause()
        } else if current == nil, let track = currentTrack {
            // 冷启动恢复的历史曲目尚未加载，点击播放时再解析。
            resolveAndPlay(track)
        } else {
            resume()
        }
    }

    func pause() {
        player.pause()
        syncPlaybackState()
        updateNowPlaying()
    }

    func resume() {
        guard current != nil else { return }
        player.play()
        syncPlaybackState()
        updateNowPlaying()
    }

    func seek(to second: Double) {
        let time = CMTime(seconds: max(0, min(second, duration)), preferredTimescale: 600)
        // seek 必须打在 currentItem 上：打在 AVPlayer 上时，replaceCurrentItem
        // 会把未完成的 seek 转移给新 item，导致下一首从上一首的进度开播。
        player.currentItem?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        elapsed = time.seconds
        updateNowPlaying()
    }

    /// userDriven = 用户手动切歌；false = 自动连播。
    func next(userDriven: Bool = true) {
        guard !queue.isEmpty else { return }
        switch mode {
        case .repeatOne where !userDriven:
            replay()
            return
        case .shuffle:
            let nextIndex = randomIndex(excluding: currentIndex)
            jumpTo(nextIndex)
        default:
            let nextIndex = ((currentIndex ?? -1) + 1) % queue.count
            jumpTo(nextIndex)
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if elapsed > 5 {
            seek(to: 0)
            return
        }
        let prevIndex = ((currentIndex ?? 0) - 1 + queue.count) % queue.count
        jumpTo(prevIndex)
    }

    func cycleMode() {
        mode = mode.next
        LocalStore.mode = mode
    }

    func clearFailure() {
        failureMessage = nil
    }

    // MARK: - Queue resolution

    private func jumpTo(_ index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        resolveAndPlay(queue[index])
    }

    private func resolveAndPlay(_ track: Track) {
        isLoading = true
        isPlaying = false
        elapsed = 0
        duration = 0
        Task {
            do {
                let detail = try await DjuuAPI.musicDetail(id: track.id)
                guard current?.id != detail.id || current?.url != detail.url || !hasCurrentItem else {
                    isLoading = false
                    resume()
                    return
                }
                current = detail
                if let cover = detail.img {
                    queue = queue.map { item in
                        item.id == track.id && item.cover == nil
                            ? Track(id: item.id, title: item.title, cover: cover, hit: item.hit, date: item.date)
                            : item
                    }
                    LocalStore.lastQueue = queue
                }
                let item = AVPlayerItem(url: URL(string: detail.url)!)
                player.replaceCurrentItem(with: item)
                player.play()
                isLoading = false
                LocalStore.lastTrackID = track.id
                LocalStore.appendHistory(track)
                await updateNowPlaying()
            } catch {
                isLoading = false
                failureMessage = error.localizedDescription
            }
        }
    }

    private var hasCurrentItem: Bool { player.currentItem != nil }

    private func replay() {
        seek(to: 0)
        player.play()
        syncPlaybackState()
    }

    private func randomIndex(excluding current: Int?) -> Int {
        guard queue.count > 1, let current else { return 0 }
        var candidate = Int.random(in: 0..<queue.count)
        while candidate == current {
            candidate = Int.random(in: 0..<queue.count)
        }
        return candidate
    }

    // MARK: - Audio session & notifications

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            failureMessage = "音频会话配置失败：\(error.localizedDescription)"
        }
    }

    private func installObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isLoading else { return }
                // isLoading 期间旧 item 还挂在 player 上，此处读到的 elapsed/duration
                // 是旧曲目的，写回会覆盖 resolveAndPlay 刚清零的进度。
                self.elapsed = time.seconds.isFinite ? time.seconds : 0
                if let item = self.player.currentItem, item.duration.seconds.isFinite, item.duration.seconds > 0 {
                    self.duration = item.duration.seconds
                }
                self.syncPlaybackState()
                self.refreshNowPlayingIfChanged()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.next(userDriven: false)
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let info = notification.userInfo,
                      let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
                switch type {
                case .began:
                    self?.pause()
                case .ended:
                    if let optionRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                       AVAudioSession.InterruptionOptions(rawValue: optionRaw).contains(.shouldResume) {
                        self?.resume()
                    }
                default:
                    break
                }
            }
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let info = notification.userInfo,
                      let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw),
                      reason == .oldDeviceUnavailable else { return }
                self?.pause()
            }
        }
    }

    private func syncPlaybackState() {
        isPlaying = player.rate > 0
    }

    // MARK: - Remote commands & Now Playing

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: positionEvent.positionTime) }
            return .success
        }
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [:]
        if let track = currentTrack {
            info[MPMediaItemPropertyTitle] = track.title
            info[MPMediaItemPropertyArtist] = current?.album?.title ?? "DJ呦呦"
        }
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        // 用 player.rate 实时值：resume() 后 isPlaying 可能还没被观察器置回，
        // 若仍发布 0，系统面板的进度会停在原地。
        let rate: Double = player.rate > 0 ? Double(player.rate) : 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        // 锁屏/控制中心/灵动岛共用此 artwork：主题渐变+花纹，与 app 内去封面改版一致。
        if let artwork = themedArtwork(for: TrackTheme.classify(currentTrack?.title)) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        lastPublishedDuration = duration
        lastPublishedRate = rate
    }

    /// 系统面板进度由 elapsed+rate 外推：只在总时长首次加载、或播放状态翻转时
    /// 重发布，避免每 0.5s 重置 nowPlayingInfo 造成进度抖动。
    private func refreshNowPlayingIfChanged() {
        let rate: Double = player.rate > 0 ? Double(player.rate) : 0
        if (duration > 0 && duration != lastPublishedDuration) || rate != lastPublishedRate {
            updateNowPlaying()
        }
    }

    /// 渲染主题徽章图（与 minibar 同款视觉），按主题缓存，避免 elapsed 刷新时重复渲染。
    private func themedArtwork(for theme: TrackTheme) -> UIImage? {
        let key = "theme-\(theme.label)" as NSString
        if let cached = artworkCache.object(forKey: key) { return cached }
        let view = ZStack {
            LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            ThemePattern(symbol: theme.symbol, symbolSize: 64, opacity: 0.14)
        }
        .frame(width: 600, height: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.uiImage else { return nil }
        artworkCache.setObject(image, forKey: key)
        return image
    }
}

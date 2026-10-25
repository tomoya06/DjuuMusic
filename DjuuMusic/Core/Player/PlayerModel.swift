import AVFoundation
import MediaPlayer
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
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
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
                guard let self else { return }
                self.elapsed = time.seconds.isFinite ? time.seconds : 0
                if let item = self.player.currentItem, item.duration.seconds.isFinite, item.duration.seconds > 0 {
                    self.duration = item.duration.seconds
                }
                self.syncPlaybackState()
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
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? player.rate : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let coverURL = currentTrack?.cover ?? current?.img else { return }
        loadArtwork(urlString: coverURL) { image in
            guard let image else { return }
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
    }

    func cachedArtwork(for urlString: String?) -> UIImage? {
        guard let urlString else { return nil }
        return artworkCache.object(forKey: urlString as NSString)
    }

    func loadArtwork(urlString: String, completion: @escaping (UIImage?) -> Void) {
        if let cached = artworkCache.object(forKey: urlString as NSString) {
            completion(cached)
            return
        }
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        Task {
            do {
                let data = try await DjuuClient.shared.download(url)
                guard let image = UIImage(data: data) else {
                    completion(nil)
                    return
                }
                self.artworkCache.setObject(image, forKey: urlString as NSString)
                completion(image)
            } catch {
                completion(nil)
            }
        }
    }
}

import Foundation

/// 播放模式 / 播放历史 / 最近队列 / 登录资料的本地持久化（UserDefaults）。
enum LocalStore {

    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let mode = "djuu.playmode"
        static let history = "djuu.history"
        static let lastQueue = "djuu.lastqueue"
        static let lastTrackID = "djuu.lasttrack"
        static let profile = "djuu.profile"
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: - Play mode

    static var mode: PlayMode {
        get { PlayMode(rawValue: defaults.integer(forKey: Keys.mode)) ?? .loopAll }
        set { defaults.set(newValue.rawValue, forKey: Keys.mode) }
    }

    // MARK: - History（我的-播放历史）

    static var history: [Track] {
        load([Track].self, forKey: Keys.history) ?? []
    }

    static func appendHistory(_ track: Track) {
        var list = history.filter { $0.id != track.id }
        list.insert(track, at: 0)
        if list.count > 100 { list = Array(list.prefix(100)) }
        save(list, forKey: Keys.history)
    }

    static func removeHistory(id: Int) {
        save(history.filter { $0.id != id }, forKey: Keys.history)
    }

    static func clearHistory() {
        defaults.removeObject(forKey: Keys.history)
    }

    // MARK: - Last queue（冷启动恢复队列，不自动播放）

    static var lastQueue: [Track] {
        get { load([Track].self, forKey: Keys.lastQueue) ?? [] }
        set { save(newValue, forKey: Keys.lastQueue) }
    }

    static var lastTrackID: Int? {
        get {
            guard defaults.object(forKey: Keys.lastTrackID) != nil else { return nil }
            return defaults.integer(forKey: Keys.lastTrackID)
        }
        set {
            if let newValue { defaults.set(newValue, forKey: Keys.lastTrackID) }
            else { defaults.removeObject(forKey: Keys.lastTrackID) }
        }
    }

    // MARK: - Profile（登录态）

    static var profile: UserProfile? {
        get { load(UserProfile.self, forKey: Keys.profile) }
        set {
            if let newValue { save(newValue, forKey: Keys.profile) }
            else { defaults.removeObject(forKey: Keys.profile) }
        }
    }

    static var isLoggedIn: Bool { profile != nil }

    static func logout() {
        profile = nil
        if let cookies = HTTPCookieStorage.shared.cookies(for: DjuuClient.baseURL) {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    // MARK: - Helpers

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}

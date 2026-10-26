import Foundation

struct Track: Codable, Identifiable, Hashable {
    let id: Int
    var title: String
    var cover: String?
    var hit: String?
    var date: String?

    init(id: Int, title: String, cover: String? = nil, hit: String? = nil, date: String? = nil) {
        self.id = id
        self.title = title
        self.cover = cover
        self.hit = hit
        self.date = date
    }
}

struct MusicDetail: Decodable {
    let id: Int
    let title: String
    let url: String
    let img: String?
    let time: String?
    let hitsNum: Int?
    let musicSize: Double?
    let album: Album?

    struct Album: Decodable {
        let id: Int
        let title: String
        let coverImg: String?
        let clickCount: Int?

        enum CodingKeys: String, CodingKey {
            case id, title
            case coverImg = "cover_img"
            case clickCount = "click_count"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, url, img, time, album
        case hitsNum = "hits_num"
        case musicSize = "musicsize"
    }
}

struct UserProfile: Codable, Equatable {
    var uid: String
    var username: String
    var avatar: String?
    var isVIP: Bool
    // H5 用它写 30 天 token cookie 鉴权 /user API（PHPSESSID 不够）
    var token: String?

    enum CodingKeys: String, CodingKey {
        case uid, username, avatar, token
        case isVIP = "is_vip"
    }

    init(uid: String, username: String, avatar: String?, isVIP: Bool, token: String? = nil) {
        self.uid = uid
        self.username = username
        self.avatar = avatar
        self.isVIP = isVIP
        self.token = token
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .uid) {
            uid = String(i)
        } else {
            uid = (try? c.decode(String.self, forKey: .uid)) ?? ""
        }
        username = (try? c.decode(String.self, forKey: .username)) ?? ""
        avatar = try? c.decode(String.self, forKey: .avatar)
        if let i = try? c.decode(Int.self, forKey: .isVIP) {
            isVIP = i != 0
        } else if let s = try? c.decode(String.self, forKey: .isVIP) {
            isVIP = Int(s) != 0
        } else {
            isVIP = false
        }
        token = try? c.decode(String.self, forKey: .token)
    }
}

struct TrackPage {
    var tracks: [Track]
    var hasMore: Bool
}

/// 收藏盒（H5「音乐盒」，/user/collect 接口返回）。
struct CollectBox: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
}

struct HomeSection: Identifiable, Hashable {
    let id: Int
    let title: String
    let tracks: [Track]
}

struct HomeContent {
    var recommended: [HomeSection]
    var updates: [HomeSection]
}

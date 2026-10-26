import Foundation

enum DjuuAPI {

    // MARK: - JSON envelope

    private struct Envelope<T: Decodable>: Decodable {
        let code: Int
        let msg: String?
        let data: T?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let i = try? c.decode(Int.self, forKey: .code) {
                code = i
            } else if let s = try? c.decode(String.self, forKey: .code), let i = Int(s) {
                code = i
            } else {
                code = -1
            }
            msg = try? c.decodeIfPresent(String.self, forKey: .msg)
            data = try? c.decodeIfPresent(T.self, forKey: .data)
        }

        enum CodingKeys: String, CodingKey { case code, msg, data }
    }

    // MARK: - Playback

    /// POST /play/music  {id} → 曲目详情（含 m4a 直链）。
    static func musicDetail(id: Int) async throws -> MusicDetail {
        struct Payload: Decodable { let data: MusicDetail? }
        let payload: Payload = try await DjuuClient.shared.postForm(path: "play/music", fields: ["id": String(id)])
        guard let detail = payload.data else {
            throw DjuuError.badResponse("曲目加载失败")
        }
        return detail
    }

    /// POST /ajax/music  {musicid:"1,2,3"} → 队列曲目 [{id,title}]。
    static func trackStubs(ids: [Int]) async throws -> [Track] {
        struct Stub: Decodable { let id: Int; let title: String }
        let joined = ids.map(String.init).joined(separator: ",")
        let stubs: [Stub] = try await DjuuClient.shared.postForm(path: "ajax/music", fields: ["musicid": joined])
        return stubs.map { Track(id: $0.id, title: $0.title) }
    }

    // MARK: - Browsing

    static func home() async throws -> HomeContent {
        let html = try await DjuuClient.shared.getHTML(path: "")
        return DjuuHTMLParser.parseHome(html)
    }

    /// GET /djlist/{cid}_{monthid}_{byid}_{page}.html
    /// byid: 1最新上传 2精品推荐 3本周热播 4上周热播 5本月热播 6上月热播 7年度热播 8年度下载
    static func djlist(cid: Int, month: Int, sort: Int, page: Int) async throws -> TrackPage {
        let path = "djlist/\(cid)_\(month)_\(sort)_\(page).html"
        let html = try await DjuuClient.shared.getHTML(path: path, query: ["ajax": "1"])
        let body = fragment(of: html)
        return TrackPage(tracks: DjuuHTMLParser.parseTrackItems(body), hasMore: DjuuHTMLParser.parseHasMore(body))
    }

    /// GET /search?musicname=&cid=&list=&page=   list: 1最新 2最热
    static func search(keyword: String, cid: Int, sort: Int, page: Int) async throws -> TrackPage {
        var query: [String: String] = [
            "musicname": keyword,
            "list": String(sort),
            "ajax": "1",
        ]
        if cid > 0 { query["cid"] = String(cid) }
        if page > 1 { query["page"] = String(page) }
        let html = try await DjuuClient.shared.getHTML(path: "search", query: query)
        let body = fragment(of: html)
        return TrackPage(tracks: DjuuHTMLParser.parseTrackItems(body), hasMore: DjuuHTMLParser.parseHasMore(body))
    }

    /// 服务端返回整页 HTML，列表位于 <!--musiclist--> 注释之后。
    private static func fragment(of html: String) -> String {
        guard let range = html.range(of: "<!--musiclist-->") else { return html }
        return String(html[range.upperBound...])
    }

    // MARK: - Login（手机号 + 短信，滑块验证码）

    /// GET /code/code?t=随机数 → 240×450 三段拼图（0:带孔背景 1:拼图块 2:完整背景）。
    static func sliderCaptchaImage() async throws -> Data {
        let url = URL(string: "code/code?t=\(Int.random(in: 0...1_000_000))", relativeTo: DjuuClient.baseURL)!
        return try await DjuuClient.shared.download(url)
    }

    /// POST /code/check?tn_r={滑块偏移} → {code:"0", data:{token}}
    static func sliderCheck(offset: Int) async throws -> String {
        struct TokenPayload: Decodable { let token: String }
        let url = URL(string: "code/check?tn_r=\(offset)", relativeTo: DjuuClient.baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, response) = try await DjuuClient.shared.session.data(for: request)
        try DjuuClient.checkHTTP(response)
        let envelope = try JSONDecoder().decode(Envelope<TokenPayload>.self, from: data)
        guard envelope.code == 0, let token = envelope.data?.token else {
            throw DjuuError.server(code: envelope.code, message: envelope.msg ?? "验证失败")
        }
        return token
    }

    /// POST /code/sendSms  {mobile, scene:'login', token}
    static func sendSms(mobile: String, token: String) async throws -> String {
        struct MsgPayload: Decodable { let msg: String? }
        let payload: MsgPayload = try await DjuuClient.shared.postForm(
            path: "code/sendSms",
            fields: ["mobile": mobile, "scene": "login", "token": token])
        return payload.msg ?? "验证码已发送"
    }

    /// POST /user/login  {username:手机号, smscode} → 会话由 Set-Cookie 维持。
    static func login(mobile: String, smsCode: String) async throws -> UserProfile {
        let payload: Envelope<UserProfile> = try await DjuuClient.shared.postForm(
            path: "user/login",
            fields: ["username": mobile, "smscode": smsCode])
        guard payload.code == 0, let profile = payload.data, !profile.uid.isEmpty else {
            throw DjuuError.server(code: payload.code, message: payload.msg ?? "登录失败")
        }
        return profile
    }

    // MARK: - Collect（收藏盒，对应 H5 /user/collect?action=...）

    /// H5 约定：会话失效返回 code=109。
    static let notLoggedInCode = 109

    private struct EmptyData: Decodable {}

    /// 收藏盒列表（showcollect → data:[{id,title}]）。
    static func collectBoxes() async throws -> [CollectBox] {
        let payload: Envelope<[CollectBox]> = try await DjuuClient.shared.postForm(
            path: "user/collect", query: ["action": "showcollect"], fields: [:])
        guard payload.code == 0 else {
            throw DjuuError.server(code: payload.code, message: payload.msg ?? "收藏加载失败")
        }
        return payload.data ?? []
    }

    /// 收藏盒内曲目（getlist → 与列表页同模板的 HTML 片段，一次返回全部）。
    static func collectTracks(boxID: Int) async throws -> [Track] {
        let html = try await DjuuClient.shared.getHTML(
            path: "user/collect",
            query: ["action": "getlist", "id": String(boxID), "ajax": "1"])
        guard html.contains("<!--musiclist-->") else {
            // 会话失效时被重定向到登录页，页面里没有列表片段。
            throw DjuuError.server(code: notLoggedInCode, message: "请登录DJ呦呦")
        }
        return DjuuHTMLParser.parseTrackItems(fragment(of: html))
    }

    /// 新建收藏盒（addcollect {boxname}）。
    static func createCollectBox(name: String) async throws -> String {
        let payload: Envelope<EmptyData> = try await DjuuClient.shared.postForm(
            path: "user/collect", query: ["action": "addcollect"], fields: ["boxname": name])
        guard payload.code == 0 else {
            throw DjuuError.server(code: payload.code, message: payload.msg ?? "创建失败")
        }
        return payload.msg ?? "创建成功"
    }

    /// 添加曲目到收藏盒（addmusic {boxid, musicid}）。
    /// H5 前端没有「已收藏」状态，是否重复收藏由服务端在此步返回错误信息。
    static func addToCollect(boxID: Int, musicID: Int) async throws -> String {
        let payload: Envelope<EmptyData> = try await DjuuClient.shared.postForm(
            path: "user/collect", query: ["action": "addmusic"],
            fields: ["boxid": String(boxID), "musicid": String(musicID)])
        guard payload.code == 0 else {
            throw DjuuError.server(code: payload.code, message: payload.msg ?? "收藏失败")
        }
        return payload.msg ?? "收藏成功"
    }
}

import Foundation

enum DjuuHTMLParser {

    // MARK: - Track list fragments

    /// 解析 djuu-list-item 列表片段（首页/曲库/搜索/榜单共用同一模板）。
    static func parseTrackItems(_ html: String) -> [Track] {
        guard html.contains("djuu-list-item") else { return [] }
        let chunks = html.components(separatedBy: "djuu-list-item")
        var tracks: [Track] = []
        var seen = Set<Int>()
        for chunk in chunks.dropFirst() {
            guard let id = Self.firstMatch("(?<=data-bs-id=\")\\d+", chunk).flatMap(Int.init) else { continue }
            guard !seen.contains(id) else { continue }
            guard let title = Self.firstMatch("(?<=<span>)[^<]+", chunk) else { continue }
            seen.insert(id)
            let hit = Self.firstMatch("(?<=HIT:)[0-9.]+℃?", chunk)
            let date = Self.firstMatch("(?<=TIME:)[0-9/]+", chunk)
            tracks.append(Track(id: id, title: Self.decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines),
                                hit: hit, date: date))
        }
        return tracks
    }

    static func parseHasMore(_ html: String) -> Bool {
        !html.contains("没有更多") && !parseTrackItems(html).isEmpty
    }

    // MARK: - Home page

    /// 首页有两个轮播：#slider_new（最新推荐 2 个 Tab）与 #slider_rank（最新更新 6 个 Tab）。
    /// 注意：芯片标签在各自轮播容器之前，必须全局按 data-bs-target 收集，不能在轮播切片内找。
    static func parseHome(_ html: String) -> HomeContent {
        var labelMap: [String: [(Int, String)]] = [:]
        for groups in capturedGroups(
            pattern: "data-bs-target=\"#([A-Za-z_]+)\"[^>]*?data-bs-slide-to=\"(\\d+)\"[^>]*?>([^<]+)",
            in: html) {
            guard groups.count == 3, let idx = Int(groups[1]) else { continue }
            labelMap[groups[0], default: []].append((idx, decodeEntities(groups[2])))
        }

        let newIndex = html.range(of: "id=\"slider_new\"")?.lowerBound
        let rankIndex = html.range(of: "id=\"slider_rank\"")?.lowerBound

        var recommended: [HomeSection] = []
        var updates: [HomeSection] = []

        if let newIdx = newIndex {
            let end = rankIndex ?? (html.index(newIdx, offsetBy: 60000, limitedBy: html.endIndex) ?? html.endIndex)
            recommended = parseCarousel(String(html[newIdx..<end]), labels: labelMap["slider_new"] ?? [])
        }
        if let rankIdx = rankIndex {
            let upper = html.index(rankIdx, offsetBy: 140000, limitedBy: html.endIndex) ?? html.endIndex
            updates = parseCarousel(String(html[rankIdx..<upper]), labels: labelMap["slider_rank"] ?? [])
        }
        return HomeContent(recommended: recommended, updates: updates)
    }

    private static func parseCarousel(_ segment: String, labels: [(Int, String)]) -> [HomeSection] {
        let sortedLabels = labels.sorted { $0.0 < $1.0 }
        let chunks = segment.components(separatedBy: "carousel-item").dropFirst()
        guard !sortedLabels.isEmpty, !chunks.isEmpty else { return [] }
        var sections: [HomeSection] = []
        for (offset, chunk) in chunks.enumerated() {
            guard offset < sortedLabels.count else { break }
            let tracks = parseTrackItems(chunk)
            guard !tracks.isEmpty else { continue }
            sections.append(HomeSection(id: sortedLabels[offset].0, title: sortedLabels[offset].1, tracks: tracks))
        }
        return sections.sorted { $0.id < $1.id }
    }

    // MARK: - Helpers

    static func decodeEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&#40;", "("), ("&#41;", ")"),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    private static func firstMatch(_ pattern: String, _ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.range.location != NSNotFound,
              let r = Range(match.range, in: text) else { return nil }
        return String(text[r])
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func capturedGroups(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { idx in
                match.range(at: idx).location == NSNotFound ? nil : Range(match.range(at: idx), in: text).map { String(text[$0]) }
            }
        }
    }
}

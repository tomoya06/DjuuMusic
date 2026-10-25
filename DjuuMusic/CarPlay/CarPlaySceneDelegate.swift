import CarPlay
import UIKit

/// CarPlay 入口：Tab = 最新推荐 / 曲库分类 / 搜索 / 正在播放。
/// 播放控制复用 PlayerModel 的 MPRemoteCommandCenter 与 MPNowPlayingInfoCenter，
/// CPNowPlayingTemplate 会自动反映锁屏媒体信息。
final class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    // CPSearchTemplate 对 delegate 是弱引用，需持有避免释放。
    private var searchHandler: CarPlaySearchHandler?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        Task { @MainActor in
            await self.installRootTemplate(in: interfaceController)
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController) {
        if self.interfaceController === interfaceController {
            self.interfaceController = nil
            searchHandler = nil
        }
    }

    // MARK: - Root

    @MainActor
    private func installRootTemplate(in controller: CPInterfaceController) async {
        let home = await homeListTemplate()
        let library = libraryTemplate()
        let search = searchTemplate()

        let templates: [CPTemplate] = [home, library, search, CPNowPlayingTemplate.shared]
        let tabBar = CPTabBarTemplate(templates: templates)
        controller.setRootTemplate(tabBar, animated: false, completion: nil)
    }

    @MainActor
    private func homeListTemplate() async -> CPTemplate {
        do {
            let content = try await DjuuAPI.home()
            var items: [CPListItem] = []
            for section in (content.recommended + content.updates).prefix(6) {
                for track in section.tracks.prefix(20) {
                    items.append(Self.trackItem(track, queue: section.tracks))
                }
            }
            return CPListTemplate(title: "最新推荐", sections: [CPListSection(items: items)])
        } catch {
            return CPListTemplate(title: "最新推荐",
                                  sections: [CPListSection(items: [Self.errorItem(message: error.localizedDescription)])])
        }
    }

    @MainActor
    private func libraryTemplate() -> CPTemplate {
        var items: [CPListItem] = DjuuCatalog.categories.map { category in
            let item = CPListItem(text: category.name,
                                  detailText: "\(category.children.count) 个子分类")
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                guard let self else { return }
                Task { @MainActor in
                    await self.pushCategory(category)
                    completion()
                }
            }
            return item
        }
        if items.isEmpty {
            items = [Self.errorItem(message: "分类为空")]
        }
        return CPListTemplate(title: "曲库", sections: [CPListSection(items: items)])
    }

    @MainActor
    private func pushCategory(_ category: DjuuCategory) async {
        guard let controller = interfaceController else { return }
        let list = await trackListTemplate(title: category.name,
                                           cid: category.id,
                                           month: 0,
                                           sort: 1,
                                           accumulated: [])
        controller.pushTemplate(list, animated: true, completion: nil)
    }

    @MainActor
    private func trackListTemplate(title: String, cid: Int, month: Int, sort: Int,
                                   accumulated: [Track]) async -> CPTemplate {
        var tracks = accumulated
        do {
            let page = try await DjuuAPI.djlist(cid: cid, month: month, sort: sort, page: accumulated.count / 60 + 1)
            let known = Set(tracks.map(\.id))
            tracks += page.tracks.filter { !known.contains($0.id) }
        } catch {
            if accumulated.isEmpty {
                return CPListTemplate(title: title,
                                      sections: [CPListSection(items: [Self.errorItem(message: error.localizedDescription)])])
            }
        }

        var items: [CPListItem] = tracks.map { Self.trackItem($0, queue: tracks) }
        if tracks.count >= 60 {
            let more = CPListItem(text: "加载更多", detailText: "已加载 \(tracks.count) 首")
            more.handler = { [weak self] _, completion in
                guard let self else { return }
                Task { @MainActor in
                    guard let controller = self.interfaceController else { return }
                    let next = await self.trackListTemplate(title: title,
                                                            cid: cid,
                                                            month: month,
                                                            sort: sort,
                                                            accumulated: tracks)
                    controller.popTemplate(animated: false, completion: { _, _ in
                        controller.pushTemplate(next, animated: false, completion: nil)
                    })
                    completion()
                }
            }
            items.append(more)
        }

        return CPListTemplate(title: title, sections: [CPListSection(items: items)])
    }

    @MainActor
    private func searchTemplate() -> CPTemplate {
        let search = CPSearchTemplate()
        let handler = CarPlaySearchHandler()
        searchHandler = handler
        search.delegate = handler
        return search
    }

    // MARK: - Items

    @MainActor
    static func trackItem(_ track: Track, queue: [Track]) -> CPListItem {
        let item = CPListItem(text: track.title, detailText: track.hit.map { "HIT \($0)" })
        item.handler = { _, completion in
            Task { @MainActor in
                PlayerModel.shared.play(track, in: queue)
                completion()
            }
        }
        return item
    }

    @MainActor
    static func errorItem(message: String) -> CPListItem {
        let item = CPListItem(text: "加载失败", detailText: message)
        item.handler = { _, completion in completion() }
        return item
    }
}

// MARK: - Search

final class CarPlaySearchHandler: NSObject, CPSearchTemplateDelegate {

    private var searchTask: Task<Void, Never>?

    func searchTemplate(_ searchTemplate: CPSearchTemplate,
                        updatedSearchText searchText: String,
                        completionHandler: @escaping ([CPListItem]) -> Void) {
        searchTask?.cancel()
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard keyword.count >= 2 else {
            completionHandler([CarPlaySceneDelegate.errorItem(message: "请输入至少 2 个字")])
            return
        }
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            do {
                let result = try await DjuuAPI.search(keyword: keyword, cid: 0, sort: 2, page: 1)
                guard !Task.isCancelled else { return }
                let items: [CPListItem] = result.tracks.map { track in
                    let item = CPListItem(text: track.title, detailText: track.hit.map { "HIT \($0)" })
                    item.handler = { _, completion in
                        Task { @MainActor in
                            PlayerModel.shared.play(track, in: result.tracks)
                            completion()
                        }
                    }
                    return item
                }
                completionHandler(items.isEmpty
                                   ? [CarPlaySceneDelegate.errorItem(message: "没有找到相关内容")]
                                   : items)
            } catch {
                completionHandler([CarPlaySceneDelegate.errorItem(message: "搜索失败，请重试")])
            }
        }
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate,
                        selectedResult item: CPListItem,
                        completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {
        // 键盘上的搜索键，无需处理。
    }
}

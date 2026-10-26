import SwiftUI
import UIKit

struct LibraryView: View {
    @Environment(PlayerModel.self) private var player

    @State private var topCategory = DjuuCatalog.categories.first!
    @State private var subCategory: DjuuCategory?
    @State private var sort: Int = 1
    @State private var year: Int = 0

    @State private var tracks: [Track] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var listPosition = ScrollPosition()

    private let sorts: [(Int, String)] = [
        (1, "最新上传"), (2, "精品推荐"), (3, "本周热播"), (4, "上周热播"),
        (5, "本月热播"), (6, "上月热播"), (7, "年度热播"), (8, "年度下载"),
    ]

    private var years: [(Int, String)] {
        var list = [(0, "全部年份")]
        let current = Calendar.current.component(.year, from: Date())
        for y in (2017...current).reversed() { list.append((y, "\(y)年")) }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                listContent
            }
            .background(Color(.systemBackground))
            .navigationTitle("曲库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SearchView()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .task { await loadFirstIfNeeded() }
        }
    }

    // MARK: - Filters

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            chipRow(title: nil, items: DjuuCatalog.categories.map { (String($0.id), $0.name) },
                    selectedID: String(topCategory.id)) { id in
                guard let category = DjuuCatalog.categories.first(where: { String($0.id) == id }) else { return }
                topCategory = category
                subCategory = nil
                Task { await reload() }
            }

            if !topCategory.children.isEmpty {
                chipRow(title: nil,
                        items: topCategory.children.map { (String($0.id), $0.name) },
                        selectedID: subCategory.map { String($0.id) }) { id in
                    subCategory = topCategory.children.first { String($0.id) == id }
                    Task { await reload() }
                }
            }

            chipRow(title: nil, items: sorts.map { (String($0.0), $0.1) },
                    selectedID: String(sort)) { id in
                sort = Int(id) ?? 1
                Task { await reload() }
            }

            chipRow(title: nil, items: years.map { (String($0.0), $0.1) },
                    selectedID: String(year)) { id in
                year = Int(id) ?? 0
                Task { await reload() }
            }
        }
        .padding(.vertical, 8)
    }

    private func chipRow(title: String?,
                         items: [(String, String)],
                         selectedID: String?,
                         onTap: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.0) { id, name in
                        let selected = id == selectedID
                        Button {
                            onTap(id)
                        } label: {
                            Text(name)
                                .font(.footnote.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.white : .primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                        }
                        .glassEffect(selected
                                     ? .regular.tint(.accentColor).interactive()
                                     : .regular.interactive(),
                                     in: .capsule)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        if let loadError, tracks.isEmpty {
            errorView(loadError)
        } else if tracks.isEmpty && isLoading {
            ProgressView("加载中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(index: index + 1,
                                 track: track,
                                 isCurrent: player.currentTrack?.id == track.id,
                                 onPlay: { player.play(track, in: tracks) },
                                 onPlayNext: { player.playNext(track) })
                            .onAppear {
                                if track.id == tracks.last?.id && hasMore && !isLoading {
                                    Task { await loadMore() }
                                }
                            }
                    }
                    if isLoading && !tracks.isEmpty {
                        ProgressView().padding(.vertical, 12)
                    }
                    if !hasMore && !tracks.isEmpty {
                        Text("没有更多了")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .refreshable { await reload() }
            .scrollPosition($listPosition)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("重试") { Task { await reload() } }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private var cid: Int { subCategory?.id ?? topCategory.id }

    private func loadFirstIfNeeded() async {
        guard tracks.isEmpty else { return }
        await reload()
    }

    private func reload() async {
        page = 1
        hasMore = true
        isLoading = true
        loadError = nil
        do {
            let result = try await DjuuAPI.djlist(cid: cid, month: year, sort: sort, page: 1)
            tracks = result.tracks
            hasMore = result.hasMore
            listPosition.scrollTo(edge: .top)
        } catch {
            loadError = error.localizedDescription
            tracks = []
            hasMore = false
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        do {
            let result = try await DjuuAPI.djlist(cid: cid, month: year, sort: sort, page: page + 1)
            let existing = Set(tracks.map(\.id))
            tracks += result.tracks.filter { !existing.contains($0.id) }
            page += 1
            hasMore = result.hasMore
        } catch {
            hasMore = false
        }
        isLoading = false
    }
}

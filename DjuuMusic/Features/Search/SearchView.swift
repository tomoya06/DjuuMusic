import SwiftUI
import UIKit

/// 复刻站点右上角搜索：关键词 + 分类筛选 + 最新/最热排序。
struct SearchView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var sort = 1          // 1 最新 / 2 最热
    @State private var cid = 0
    @State private var searchedKeyword = ""

    @State private var tracks: [Track] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var listPosition = ScrollPosition()
    @FocusState private var fieldFocused: Bool

    private var categories: [(Int, String)] {
        [(0, "全部分类")] + DjuuCatalog.categories.map { ($0.id, $0.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            filterRow
            results
        }
        .background(Color(.systemBackground))
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fieldFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索 DJ 舞曲 / 串烧 / Remix", text: $keyword)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await reload() } }
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                        fieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular.interactive(), in: .capsule)

            Button("搜索") {
                fieldFocused = false
                Task { await reload() }
            }
            .buttonStyle(.glassProminent)
            .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(categories, id: \.0) { id, name in
                    Button(name) { cid = id }
                }
            } label: {
                let name = categories.first { $0.0 == cid }?.1 ?? "全部分类"
                HStack(spacing: 4) {
                    Text(name).font(.footnote)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            Spacer()

            ForEach([(1, "最新"), (2, "最热")], id: \.0) { value, name in
                Button(name) { sort = value }
                    .font(.footnote.weight(sort == value ? .semibold : .regular))
                    // 选中态玻璃底是强调色，文字须手动切白，否则粉底粉字（同首页 chip）
                    .foregroundStyle(sort == value ? Color.white : .primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .glassEffect(sort == value
                                 ? .regular.tint(.accentColor).interactive()
                                 : .regular.interactive(),
                                 in: .capsule)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var results: some View {
        if let loadError, tracks.isEmpty {
            VStack(spacing: 12) {
                Text(loadError).font(.footnote).foregroundStyle(.secondary)
                Button("重试") { Task { await reload() } }
                    .buttonStyle(.glassProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tracks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: searchedKeyword.isEmpty ? "music.mic" : "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(searchedKeyword.isEmpty ? "输入关键词开始搜索" : "没有找到相关内容")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
                    if isLoading { ProgressView().padding(.vertical, 12) }
                    if !hasMore {
                        Text("没有更多了")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 12)
            }
            .refreshable { await reload() }
            .scrollPosition($listPosition)
        }
    }

    // MARK: - Data

    private func reload() async {
        let query = keyword.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        searchedKeyword = query
        page = 1
        hasMore = true
        isLoading = true
        loadError = nil
        do {
            let result = try await DjuuAPI.search(keyword: query, cid: cid, sort: sort, page: 1)
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
            let result = try await DjuuAPI.search(keyword: searchedKeyword, cid: cid, sort: sort, page: page + 1)
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

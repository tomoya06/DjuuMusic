import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(PlayerModel.self) private var player

    @State private var content: HomeContent?
    @State private var loadError: String?
    @State private var selectedRecommended = 0
    @State private var selectedUpdate = 0

    var body: some View {
        NavigationStack {
            Group {
                if let content {
                    sectionsView(content)
                } else if let loadError {
                    errorView(loadError)
                } else {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("DJ呦呦")
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
            .task { await load() }
            .refreshable { await load(force: true) }
        }
    }

    // MARK: - Sections

    private func sectionsView(_ content: HomeContent) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                if !content.recommended.isEmpty {
                    section(title: "最新推荐",
                            sections: content.recommended,
                            selection: $selectedRecommended)
                }
                if !content.updates.isEmpty {
                    section(title: "最新更新",
                            sections: content.updates,
                            selection: $selectedUpdate)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func section(title: String,
                         sections: [HomeSection],
                         selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sections) { section in
                        let selected = section.id == selection.wrappedValue
                        Button {
                            Haptics.selection()
                            withAnimation(.snappy) { selection.wrappedValue = section.id }
                        } label: {
                            Text(section.title)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .glassEffect(selected
                                     ? .regular.tint(.accentColor).interactive()
                                     : .regular.interactive(),
                                     in: .capsule)
                    }
                }
                .padding(.horizontal, 16)
            }

            let active = sections.first(where: { $0.id == selection.wrappedValue }) ?? sections.first
            if let active {
                LazyVStack(spacing: 4) {
                    ForEach(Array(active.tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(index: nil,
                                 track: track,
                                 isCurrent: player.currentTrack?.id == track.id,
                                 onPlay: { player.play(track, in: active.tracks) },
                                 onPlayNext: { player.playNext(track) })
                    }
                }
                .padding(.horizontal, 12)
            }
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
            Button("重试") { Task { await load(force: true) } }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load(force: Bool = false) async {
        if content != nil && !force { return }
        do {
            loadError = nil
            content = try await DjuuAPI.home()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

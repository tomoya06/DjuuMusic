import SwiftUI

/// 完整播放历史页（个人中心「播放历史」Section 的入口）：
/// 全量列表 + 单条滑动删除 + 清空。
struct HistoryView: View {
    @Environment(PlayerModel.self) private var player
    @State private var history: [Track] = []

    var body: some View {
        Group {
            if history.isEmpty {
                ContentUnavailableView("暂无播放历史",
                                       systemImage: "clock.arrow.circlepath",
                                       description: Text("播放过的歌曲会记录在这里"))
            } else {
                List {
                    ForEach(history) { track in
                        TrackRow(index: nil,
                                 track: track,
                                 isCurrent: player.currentTrack?.id == track.id,
                                 onPlay: { player.play(track, in: history) },
                                 onPlayNext: nil)
                    }
                    .onDelete { offsets in
                        for offset in offsets where history.indices.contains(offset) {
                            LocalStore.removeHistory(id: history[offset].id)
                        }
                        history = LocalStore.history
                    }
                    Button(role: .destructive) {
                        LocalStore.clearHistory()
                        history = []
                    } label: {
                        Text("清空播放历史")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("播放历史")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { history = LocalStore.history }
    }
}

import SwiftUI

struct TrackRow: View {
    let index: Int?
    let track: Track
    let isCurrent: Bool
    var onPlay: () -> Void
    var onPlayNext: (() -> Void)?

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                if let index {
                    Text("\(index)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                        .frame(width: 26)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: isCurrent ? "waveform" : "play.circle")
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onPlay()
            } label: {
                Label("播放", systemImage: "play.fill")
            }
            if let onPlayNext {
                Button {
                    onPlayNext()
                } label: {
                    Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
            }
        }
    }

    private var meta: String {
        var parts: [String] = ["ID:\(track.id)"]
        if let hit = track.hit, !hit.isEmpty { parts.append("HIT:\(hit)") }
        if let date = track.date, !date.isEmpty { parts.append(date) }
        return parts.joined(separator: " · ")
    }
}

import SwiftUI
import UIKit

/// 触觉反馈只在有因果的 commit 时刻触发（播放/切歌/选择/成功/失败），
/// 过度反馈会让用户对所有反馈脱敏。
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

/// 行与小按钮的按压反馈：`.plain` 样式没有按下态，按下瞬间就应有响应，
/// 而不是等松手才见效果。轻微缩放 + 变暗，短 ease-out，无弹簧过冲。
struct PressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

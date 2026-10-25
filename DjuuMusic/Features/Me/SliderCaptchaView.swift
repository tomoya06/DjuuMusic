import SwiftUI
import UIKit

/// 复刻站点 tncode 滑块拼图验证码。
/// 站点返回 240×450 的三段拼图：
/// 第 1 段（y 0-150）带缺口背景 / 第 2 段（y 150-300）拼图块素材 / 第 3 段（y 300-450）完整背景。
/// 拖动结束后 POST /code/check?tn_r={偏移} 换取 token。
struct SliderCaptchaView: View {
    var onVerified: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var cleanImage: CGImage?
    @State private var holeImage: CGImage?
    @State private var pieceImage: CGImage?
    @State private var imageData: Data?

    @State private var offset: CGFloat = 0          // 显示坐标下的滑块位移
    @State private var isDragging = false
    @State private var phase: CaptchaPhase = .loading
    @State private var shakeTrigger: CGFloat = 0

    private let imageWidth: CGFloat = 240
    private let imageHeight: CGFloat = 150
    private let pieceWidth: CGFloat = 50

    private enum CaptchaPhase { case loading, ready, checking, success, failed }

    var body: some View {
        VStack(spacing: 18) {
            Text("拖动滑块完成拼图")
                .font(.headline)
                .padding(.top, 24)

            puzzle
                .frame(width: displayWidth, height: displayHeight)
                .overlay {
                    if phase == .loading {
                        ProgressView()
                            .frame(width: displayWidth, height: displayHeight)
                            .background(.ultraThinMaterial)
                    }
                }
                .modifier(ShakeEffect(trigger: shakeTrigger))

            slider
                .frame(width: displayWidth, height: 44)

            HStack(spacing: 16) {
                Button {
                    Task { await loadCaptcha() }
                } label: {
                    Label("换一张", systemImage: "arrow.clockwise")
                        .font(.footnote)
                }
                Button {
                    dismiss()
                } label: {
                    Text("取消")
                        .font(.footnote)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .task { await loadCaptcha() }
    }

    // MARK: - Puzzle canvas

    private var puzzle: some View {
        ZStack(alignment: .topLeading) {
            if phase == .success, let cleanImage {
                image(cleanImage)
            } else if isDragging || offset > 1, let holeImage {
                image(holeImage)
            } else if let cleanImage {
                image(cleanImage)
            }

            if let pieceImage, phase != .success {
                Image(decorative: pieceImage, scale: 1)
                    .resizable()
                    .frame(width: pieceWidth * scale, height: displayHeight)
                    .offset(x: offset, y: 0)
                    .shadow(radius: 3)
            }

            if phase == .success {
                VStack {
                    HStack {
                        Label("验证成功", systemImage: "checkmark.circle.fill")
                            .font(.footnote.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.green, in: Capsule())
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func image(_ cgImage: CGImage) -> some View {
        Image(decorative: cgImage, scale: 1)
            .resizable()
            .scaledToFit()
    }

    // MARK: - Slider

    private var slider: some View {
        let maxOffset = displayWidth - pieceWidth * scale
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.25))
                            .frame(width: offset + 22 * scale)
                    }
                }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 44, height: 36)
                .overlay {
                    Image(systemName: "chevron.right.2")
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                }
                .shadow(radius: 2)
                .offset(x: min(max(offset, 0), maxOffset))
                .gesture(dragGesture(maxOffset: maxOffset))
        }
    }

    private var hint: String {
        switch phase {
        case .loading: return "正在加载验证码…"
        case .checking: return "正在校验…"
        case .success: return "验证成功"
        case .failed: return "未通过，请重试"
        case .ready: return offset > 1 ? "" : "按住滑块拖动到缺口位置"
        }
    }

    private func dragGesture(maxOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard phase == .ready || phase == .failed else { return }
                isDragging = true
                offset = min(max(value.translation.width, 0), maxOffset)
            }
            .onEnded { _ in
                isDragging = false
                Task { await verify() }
            }
    }

    // MARK: - Data

    private var scale: CGFloat { displayWidth / imageWidth }
    private var displayWidth: CGFloat { min(UIScreen.main.bounds.width - 56, 300) }
    private var displayHeight: CGFloat { displayWidth * imageHeight / imageWidth }

    private func loadCaptcha() async {
        phase = .loading
        offset = 0
        pieceImage = nil
        holeImage = nil
        cleanImage = nil
        do {
            let data = try await DjuuAPI.sliderCaptchaImage()
            guard let full = CGImageSource.createImage(from: data),
                  let hole = full.cropping(to: CGRect(x: 0, y: 0, width: 240, height: 150)),
                  let pieceSource = full.cropping(to: CGRect(x: 0, y: 150, width: 50, height: 150)),
                  let clean = full.cropping(to: CGRect(x: 0, y: 300, width: 240, height: 150)) else {
                phase = .failed
                return
            }
            holeImage = hole
            cleanImage = clean
            pieceImage = Self.maskedPuzzlePiece(from: pieceSource)
            phase = .ready
        } catch {
            phase = .failed
        }
    }

    private func verify() async {
        guard phase == .ready || phase == .failed else { return }
        phase = .checking
        let tnR = Int((offset / scale).rounded())
        do {
            let token = try await DjuuAPI.sliderCheck(offset: tnR)
            withAnimation(.snappy) { phase = .success }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .seconds(0.6))
            onVerified(token)
            dismiss()
        } catch {
            phase = .failed
            shakeTrigger += 1
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            offset = 0
            await loadCaptcha()
        }
    }

    // MARK: - Piece masking（复刻 tncode._draw_mark 的透明化算法）

    /// 拼图块素材四周是纯黑区域：逐行从左右两端向内，将近黑色（RGB 之和 < 200）
    /// 的像素置为透明，边缘做 5px 渐变，得到带不规则边缘的拼图块。
    static func maskedPuzzlePiece(from source: CGImage) -> CGImage? {
        let width = source.width
        let height = source.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let buffer = context.data else { return nil }
        let pixels = buffer.assumingMemoryBound(to: UInt8.self)

        for row in 0..<height {
            var direction = 1
            var column = 0
            var turnaround = -1
            while column >= 0, column < width, column > turnaround {
                let base = 4 * (row * width + column)
                let dark = Int(pixels[base]) + Int(pixels[base + 1]) + Int(pixels[base + 2]) < 200
                column += direction
                if dark {
                    pixels[base + 3] = 0
                } else {
                    for step in 1...5 {
                        let target = column - step * direction
                        guard target >= 0, target < width else { continue }
                        let alphaIndex = 4 * (row * width + target) + 3
                        let alpha = 250 - (250 / 6) * step
                        pixels[alphaIndex] = UInt8(max(0, alpha))
                    }
                    if direction == -1 { break }
                    turnaround = column
                    column = width - 1
                    direction = -1
                }
            }
        }
        return context.makeImage()
    }
}

// MARK: - Helpers

extension CGImageSource {
    static func createImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

struct ShakeEffect: GeometryEffect {
    var trigger: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: 10 * sin(trigger * .pi * 4), y: 0))
    }
}

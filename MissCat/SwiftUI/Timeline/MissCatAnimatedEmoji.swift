import CoreGraphics
import Foundation
import SwiftUI

struct MissCatCustomEmojiFrame: @unchecked Sendable {
    let image: CGImage
    let duration: TimeInterval
}

struct MissCatCustomEmojiAnimation: @unchecked Sendable {
    let frames: [MissCatCustomEmojiFrame]
    let loopCount: Int

    var firstFrame: CGImage { frames[0].image }

    var totalDuration: TimeInterval {
        frames.reduce(0) { $0 + $1.duration }
    }

    var minimumFrameDuration: TimeInterval {
        frames.map(\.duration).min() ?? 0.1
    }

    func frameIndex(at elapsedTime: TimeInterval) -> Int {
        guard frames.count > 1,
              elapsedTime.isFinite,
              elapsedTime >= 0,
              totalDuration > 0 else { return 0 }
        if loopCount > 0,
           elapsedTime >= totalDuration * Double(loopCount) {
            return frames.index(before: frames.endIndex)
        }
        let cycleTime = elapsedTime.truncatingRemainder(dividingBy: totalDuration)
        var boundary: TimeInterval = 0
        for (index, frame) in frames.enumerated() {
            boundary += frame.duration
            if cycleTime < boundary { return index }
        }
        return frames.index(before: frames.endIndex)
    }
}

struct MissCatAnimatedEmojiContext: Equatable, Sendable {
    let pointSize: CGFloat
    let baselineInset: CGFloat

    static let timelineBody = MissCatAnimatedEmojiContext(pointSize: 30, baselineInset: 3)
    static let timelineAuthor = MissCatAnimatedEmojiContext(pointSize: 25, baselineInset: 3)
    static let reaction = MissCatAnimatedEmojiContext(pointSize: 30, baselineInset: 0)

    init(pointSize: CGFloat, baselineInset: CGFloat) {
        self.pointSize = max(pointSize, 1)
        self.baselineInset = min(max(baselineInset, 0), self.pointSize)
    }
}

struct MissCatAnimatedEmojiLayout: Equatable, Sendable {
    let size: CGSize
    let firstTextBaseline: CGFloat
}

enum MissCatAnimatedEmojiGeometry {
    static func layout(
        pixelWidth: Int,
        pixelHeight: Int,
        context: MissCatAnimatedEmojiContext
    ) -> MissCatAnimatedEmojiLayout {
        let safeWidth = max(pixelWidth, 1)
        let safeHeight = max(pixelHeight, 1)
        let height = context.pointSize
        let width = height * CGFloat(safeWidth) / CGFloat(safeHeight)
        return MissCatAnimatedEmojiLayout(
            size: CGSize(width: width, height: height),
            firstTextBaseline: height - context.baselineInset
        )
    }
}

/// SwiftUI-only playback for ImageIO animations. Its intrinsic size is stable
/// across frames so playback cannot change text wrapping or reaction geometry.
struct MissCatAnimatedEmojiView: View {
    let animation: MissCatCustomEmojiAnimation
    let context: MissCatAnimatedEmojiContext
    let accessibilityLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playbackStart = Date()

    private var layout: MissCatAnimatedEmojiLayout {
        MissCatAnimatedEmojiGeometry.layout(
            pixelWidth: animation.firstFrame.width,
            pixelHeight: animation.firstFrame.height,
            context: context
        )
    }

    var body: some View {
        let geometry = layout
        return Group {
            if animation.frames.count == 1 || reduceMotion {
                frame(animation.firstFrame)
            } else {
                TimelineView(.animation(minimumInterval: animation.minimumFrameDuration)) { timeline in
                    let elapsed = max(timeline.date.timeIntervalSince(playbackStart), 0)
                    let index = animation.frameIndex(at: elapsed)
                    frame(animation.frames[index].image)
                }
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .alignmentGuide(.firstTextBaseline) { _ in geometry.firstTextBaseline }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear { playbackStart = Date() }
    }

    private func frame(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: layout.size.width, height: layout.size.height)
    }
}

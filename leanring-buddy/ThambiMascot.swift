//
//  ThambiMascot.swift
//  leanring-buddy
//
//  Thambi's face: a cursor with eyes. A rounded square whose top-left corner stays sharp,
//  like the tip of a pointer, because Thambi lives next to your cursor and points at things.
//
//  Drawn entirely in code from plain geometry. There are no image files and nothing borrowed:
//  the same outline makes the panel mascot, the menu bar icon and the app icon.
//

import AppKit
import SwiftUI

// MARK: - Geometry (shared by SwiftUI and AppKit drawing)

nonisolated enum ThambiMascotArt {
    /// Corner roundness of the head, as a share of its side.
    static let cornerRadiusRatio: CGFloat = 0.30
    /// Eye centres and size, as shares of the head's side (top-left origin).
    static let leftEyeCenterX: CGFloat = 0.37
    static let rightEyeCenterX: CGFloat = 0.65
    static let eyeCenterY: CGFloat = 0.50
    static let eyeWidthRatio: CGFloat = 0.115
    static let eyeHeightRatio: CGFloat = 0.25

    /// The head: three round corners and one sharp one. `isFlipped` is true when y grows downward
    /// (SwiftUI); false for AppKit drawing, where the sharp corner still ends up at the top-left.
    static func headPath(in rect: CGRect, isFlipped: Bool) -> CGPath {
        let radius = rect.width * cornerRadiusRatio
        let path = CGMutablePath()
        let top = isFlipped ? rect.minY : rect.maxY
        let bottom = isFlipped ? rect.maxY : rect.minY
        // Start at the sharp tip and go clockwise as seen on screen.
        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX, y: bottom), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom), tangent2End: CGPoint(x: rect.minX, y: bottom), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom), tangent2End: CGPoint(x: rect.minX, y: top), radius: radius)
        path.closeSubpath()
        return path
    }

    /// One resting eye (a pill), for the still icons.
    static func eyeRect(in rect: CGRect, centerXRatio: CGFloat, isFlipped: Bool) -> CGRect {
        let width = rect.width * eyeWidthRatio
        let height = rect.height * eyeHeightRatio
        let centerY = isFlipped ? rect.minY + rect.height * eyeCenterY : rect.maxY - rect.height * eyeCenterY
        return CGRect(x: rect.minX + rect.width * centerXRatio - width / 2, y: centerY - height / 2, width: width, height: height)
    }

    /// The menu bar icon: the head in one colour with the eyes cut out. A template image, so
    /// macOS tints it for light and dark menu bars.
    @MainActor
    static func menuBarIcon(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let headRect = bounds.insetBy(dx: pointSize * 0.11, dy: pointSize * 0.11)
            context.addPath(headPath(in: headRect, isFlipped: false))
            for centerX in [leftEyeCenterX, rightEyeCenterX] {
                let eye = eyeRect(in: headRect, centerXRatio: centerX, isFlipped: false)
                context.addPath(CGPath(roundedRect: eye, cornerWidth: eye.width / 2, cornerHeight: eye.width / 2, transform: nil))
            }
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        return image
    }
}

private struct ThambiHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ThambiMascotArt.headPath(in: rect, isFlipped: true))
    }
}

/// A smiling eye: a short arc, open at the bottom.
private struct ThambiHappyEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6))
        return path
    }
}

// MARK: - The animated mascot

struct ThambiMascot: View {

    enum Mood: Equatable {
        /// Waiting. Blinks now and then.
        case idle
        /// Hearing you: eyes open wide and follow how loud you are.
        case listening
        /// Working something out, or looking at the screen: eyes glance side to side.
        case thinking
        /// Talking: a small mouth moves.
        case speaking
        /// Clicking or typing for you: leans toward its pointer tip.
        case acting
        /// Waiting for your go-ahead: steady, eyes up at you.
        case asking
        /// It worked.
        case happy
        /// It didn't.
        case sorry
    }

    var mood: Mood = .idle
    var size: CGFloat = 28
    /// 0...1, how loud the microphone is (only used while listening).
    var audioLevel: CGFloat = 0
    /// False while the mascot is hidden, so nothing ticks in the background.
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBlinking = false

    /// Moods that move all the time. The others hold a pose and only blink, which needs two
    /// redraws every few seconds instead of thirty a second.
    private var isContinuouslyAnimated: Bool {
        switch mood {
        case .thinking, .speaking, .acting: return true
        case .idle, .listening, .asking, .happy, .sorry: return false
        }
    }

    var body: some View {
        Group {
            if reduceMotion || !isActive {
                face(at: 0, isStill: true, isBlinking: false)
            } else if isContinuouslyAnimated {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    face(at: timeline.date.timeIntervalSinceReferenceDate, isStill: false, isBlinking: false)
                }
            } else {
                face(at: 0, isStill: true, isBlinking: isBlinking)
                    .animation(.easeOut(duration: 0.08), value: isBlinking)
                    .animation(.easeOut(duration: 0.12), value: audioLevel)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: mood)
        .task(id: isActive && !reduceMotion) {
            guard isActive, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_200_000_000)
                guard !Task.isCancelled else { return }
                isBlinking = true
                try? await Task.sleep(nanoseconds: 130_000_000)
                isBlinking = false
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Thambi")
        .accessibilityValue(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        switch mood {
        case .idle: return "ready"
        case .listening: return "listening"
        case .thinking: return "thinking"
        case .speaking: return "speaking"
        case .acting: return "working"
        case .asking: return "waiting for you"
        case .happy: return "done"
        case .sorry: return "couldn't finish"
        }
    }

    private func face(at time: TimeInterval, isStill: Bool, isBlinking: Bool) -> some View {
        let pose = Pose(mood: mood, time: time, isStill: isStill, audioLevel: audioLevel, isBlinking: isBlinking)
        let eyeWidth = size * ThambiMascotArt.eyeWidthRatio * pose.eyeWidthScale
        let eyeHeight = max(size * 0.035, size * ThambiMascotArt.eyeHeightRatio * pose.eyeHeightScale)
        let eyeY = size * (ThambiMascotArt.eyeCenterY - 0.5) + size * pose.eyeOffsetY

        return ZStack {
            ThambiHeadShape()
                .fill(DS.Colors.cool)

            ForEach([ThambiMascotArt.leftEyeCenterX, ThambiMascotArt.rightEyeCenterX], id: \.self) { centerX in
                Group {
                    if pose.hasHappyEyes {
                        ThambiHappyEyeShape()
                            .stroke(DS.Colors.well, style: StrokeStyle(lineWidth: max(1.2, size * 0.075), lineCap: .round))
                            .frame(width: size * 0.15, height: size * 0.07)
                    } else {
                        Capsule()
                            .fill(DS.Colors.well)
                            .frame(width: eyeWidth, height: eyeHeight)
                    }
                }
                .offset(x: size * (centerX - 0.5) + size * pose.eyeOffsetX, y: eyeY)
            }

            if pose.mouthOpenness > 0 {
                Capsule()
                    .fill(DS.Colors.well)
                    .frame(width: size * 0.14, height: size * (0.035 + 0.075 * pose.mouthOpenness))
                    .offset(x: size * 0.01, y: size * 0.24)
            }
        }
        .frame(width: size, height: size)
        .offset(x: size * pose.headOffset, y: size * pose.headOffset)
    }

    /// Where everything sits at one instant. Pure arithmetic on the clock, so there is no stored
    /// animation state to get out of step.
    private struct Pose {
        var eyeWidthScale: CGFloat = 1
        var eyeHeightScale: CGFloat = 1
        var eyeOffsetX: CGFloat = 0
        var eyeOffsetY: CGFloat = 0
        var mouthOpenness: CGFloat = 0
        var headOffset: CGFloat = 0
        var hasHappyEyes = false

        init(mood: Mood, time: TimeInterval, isStill: Bool, audioLevel: CGFloat, isBlinking: Bool) {
            // A blink: closed for a moment every few seconds.
            let blinkPhase = time.truncatingRemainder(dividingBy: 4.3)
            let blink: CGFloat = (isBlinking || (!isStill && blinkPhase < 0.14)) ? 0.12 : 1

            switch mood {
            case .idle:
                eyeHeightScale = blink
            case .listening:
                let level = min(max(audioLevel, 0), 1)
                eyeWidthScale = 1.25
                eyeHeightScale = 1.12 + 0.22 * level
            case .thinking:
                eyeHeightScale = 0.8 * blink
                eyeOffsetX = isStill ? 0.05 : 0.07 * CGFloat(sin(time * 2.4))
                eyeOffsetY = -0.04
            case .speaking:
                eyeHeightScale = 0.86 * blink
                eyeOffsetY = -0.05
                mouthOpenness = isStill ? 0.5 : 0.5 + 0.5 * CGFloat(sin(time * 11) * sin(time * 3.1))
                mouthOpenness = max(0.08, mouthOpenness)
            case .acting:
                eyeHeightScale = 0.9
                eyeOffsetX = -0.07
                eyeOffsetY = -0.07
                headOffset = isStill ? 0 : -0.035 * CGFloat(max(0, sin(time * 5)))
            case .asking:
                eyeHeightScale = 1.1 * blink
                eyeWidthScale = 1.1
                eyeOffsetY = -0.03
            case .happy:
                hasHappyEyes = true
            case .sorry:
                eyeHeightScale = 0.3
                eyeOffsetY = 0.05
            }
        }
    }
}

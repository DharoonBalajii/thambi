//
//  TargetArrowLayout.swift
//  leanring-buddy
//
//  LOCAL ADDITION: pure layout math for the "arrow pointing at the target" drawing.
//
//  Goal: the thing being pointed at must never be covered. So the cursor ("buddy") and its
//  label rest AWAY from the target, at the tail of an arrow whose head stops just short of it:
//
//        [label][buddy] ───────────▶ ·target
//
//  No dependencies beyond CoreGraphics, so it can be unit-tested on its own.
//

import CoreGraphics
import Foundation

enum TargetArrowLayout {
    /// Gap between the arrow head's tip and the exact target point (the target itself stays visible).
    static let gapBetweenArrowHeadAndTarget: CGFloat = 12
    static let arrowLength: CGFloat = 95
    /// Gap between the buddy cursor and the start of the arrow shaft.
    static let gapBetweenBuddyAndArrowTail: CGFloat = 14
    static let screenEdgePadding: CGFloat = 20
    private static let diagonalUnit: CGFloat = 0.70710678

    /// How far the buddy rests from the target along the arrow direction.
    static var buddyDistanceFromTarget: CGFloat {
        gapBetweenArrowHeadAndTarget + arrowLength + gapBetweenBuddyAndArrowTail
    }

    /// Where the buddy cursor rests: up and to the left of the target by default (usually empty
    /// space, while captions tend to sit below), flipping to the other side only when there isn't
    /// room before the screen edge. Always kept inside the screen.
    static func buddyRestingPosition(forTarget target: CGPoint, screenSize: CGSize) -> CGPoint {
        let diagonalDistance = buddyDistanceFromTarget * diagonalUnit
        let horizontalSign: CGFloat = (target.x - diagonalDistance >= screenEdgePadding) ? -1 : 1
        let verticalSign: CGFloat = (target.y - diagonalDistance >= screenEdgePadding) ? -1 : 1
        let rawPosition = CGPoint(
            x: target.x + horizontalSign * diagonalDistance,
            y: target.y + verticalSign * diagonalDistance
        )
        return CGPoint(
            x: max(screenEdgePadding, min(rawPosition.x, screenSize.width - screenEdgePadding)),
            y: max(screenEdgePadding, min(rawPosition.y, screenSize.height - screenEdgePadding))
        )
    }

    /// CONTENT-AWARE placement: tries many directions and arrow lengths and picks the one where the
    /// arrow, the cursor and the label cover the least text/graphics on screen, so nothing readable
    /// is hidden. Falls back to the simple geometric placement when there is no screenshot map.
    static func bestBuddyRestingPosition(
        forTarget target: CGPoint,
        screenSize: CGSize,
        bubbleSize: CGSize,
        busyness: ScreenBusynessMap?
    ) -> CGPoint {
        guard let busyness else { return buddyRestingPosition(forTarget: target, screenSize: screenSize) }

        let candidateArrowLengths: [CGFloat] = [60, 85, 110, 140]
        let directionStepCount = 24
        let preferredAngle = -3 * Double.pi / 4   // up-left, the classic look, used only as a tie-breaker
        var best: (score: Float, position: CGPoint)?

        for arrowLength in candidateArrowLengths {
            let distanceFromTarget = gapBetweenArrowHeadAndTarget + arrowLength + gapBetweenBuddyAndArrowTail
            for step in 0..<directionStepCount {
                let angle = Double(step) * 2 * Double.pi / Double(directionStepCount)
                let candidatePosition = CGPoint(
                    x: target.x + CGFloat(cos(angle)) * distanceFromTarget,
                    y: target.y + CGFloat(sin(angle)) * distanceFromTarget
                )
                guard candidatePosition.x >= screenEdgePadding,
                      candidatePosition.y >= screenEdgePadding,
                      candidatePosition.x <= screenSize.width - screenEdgePadding,
                      candidatePosition.y <= screenSize.height - screenEdgePadding else { continue }

                let endpoints = arrowEndpoints(target: target, buddyRestingPosition: candidatePosition)
                let arrowBusyness = busyness.busynessAlongSegment(from: endpoints.tail, to: endpoints.head)

                let labelCenter = bubbleCenter(buddyPosition: candidatePosition, target: target, bubbleSize: bubbleSize, screenSize: screenSize)
                let labelRect = CGRect(
                    x: labelCenter.x - bubbleSize.width / 2, y: labelCenter.y - bubbleSize.height / 2,
                    width: bubbleSize.width, height: bubbleSize.height
                )
                // The label must never sit on the target itself.
                let distanceFromTargetToLabel = hypot(
                    max(labelRect.minX - target.x, 0, target.x - labelRect.maxX),
                    max(labelRect.minY - target.y, 0, target.y - labelRect.maxY)
                )
                guard distanceFromTargetToLabel >= 40 else { continue }
                let labelBusyness = busyness.meanBusyness(in: labelRect)

                let cursorRect = CGRect(x: candidatePosition.x - 12, y: candidatePosition.y - 12, width: 24, height: 24)
                let cursorBusyness = busyness.meanBusyness(in: cursorRect)

                var angleFromPreferred = abs(angle - preferredAngle).truncatingRemainder(dividingBy: 2 * Double.pi)
                if angleFromPreferred > Double.pi { angleFromPreferred = 2 * Double.pi - angleFromPreferred }

                let score = 3.0 * arrowBusyness
                    + 2.5 * labelBusyness
                    + 2.0 * cursorBusyness
                    + 0.10 * Float(arrowLength / 140)
                    + 0.06 * Float(angleFromPreferred / Double.pi)
                if best == nil || score < best!.score {
                    best = (score, candidatePosition)
                }
            }
        }
        return best?.position ?? buddyRestingPosition(forTarget: target, screenSize: screenSize)
    }

    /// The label bubble's size is only known once it is drawn; this estimate (11pt medium text plus
    /// padding) is accurate enough to choose where it will go.
    static func estimatedBubbleSize(forLabel label: String?) -> CGSize {
        let characterCount = CGFloat(label?.count ?? 10)
        return CGSize(width: min(max(characterCount * 6.4 + 18, 60), 260), height: 24)
    }

    /// Unit vector pointing from the target toward the buddy.
    static func unitVectorFromTarget(toBuddy buddyPosition: CGPoint, target: CGPoint) -> CGPoint {
        let deltaX = buddyPosition.x - target.x
        let deltaY = buddyPosition.y - target.y
        let length = hypot(deltaX, deltaY)
        guard length > 0.001 else { return CGPoint(x: -diagonalUnit, y: -diagonalUnit) }
        return CGPoint(x: deltaX / length, y: deltaY / length)
    }

    /// The arrow runs from just beside the buddy (tail) to just short of the target (head).
    static func arrowEndpoints(target: CGPoint, buddyRestingPosition: CGPoint) -> (tail: CGPoint, head: CGPoint) {
        let towardBuddy = unitVectorFromTarget(toBuddy: buddyRestingPosition, target: target)
        let head = CGPoint(
            x: target.x + towardBuddy.x * gapBetweenArrowHeadAndTarget,
            y: target.y + towardBuddy.y * gapBetweenArrowHeadAndTarget
        )
        let tail = CGPoint(
            x: buddyRestingPosition.x - towardBuddy.x * gapBetweenBuddyAndArrowTail,
            y: buddyRestingPosition.y - towardBuddy.y * gapBetweenBuddyAndArrowTail
        )
        return (tail, head)
    }

    /// Where the label bubble goes: on the far side of the buddy from the target, so it never
    /// sits on the thing being pointed at. Kept fully on screen.
    static func bubbleCenter(buddyPosition: CGPoint, target: CGPoint, bubbleSize: CGSize, screenSize: CGSize) -> CGPoint {
        let awayFromTarget = unitVectorFromTarget(toBuddy: buddyPosition, target: target)
        let halfWidth = bubbleSize.width / 2
        let halfHeight = bubbleSize.height / 2
        let rawCenter = CGPoint(
            x: buddyPosition.x + awayFromTarget.x * (halfWidth + 12),
            y: buddyPosition.y + awayFromTarget.y * (halfHeight + 10)
        )
        let edgePadding: CGFloat = 8
        return CGPoint(
            x: max(halfWidth + edgePadding, min(rawCenter.x, screenSize.width - halfWidth - edgePadding)),
            y: max(halfHeight + edgePadding, min(rawCenter.y, screenSize.height - halfHeight - edgePadding))
        )
    }
}

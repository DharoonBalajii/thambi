//
//  ScreenBusynessMap.swift
//  leanring-buddy
//
//  LOCAL ADDITION: a coarse "how busy is each part of the screen" grid, built from the screenshot
//  Clicky already took. Busy = lots of edges (text, icons, box borders). Empty areas and flat
//  colour fills score zero.
//
//  The arrow placement uses it to put the arrow, the cursor and the label where they cover the
//  least content, instead of always drawing from the same corner and crossing text.
//
//  All queries are in screen POINTS with a top-left origin (the same space the overlay draws in).
//

import CoreGraphics
import Foundation
import ImageIO

final class ScreenBusynessMap: @unchecked Sendable {
    let screenSizeInPoints: CGSize
    private let columnCount: Int
    private let rowCount: Int
    /// Fraction of edge pixels in each cell, 0...1.
    private let density: [Float]
    /// The same grid with each cell replaced by the max of its 3x3 neighbourhood: roughly the
    /// footprint of a ~9pt-thick arrow line.
    private let dilatedDensity: [Float]
    /// Summed-area table of `density`, for fast rectangle averages.
    private let summedAreaTable: [Float]

    // MARK: - Building

    /// Builds the map from a screenshot (JPEG/PNG data). Returns nil if the image can't be decoded.
    convenience init?(imageData: Data, screenSizeInPoints: CGSize) {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }
        self.init(cgImage: cgImage, screenSizeInPoints: screenSizeInPoints)
    }

    convenience init?(cgImage: CGImage, screenSizeInPoints: CGSize) {
        // Work on a grayscale copy no wider than 1280px: that is the size Claude sees anyway.
        let workingWidth = min(cgImage.width, 1280)
        let workingHeight = max(1, Int((Double(cgImage.height) * Double(workingWidth) / Double(cgImage.width)).rounded()))
        var pixels = [UInt8](repeating: 0, count: workingWidth * workingHeight)
        let drewImage = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let context = CGContext(
                data: rawBuffer.baseAddress, width: workingWidth, height: workingHeight,
                bitsPerComponent: 8, bytesPerRow: workingWidth,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: workingWidth, height: workingHeight))
            return true
        }
        guard drewImage else { return nil }
        self.init(grayscalePixels: pixels, width: workingWidth, height: workingHeight, screenSizeInPoints: screenSizeInPoints)
    }

    /// Edge pixels -> per-cell density. Cells are 4x4 pixels of the working image.
    convenience init(grayscalePixels: [UInt8], width: Int, height: Int, screenSizeInPoints: CGSize) {
        let cellSizeInPixels = 4
        let columns = max(1, width / cellSizeInPixels)
        let rows = max(1, height / cellSizeInPixels)
        var edgeCounts = [Float](repeating: 0, count: columns * rows)
        let edgeThreshold = 32   // |dx| + |dy| of 0...255 luminance

        if width > 2 && height > 2 {
            for y in 1..<(height - 1) {
                let rowOffset = y * width
                let cellRow = min(rows - 1, y / cellSizeInPixels)
                for x in 1..<(width - 1) {
                    let horizontalChange = abs(Int(grayscalePixels[rowOffset + x + 1]) - Int(grayscalePixels[rowOffset + x - 1]))
                    let verticalChange = abs(Int(grayscalePixels[rowOffset + x + width]) - Int(grayscalePixels[rowOffset + x - width]))
                    if horizontalChange + verticalChange > edgeThreshold {
                        let cellColumn = min(columns - 1, x / cellSizeInPixels)
                        edgeCounts[cellRow * columns + cellColumn] += 1
                    }
                }
            }
        }
        let pixelsPerCell = Float(cellSizeInPixels * cellSizeInPixels)
        let densityGrid = edgeCounts.map { min(1, $0 / pixelsPerCell * 2) }   // x2: text rarely fills >50% of a cell
        self.init(density: densityGrid, columnCount: columns, rowCount: rows, screenSizeInPoints: screenSizeInPoints)
    }

    /// Direct construction from a density grid (also used by tests).
    init(density: [Float], columnCount: Int, rowCount: Int, screenSizeInPoints: CGSize) {
        precondition(density.count == columnCount * rowCount)
        self.screenSizeInPoints = screenSizeInPoints
        self.columnCount = columnCount
        self.rowCount = rowCount
        self.density = density

        var dilated = density
        for row in 0..<rowCount {
            for column in 0..<columnCount {
                var maximum: Float = 0
                for neighbourRow in max(0, row - 1)...min(rowCount - 1, row + 1) {
                    for neighbourColumn in max(0, column - 1)...min(columnCount - 1, column + 1) {
                        maximum = max(maximum, density[neighbourRow * columnCount + neighbourColumn])
                    }
                }
                dilated[row * columnCount + column] = maximum
            }
        }
        self.dilatedDensity = dilated

        var table = [Float](repeating: 0, count: (columnCount + 1) * (rowCount + 1))
        for row in 0..<rowCount {
            var runningRowSum: Float = 0
            for column in 0..<columnCount {
                runningRowSum += density[row * columnCount + column]
                table[(row + 1) * (columnCount + 1) + (column + 1)] = table[row * (columnCount + 1) + (column + 1)] + runningRowSum
            }
        }
        self.summedAreaTable = table
    }

    // MARK: - Queries (screen points, top-left origin)

    private var pointsPerColumn: CGFloat { screenSizeInPoints.width / CGFloat(columnCount) }
    private var pointsPerRow: CGFloat { screenSizeInPoints.height / CGFloat(rowCount) }

    /// Average busyness (0...1) inside a rectangle. Parts outside the screen count as busy, so
    /// placements that run off the edge are never preferred.
    func meanBusyness(in rectInPoints: CGRect) -> Float {
        let screenRect = CGRect(origin: .zero, size: screenSizeInPoints)
        let clipped = rectInPoints.intersection(screenRect)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return 1 }

        let firstColumn = max(0, min(columnCount - 1, Int(clipped.minX / pointsPerColumn)))
        let lastColumn = max(firstColumn, min(columnCount - 1, Int((clipped.maxX - 0.001) / pointsPerColumn)))
        let firstRow = max(0, min(rowCount - 1, Int(clipped.minY / pointsPerRow)))
        let lastRow = max(firstRow, min(rowCount - 1, Int((clipped.maxY - 0.001) / pointsPerRow)))

        let stride = columnCount + 1
        let sum = summedAreaTable[(lastRow + 1) * stride + (lastColumn + 1)]
            - summedAreaTable[firstRow * stride + (lastColumn + 1)]
            - summedAreaTable[(lastRow + 1) * stride + firstColumn]
            + summedAreaTable[firstRow * stride + firstColumn]
        let cellCount = Float((lastColumn - firstColumn + 1) * (lastRow - firstRow + 1))
        let insideMean = sum / cellCount

        let insideFraction = Float((clipped.width * clipped.height) / (rectInPoints.width * rectInPoints.height))
        return insideMean * insideFraction + (1 - insideFraction)
    }

    /// Average busyness (0...1) along a line of arrow thickness from one point to another.
    func busynessAlongSegment(from start: CGPoint, to end: CGPoint) -> Float {
        let length = hypot(end.x - start.x, end.y - start.y)
        let sampleCount = max(2, Int(length / max(1, min(pointsPerColumn, pointsPerRow))))
        var total: Float = 0
        for sampleIndex in 0...sampleCount {
            let fraction = CGFloat(sampleIndex) / CGFloat(sampleCount)
            let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            total += dilatedDensityAt(point)
        }
        return total / Float(sampleCount + 1)
    }

    private func dilatedDensityAt(_ point: CGPoint) -> Float {
        guard point.x >= 0, point.y >= 0, point.x < screenSizeInPoints.width, point.y < screenSizeInPoints.height else { return 1 }
        let column = min(columnCount - 1, Int(point.x / pointsPerColumn))
        let row = min(rowCount - 1, Int(point.y / pointsPerRow))
        return dilatedDensity[row * columnCount + column]
    }
}

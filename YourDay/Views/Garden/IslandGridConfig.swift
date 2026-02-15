//
//  IslandGridConfig.swift
//  YourDay
//

import Foundation
import UIKit

struct IslandGridConfig {
    /// Set to `true` to enable the dev-mode grid overlay for positioning tiles on the island.
    static let devMode = false

    static let gridColumns = 10
    static let gridRows = 8
    static let totalTiles = gridColumns * gridRows // 80

    // Grid bounds as fractional offsets of the island image
    // These define where the grid sits on top of the island
    static let gridLeftFraction: CGFloat = 0.10
    static let gridTopFraction: CGFloat = 0.15
    static let gridWidthFraction: CGFloat = 0.80
    static let gridHeightFraction: CGFloat = 0.65

    // Map-space offset baked in from dev-mode calibration.
    // Applied in mapPosition(for:) so the grid aligns with the island art.
    static let calibratedMapOffset = CGSize(width: 13.33333333333212, height: -713.3333333333339)

    // The 43 valid tile positions that fit on the island (from dev-mode calibration).
    // To recalibrate: set devMode = true, drag the grid, tap tiles, read the console output,
    // then paste the active tiles here and update calibratedMapOffset above.
    static let validTilePositions: Set<String> = [
        "1,1", "2,1", "3,1", "4,1", "5,1", "6,1", "7,1", "8,1",
        "0,2", "1,2", "2,2", "3,2", "4,2", "5,2", "6,2", "7,2", "8,2", "9,2",
        "0,3", "1,3", "2,3", "3,3", "4,3", "5,3", "6,3", "7,3", "8,3", "9,3",
        "0,4", "1,4", "2,4", "3,4", "4,4", "5,4", "6,4", "7,4", "9,4",
        "1,5", "2,5", "3,5", "4,5", "5,5", "6,5"
    ]

    /// Check whether a grid position is valid (fits on the island).
    static func isValidPosition(_ pos: GridPosition) -> Bool {
        validTilePositions.contains("\(pos.x),\(pos.y)")
    }

    // Cached island image size
    static var islandImageSize: CGSize {
        let islandName = GardenAssetHelper.islandImageName()
        if let image = UIImage(named: islandName) {
            return image.size
        }
        return CGSize(width: 800, height: 600) // fallback
    }

    // Tile size computed from island image and grid dimensions
    static var tileSize: CGSize {
        let imgSize = islandImageSize
        let gridW = imgSize.width * gridWidthFraction
        let gridH = imgSize.height * gridHeightFraction
        return CGSize(
            width: gridW / CGFloat(gridColumns),
            height: gridH / CGFloat(gridRows)
        )
    }

    // Convert a grid position to a point in island-image space (center of tile)
    static func tileCenter(for pos: GridPosition) -> CGPoint {
        let imgSize = islandImageSize
        let gridOriginX = imgSize.width * gridLeftFraction
        let gridOriginY = imgSize.height * gridTopFraction
        let ts = tileSize

        return CGPoint(
            x: gridOriginX + (CGFloat(pos.x) + 0.5) * ts.width,
            y: gridOriginY + (CGFloat(pos.y) + 0.5) * ts.height
        )
    }

    // Where the island image center sits in map space
    static func islandCenterInMapSpace() -> CGPoint {
        guard let mapDims = GardenMapConfig.mapDimensions() else {
            return .zero
        }
        return CGPoint(x: mapDims.width / 2, y: mapDims.height / 2)
    }

    // Island image rendering size (scaled to look good on the map)
    static var islandDisplaySize: CGSize {
        let imgSize = islandImageSize
        // Scale island to roughly 40% of map width, maintaining aspect ratio
        guard let mapDims = GardenMapConfig.mapDimensions() else {
            return imgSize
        }
        let targetWidth = mapDims.width * 0.35
        let scale = targetWidth / imgSize.width
        return CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
    }

    /// Minimum zoom scale that fits the entire island (with padding) on screen.
    static func minimumZoomToFitIsland(for screenSize: CGSize, padding: CGFloat = 40) -> CGFloat {
        let display = islandDisplaySize
        guard display.width > 0, display.height > 0 else { return 0.1 }
        let scaleX = (screenSize.width - padding * 2) / display.width
        let scaleY = (screenSize.height - padding * 2) / display.height
        return min(scaleX, scaleY)
    }

    /// Pan offset that centers the island on screen at a given zoom scale.
    static func panOffsetToCenterIsland(for screenSize: CGSize, zoomScale: CGFloat) -> CGSize {
        let center = islandCenterInMapSpace()
        return CGSize(
            width: screenSize.width / 2 - center.x * zoomScale,
            height: screenSize.height / 2 - center.y * zoomScale
        )
    }

    // Tile unlock order: only valid positions, sorted by distance from grid center (center-outward spiral)
    static let tileUnlockOrder: [GridPosition] = {
        let centerX = Double(gridColumns - 1) / 2.0
        let centerY = Double(gridRows - 1) / 2.0

        var positions: [(pos: GridPosition, dist: Double)] = []
        for row in 0..<gridRows {
            for col in 0..<gridColumns {
                let pos = GridPosition(x: col, y: row)
                guard isValidPosition(pos) else { continue }
                let dx = Double(col) - centerX
                let dy = Double(row) - centerY
                let dist = sqrt(dx * dx + dy * dy)
                positions.append((pos, dist))
            }
        }

        // Sort by distance from center, then by row then column for ties
        positions.sort { a, b in
            if abs(a.dist - b.dist) < 0.001 {
                if a.pos.y != b.pos.y { return a.pos.y < b.pos.y }
                return a.pos.x < b.pos.x
            }
            return a.dist < b.dist
        }

        return positions.map { $0.pos }
    }()

    // First N positions from unlock order
    static func unlockedPositions(count: Int) -> [GridPosition] {
        let clamped = min(max(0, count), tileUnlockOrder.count)
        return Array(tileUnlockOrder.prefix(clamped))
    }

    /// Tile size in map / display-space units (unscaled by zoom).
    static var displayTileSize: CGSize {
        let displaySize = islandDisplaySize
        let gridW = displaySize.width * gridWidthFraction
        let gridH = displaySize.height * gridHeightFraction
        return CGSize(
            width: gridW / CGFloat(gridColumns),
            height: gridH / CGFloat(gridRows)
        )
    }

    /// Absolute map-space position for a grid tile (island center + offset + calibration).
    static func mapPosition(for pos: GridPosition) -> CGPoint {
        let center = islandCenterInMapSpace()
        let offset = tileOffsetFromIslandCenter(for: pos)
        return CGPoint(
            x: center.x + offset.x + calibratedMapOffset.width,
            y: center.y + offset.y + calibratedMapOffset.height
        )
    }

    /// Tile offset from the island center (in unscaled island-display units).
    /// This is purely relative to the island — no map, zoom, or pan involved.
    static func tileOffsetFromIslandCenter(for pos: GridPosition) -> CGPoint {
        let displaySize = islandDisplaySize

        // Grid area within the island
        let gridOriginX = -displaySize.width / 2 + displaySize.width * gridLeftFraction
        let gridOriginY = -displaySize.height / 2 + displaySize.height * gridTopFraction
        let gridW = displaySize.width * gridWidthFraction
        let gridH = displaySize.height * gridHeightFraction
        let tw = gridW / CGFloat(gridColumns)
        let th = gridH / CGFloat(gridRows)

        return CGPoint(
            x: gridOriginX + (CGFloat(pos.x) + 0.5) * tw,
            y: gridOriginY + (CGFloat(pos.y) + 0.5) * th
        )
    }

    /// Screen position of a tile, derived from the island's screen center.
    /// Because both the island image and the grid use the same center + offset * zoom
    /// formula, they stay locked together at every zoom / pan level.
    static func screenPosition(for pos: GridPosition, zoomScale: CGFloat, panOffset: CGSize) -> CGPoint {
        let islandCenter = islandCenterInMapSpace()
        let islandScreenX = islandCenter.x * zoomScale + panOffset.width
        let islandScreenY = islandCenter.y * zoomScale + panOffset.height

        let offset = tileOffsetFromIslandCenter(for: pos)

        return CGPoint(
            x: islandScreenX + offset.x * zoomScale + calibratedMapOffset.width * zoomScale,
            y: islandScreenY + offset.y * zoomScale + calibratedMapOffset.height * zoomScale
        )
    }

    // Tile size in screen space
    static func screenTileSize(zoomScale: CGFloat) -> CGSize {
        let displaySize = islandDisplaySize
        let gridW = displaySize.width * gridWidthFraction
        let gridH = displaySize.height * gridHeightFraction
        return CGSize(
            width: (gridW / CGFloat(gridColumns)) * zoomScale,
            height: (gridH / CGFloat(gridRows)) * zoomScale
        )
    }

    // MARK: - Dev Mode Helpers

    /// All grid positions in the full rectangle (used by dev mode overlay).
    static var allGridPositions: [GridPosition] {
        var positions: [GridPosition] = []
        for row in 0..<gridRows {
            for col in 0..<gridColumns {
                positions.append(GridPosition(x: col, y: row))
            }
        }
        return positions
    }

    /// Screen position with an additional dev-mode drag offset (in screen points).
    static func screenPosition(for pos: GridPosition, zoomScale: CGFloat, panOffset: CGSize, devOffset: CGSize) -> CGPoint {
        let base = screenPosition(for: pos, zoomScale: zoomScale, panOffset: panOffset)
        return CGPoint(x: base.x + devOffset.width, y: base.y + devOffset.height)
    }
}

//
//  PlotTileNode.swift
//  YourDay
//
//  An unlocked, unoccupied soil plot. All tiles share one texture pre-rendered
//  from the SwiftUI EmptyTileView, so the gradients/shadows are baked once
//  instead of composited live per tile per frame like the legacy path.
//

import SpriteKit

final class PlotTileNode: SKSpriteNode {
    let gridPosition: GridPosition

    /// - Parameter tileSize: full tile size in map units; EmptyTileView draws
    ///   itself at the legacy 0.92 inset, so the sprite matches that footprint.
    init(gridPosition: GridPosition, texture: SKTexture?, tileSize: CGSize) {
        self.gridPosition = gridPosition
        let size = CGSize(width: tileSize.width * 0.92, height: tileSize.height * 0.92)
        super.init(texture: texture, color: .clear, size: size)
        if texture == nil {
            // Visible fallback if pre-rendering ever fails.
            color = UIColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 0.9)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

//
//  OceanBackgroundNode.swift
//  YourDay
//
//  Ocean water + winter icebergs for GardenScene.
//
//  The legacy Canvas drew a 30×30 grid of tiles each scaled ×2, so every
//  screen pixel was painted ~4 times. Here the same on-screen texture scale is
//  achieved with a 15×15 SKTileMapNode whose tiles are 2× the base cell size —
//  non-overlapping, one shared texture, batched into a single draw.
//

import SpriteKit

final class OceanBackgroundNode: SKNode {
    private enum Layer {
        static let ocean: CGFloat = 0
        static let icebergs: CGFloat = 10
    }

    private var tileMap: SKTileMapNode?
    private let icebergLayer = SKNode()

    func build(geometry: GardenSceneGeometry, textures: GardenTextureProvider) {
        removeAllChildren()
        tileMap = nil

        buildOcean(geometry: geometry, textures: textures)

        icebergLayer.zPosition = Layer.icebergs
        addChild(icebergLayer)
        rebuildIcebergs(geometry: geometry, textures: textures)
    }

    // MARK: - Ocean

    private func buildOcean(geometry: GardenSceneGeometry, textures: GardenTextureProvider) {
        guard let texture = textures.backdropTexture,
              let baseTile = GardenMapConfig.tileSize() else { return }

        // 2× stride keeps the water texture at the exact on-screen scale of the
        // legacy backdropScale=2.0 rendering while halving the tile counts.
        let stride = CGSize(
            width: baseTile.width * GardenMapConfig.backdropScale,
            height: baseTile.height * GardenMapConfig.backdropScale
        )
        guard stride.width > 0, stride.height > 0 else { return }

        let columns = Int(ceil(geometry.mapWidth / stride.width))
        let rows = Int(ceil(geometry.mapHeight / stride.height))
        guard columns > 0, rows > 0 else { return }

        let definition = SKTileDefinition(texture: texture, size: stride)
        let group = SKTileGroup(tileDefinition: definition)
        let tileSet = SKTileSet(tileGroups: [group])

        let map = SKTileMapNode(tileSet: tileSet, columns: columns, rows: rows, tileSize: stride)
        map.fill(with: group)
        map.anchorPoint = .zero
        map.position = .zero
        map.zPosition = Layer.ocean
        addChild(map)
        tileMap = map
    }

    // MARK: - Icebergs (winter daytime only; ported from the legacy generator)

    func rebuildIcebergs(geometry: GardenSceneGeometry, textures: GardenTextureProvider) {
        icebergLayer.removeAllChildren()
        guard GardenAssetHelper.isWinterDaytime() else { return }

        let pieceTextures = textures.icebergTextures()
        guard !pieceTextures.isEmpty else { return }

        var placedPositions: [CGPoint] = []
        let maxAttempts = GardenMapConfig.icebergCount * 20
        var attempts = 0

        while placedPositions.count < GardenMapConfig.icebergCount, attempts < maxAttempts {
            attempts += 1

            let mapPosition = CGPoint(
                x: CGFloat.random(in: 0...geometry.mapWidth),
                y: CGFloat.random(in: (geometry.mapHeight * 0.08)...(geometry.mapHeight * 0.72))
            )

            let tooClose = placedPositions.contains { existing in
                hypot(mapPosition.x - existing.x, mapPosition.y - existing.y) < GardenMapConfig.icebergMinSpacing
            }
            if tooClose { continue }
            placedPositions.append(mapPosition)

            guard let texture = pieceTextures.randomElement() else { continue }
            let scale = CGFloat.random(in: 0.5...1.05)
            let sprite = SKSpriteNode(texture: texture)
            sprite.size = CGSize(
                width: texture.size().width * scale * GardenMapConfig.icebergAssetScaleMultiplier,
                height: texture.size().height * scale * GardenMapConfig.icebergAssetScaleMultiplier
            )
            sprite.alpha = CGFloat.random(in: 0.78...0.96)
            sprite.position = geometry.scenePoint(fromMap: mapPosition)
            icebergLayer.addChild(sprite)
        }
    }
}

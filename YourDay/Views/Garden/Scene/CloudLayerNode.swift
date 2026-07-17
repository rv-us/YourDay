//
//  CloudLayerNode.swift
//  YourDay
//
//  Drifting cloud clusters for GardenScene, replacing the legacy 30fps
//  Timer.publish + @State approach. Movement, fade-in, and respawn are all
//  SKActions (zero per-frame Swift work); the only per-frame pass is the
//  viewport edge-fade over ≤ ~10 nodes, driven from GardenScene.update().
//
//  Density note: the legacy config produced ~224 clusters (tilesPerCluster=4);
//  the comment intent was ~1 cluster per 125 tiles. This layer uses 2 clusters
//  per map quadrant (8 total), matching that intent.
//

import SpriteKit

final class CloudLayerNode: SKNode {
    private enum Config {
        // Visual density knob. Legacy rendered ~56/quadrant (a config bug that
        // also tanked SwiftUI perf); 2/quadrant read as too sparse on device.
        // SKAction clouds are cheap — raise/lower freely to taste.
        static let clustersPerQuadrant = 8
        static let piecesPerCluster = 4...8
        // Legacy speeds were 0.3–0.8 map-px per 1/30s tick.
        static let speedRange: ClosedRange<CGFloat> = (0.3 * 30)...(0.8 * 30) // map-px/sec
        static let directionRange: ClosedRange<CGFloat> = -0.3...0.3
        static let respawnXRange: ClosedRange<CGFloat> = -250 ... -50
        static let despawnMargin: CGFloat = 300
        static let fadeInDuration: TimeInterval = 2.0
        static let edgeFadeMapDistance: CGFloat = 200 // legacy fadeMargin was 200 × zoom in screen px
    }

    /// Wrapper (this class's direct children) carries the edge-fade alpha;
    /// its single child carries the fade-in action alpha. Nested alphas
    /// multiply, so the two fades never fight.
    private final class ClusterWrapper: SKNode {
        var quadrantIndex = 0
    }

    private var geometry: GardenSceneGeometry?
    private var quadrantTextures: [SKTexture] = []

    // MARK: - Build

    func build(geometry: GardenSceneGeometry, textures: GardenTextureProvider) {
        self.geometry = geometry
        quadrantTextures = textures.cloudQuadrantTextures()
        removeAllChildren()
        guard !quadrantTextures.isEmpty else { return }

        for quadrant in 0..<4 {
            var placedMapPositions: [CGPoint] = []
            var attempts = 0
            while placedMapPositions.count < Config.clustersPerQuadrant && attempts < 60 {
                attempts += 1
                let bounds = quadrantMapBounds(quadrant, geometry: geometry)
                let candidate = CGPoint(
                    x: CGFloat.random(in: bounds.x),
                    y: CGFloat.random(in: bounds.y)
                )
                let tooClose = placedMapPositions.contains { existing in
                    hypot(candidate.x - existing.x, candidate.y - existing.y) < GardenMapConfig.minClusterSpacing
                }
                if tooClose { continue }
                placedMapPositions.append(candidate)
                spawnCluster(atMapPosition: candidate, quadrant: quadrant)
            }
        }
    }

    // MARK: - Quadrants (map space, y-down; index 0=TL 1=TR 2=BL 3=BR)

    private func quadrantMapBounds(
        _ index: Int,
        geometry: GardenSceneGeometry
    ) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let halfW = geometry.mapWidth / 2
        let halfH = geometry.mapHeight / 2
        switch index {
        case 0: return (0...halfW, 0...halfH)
        case 1: return (halfW...geometry.mapWidth, 0...halfH)
        case 2: return (0...halfW, halfH...geometry.mapHeight)
        default: return (halfW...geometry.mapWidth, halfH...geometry.mapHeight)
        }
    }

    // MARK: - Cluster lifecycle

    private func spawnCluster(atMapPosition mapPosition: CGPoint, quadrant: Int) {
        guard let geometry else { return }
        let wrapper = ClusterWrapper()
        wrapper.quadrantIndex = quadrant
        wrapper.position = geometry.scenePoint(fromMap: mapPosition)
        addChild(wrapper)

        addPieces(to: wrapper)
        fadeInAndDrift(wrapper)
    }

    private func addPieces(to wrapper: ClusterWrapper) {
        wrapper.removeAllChildren()
        let body = SKNode()
        body.alpha = 0 // fade-in target alpha is 1; per-piece alphas carry the 0.4–0.8 variation
        wrapper.addChild(body)

        let pieceCount = Int.random(in: Config.piecesPerCluster)
        for pieceIndex in 0..<pieceCount {
            // Fan pieces around the center — same layout math as the legacy
            // cluster factory, with the y offset flipped into scene space.
            let angle = (CGFloat(pieceIndex) / CGFloat(max(pieceCount, 1))) * .pi * 2
                + CGFloat.random(in: -0.35...0.35)
            let radius = CGFloat.random(in: 80...190)
            let xOffset = cos(angle) * radius + CGFloat.random(in: -20...20)
            let yOffsetMap = sin(angle) * radius * 0.6 + CGFloat.random(in: -14...14)

            guard let texture = quadrantTextures.randomElement() else { continue }
            let scale = CGFloat.random(in: 0.6...1.2)
            let sprite = SKSpriteNode(texture: texture)
            sprite.size = CGSize(
                width: texture.size().width * scale * GardenMapConfig.cloudAssetScaleMultiplier,
                height: texture.size().height * scale * GardenMapConfig.cloudAssetScaleMultiplier
            )
            sprite.alpha = CGFloat.random(in: 0.4...0.8)
            sprite.position = CGPoint(x: xOffset, y: -yOffsetMap)
            body.addChild(sprite)
        }
    }

    private func fadeInAndDrift(_ wrapper: ClusterWrapper) {
        guard let geometry else { return }
        wrapper.children.first?.run(.fadeAlpha(to: 1.0, duration: Config.fadeInDuration))

        let mapX = geometry.mapPoint(fromScene: wrapper.position).x
        let speed = CGFloat.random(in: Config.speedRange)
        // Legacy vertical drift: y += sin(direction) × driftOffset × 0.1 (map
        // space, y-down) — a constant slope per cluster, so a single moveBy.
        let slope = sin(CGFloat.random(in: Config.directionRange)) * 0.1

        let travelX = (geometry.mapWidth + Config.despawnMargin) - mapX
        guard travelX > 0, speed > 0 else {
            respawn(wrapper)
            return
        }
        let drift = SKAction.move(
            by: CGVector(dx: travelX, dy: -slope * travelX),
            duration: TimeInterval(travelX / speed)
        )
        wrapper.run(.sequence([drift, .run { [weak self, weak wrapper] in
            guard let self, let wrapper else { return }
            self.respawn(wrapper)
        }]))
    }

    private func respawn(_ wrapper: ClusterWrapper) {
        guard let geometry else { return }
        let bounds = quadrantMapBounds(wrapper.quadrantIndex, geometry: geometry)
        let mapPosition = CGPoint(
            x: CGFloat.random(in: Config.respawnXRange),
            y: CGFloat.random(in: bounds.y)
        )
        wrapper.position = geometry.scenePoint(fromMap: mapPosition)
        addPieces(to: wrapper)
        fadeInAndDrift(wrapper)
    }

    // MARK: - Viewport edge fade (called from GardenScene.update)

    func updateEdgeFade(camera: GardenCamera, viewSize: CGSize) {
        guard let geometry, viewSize.width > 0, viewSize.height > 0 else { return }
        // Legacy: fade begins at the viewport edge over 200×zoom screen px,
        // which is 200 map units — constant in map space at every zoom.
        let fadeScreenMargin = Config.edgeFadeMapDistance * camera.zoomScale
        guard fadeScreenMargin > 0 else { return }

        for case let wrapper as ClusterWrapper in children {
            let mapPoint = geometry.mapPoint(fromScene: wrapper.position)
            let screen = camera.viewPoint(atMapPoint: mapPoint)

            let outLeft = max(0, -screen.x)
            let outRight = max(0, screen.x - viewSize.width)
            let outTop = max(0, -screen.y)
            let outBottom = max(0, screen.y - viewSize.height)
            let maxOutside = max(outLeft, outRight, outTop, outBottom)

            wrapper.alpha = maxOutside > 0
                ? max(0.0, 1.0 - maxOutside / fadeScreenMargin)
                : 1.0
        }
    }
}

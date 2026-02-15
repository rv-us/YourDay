//
//  OceanVideoBackgroundView.swift
//  YourDay
//
//  Created on 2/14/25.
//

import SwiftUI
import UIKit

// MARK: - Map Configuration

// Helper functions for dynamic asset selection
struct GardenAssetHelper {
    static let winterBackdropImage = "water_winter_back_drop (1)"
    static let icebergImage = "iceburg"

    /// Determines if it's currently day or night (6 AM - 8 PM = day)
    static func isDayTime() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 6 && hour < 20
    }
    
    /// Gets the current season based on month
    static func currentSeason() -> String? {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 3...5: return "spring"
        case 6...8: return "summer"
        case 9...11: return "fall"
        case 12, 1, 2: return "winter"
        default: return nil
        }
    }

    static func isWinterDaytime() -> Bool {
        return isDayTime() && currentSeason() == "winter"
    }
    
    /// Gets the backdrop image name based on time of day
    static func backdropImageName() -> String {
        if isWinterDaytime(), UIImage(named: winterBackdropImage) != nil {
            return winterBackdropImage
        }
        return isDayTime() ? "water_back_drop" : "water_back_drop_night"
    }
    
    /// Gets the clouds image name based on time of day
    static func cloudsImageName() -> String {
        return isDayTime() ? "clouds" : "clouds_night"
    }
    
    /// Gets the island image name based on season, with fallback to summer
    static func islandImageName() -> String {
        guard let season = currentSeason() else { return "summer_main_island" }
        
        switch season {
        case "spring": return "sprint_main_island"
        case "summer": return "summer_main_island"
        case "fall": return "fall_main_island"
        case "winter": return "winter_main_island"
        default: return "summer_main_island"
        }
    }
}

struct GardenMapConfig {
    static let mapColumns = 30
    static let mapRows = 30
    static let baseMapBackdropImage = "water_back_drop"
    static let backdropScale: CGFloat = 2.0
    static let icebergAssetScaleMultiplier: CGFloat = 1.8
    static let cloudAssetScaleMultiplier: CGFloat = 3.0
    static let icebergCount = 18
    static let icebergMinSpacing: CGFloat = 180
    
    // Cloud rules: cluster count scales with tiles per quadrant (~1 per 125 tiles)
    static let tilesPerCluster = 4
    static var clustersPerQuadrant: Int {
        let tilesPerQuadrant = (mapColumns / 2) * (mapRows / 2)
        return max(1, tilesPerQuadrant / tilesPerCluster)
    }
    static var totalClusters: Int { clustersPerQuadrant * 12 }
    static let minPiecesPerCluster = 4
    static let maxPiecesPerCluster = 8
    static let minClusterSpacing: CGFloat = 150
    
    static func tileSize() -> CGSize? {
        // Keep map-space geometry stable at 1x using the base backdrop tile size.
        // Seasonal/day-night backdrops can change visuals, but not map/island scaling math.
        if let baseImage = UIImage(named: baseMapBackdropImage) {
            return baseImage.size
        }

        // Fallback if base asset is unavailable.
        let activeBackdropName = GardenAssetHelper.backdropImageName()
        return UIImage(named: activeBackdropName)?.size
    }
    
    static func mapDimensions() -> (width: CGFloat, height: CGFloat)? {
        guard let tileSize = tileSize() else { return nil }
        return (
            width: CGFloat(mapColumns) * tileSize.width,
            height: CGFloat(mapRows) * tileSize.height
        )
    }
    
    // Calculate minimum zoom scale to fit entire map on screen
    static func minimumZoomScale(for screenSize: CGSize, padding: CGFloat = 20) -> CGFloat? {
        guard let dims = mapDimensions() else { return nil }
        
        // Calculate scale needed to fit map width and height on screen
        let scaleX = (screenSize.width - padding * 2) / dims.width
        let scaleY = (screenSize.height - padding * 2) / dims.height
        
        // Use the smaller scale to ensure entire map fits
        return min(scaleX, scaleY)
    }
    
}

// MARK: - Cloud Image Splitter

class CloudImageSplitter {
    static func splitCloudsImage(_ image: UIImage) -> [UIImage] {
        guard let cgImage = image.cgImage else { return [] }
        
        let width = cgImage.width
        let height = cgImage.height
        let halfWidth = width / 2
        let halfHeight = height / 2
        
        let rects = [
            CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight),
            CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight),
            CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight),
            CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight)
        ]
        
        return rects.compactMap { rect in
            cgImage.cropping(to: rect).map {
                UIImage(cgImage: $0, scale: image.scale, orientation: image.imageOrientation)
            }
        }
    }
}

// MARK: - Cloud Models

struct CloudPiece: Identifiable {
    let id = UUID()
    let image: UIImage
    var offset: CGPoint
    var scale: CGFloat
    var opacity: Double
}

struct CloudCluster: Identifiable {
    let id = UUID()
    var position: CGPoint
    var cloudPieces: [CloudPiece]
    var speed: CGFloat
    var direction: CGFloat
    var driftOffset: CGFloat = 0
    var quadrantIndex: Int = 0  // 0=TL, 1=TR, 2=BL, 3=BR
    var spawnTime: Date = Date()  // Track when cluster was created for fade-in
}

struct IcebergPiece: Identifiable {
    let id = UUID()
    let image: UIImage
    var position: CGPoint
    var scale: CGFloat
    var opacity: Double
}

// MARK: - Main Background View

struct OceanVideoBackgroundView: View {
    var zoomScale: CGFloat = 1.0
    var panOffset: CGSize = .zero
    
    @State private var cloudClusters: [CloudCluster] = []
    @State private var cloudQuadrants: [UIImage] = []
    @State private var icebergPieces: [IcebergPiece] = []
    @State private var tileImage: UIImage?
    @State private var tileSize: CGSize = .zero
    @State private var mapWidth: CGFloat = 0
    @State private var mapHeight: CGFloat = 0
    @State private var isReady = false
    
    // Single shared timer for all cloud animation at 30fps
    private let cloudTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            if isReady, let tileImage = tileImage {
                ZStack {
                    // Viewport-sized Canvas — only draws visible tiles
                    Canvas { context, size in
                        let resolvedImage = context.resolve(Image(uiImage: tileImage))

                        guard tileSize.width > 0, tileSize.height > 0, zoomScale > 0 else { return }

                        // Calculate which map region is visible in the viewport
                        let viewW = size.width
                        let viewH = size.height

                        // Map coordinate at viewport center
                        let mapCenterX = (viewW / 2 - panOffset.width) / zoomScale
                        let mapCenterY = (viewH / 2 - panOffset.height) / zoomScale

                        // Visible map extent
                        let visibleW = viewW / zoomScale
                        let visibleH = viewH / zoomScale

                        // Tile range to draw (with 1-tile buffer)
                        let firstCol = max(0, Int((mapCenterX - visibleW / 2) / tileSize.width) - 1)
                        let lastCol = min(GardenMapConfig.mapColumns - 1, Int((mapCenterX + visibleW / 2) / tileSize.width) + 1)
                        let firstRow = max(0, Int((mapCenterY - visibleH / 2) / tileSize.height) - 1)
                        let lastRow = min(GardenMapConfig.mapRows - 1, Int((mapCenterY + visibleH / 2) / tileSize.height) + 1)

                        guard firstCol <= lastCol, firstRow <= lastRow else { return }

                        for row in firstRow...lastRow {
                            for col in firstCol...lastCol {
                                // Map-space position of this tile
                                let mapX = CGFloat(col) * tileSize.width
                                let mapY = CGFloat(row) * tileSize.height

                                // Convert to screen-space
                                let screenX = mapX * zoomScale + panOffset.width
                                let screenY = mapY * zoomScale + panOffset.height
                                // Apply backdrop scale only when rendering (2x), keeping map dimensions at 1x for islands
                                let screenW = tileSize.width * zoomScale * GardenMapConfig.backdropScale + 0.5  // 0.5px overlap to prevent seams
                                let screenH = tileSize.height * zoomScale * GardenMapConfig.backdropScale + 0.5

                                let rect = CGRect(x: screenX, y: screenY, width: screenW, height: screenH)
                                context.draw(resolvedImage, in: rect)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .zIndex(0)

                    // Static iceberg layer (winter daytime only), above backdrop and below clouds
                    ForEach(icebergPieces) { piece in
                        IcebergPieceView(piece: piece, zoomScale: zoomScale, panOffset: panOffset, viewportSize: geometry.size)
                            .zIndex(0.5)
                    }

                    // Cloud clusters with viewport transforms
                    ForEach(cloudClusters) { cluster in
                        CloudClusterView(cluster: cluster, zoomScale: zoomScale, panOffset: panOffset, viewportSize: geometry.size)
                            .zIndex(1)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            } else {
                Color.teal
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            initializeMap()
        }
        .onReceive(cloudTimer) { _ in
            updateClouds()
        }
    }
    
    // MARK: - Initialization
    
    private func initializeMap() {
        guard let ts = GardenMapConfig.tileSize(),
              let dims = GardenMapConfig.mapDimensions() else { return }

        tileSize = ts
        mapWidth = dims.width
        mapHeight = dims.height
        tileImage = UIImage(named: GardenAssetHelper.backdropImageName())

        // Split clouds image into quadrants
        if cloudQuadrants.isEmpty, let cloudsImage = UIImage(named: GardenAssetHelper.cloudsImageName()) {
            cloudQuadrants = CloudImageSplitter.splitCloudsImage(cloudsImage)
            print("🌥️ Clouds loaded: \(cloudQuadrants.count) quadrants")
        } else {
            print("⚠️ Failed to load clouds image")
        }

        // Generate initial cloud clusters
        if cloudClusters.isEmpty && !cloudQuadrants.isEmpty {
            cloudClusters = generateInitialClusters()
            print("☁️ Generated \(cloudClusters.count) cloud clusters")
        }

        if GardenAssetHelper.isWinterDaytime() {
            let icebergImages = loadIcebergImages()
            icebergPieces = generateIcebergPieces(from: icebergImages)
        } else {
            icebergPieces = []
        }

        isReady = true
    }
    
    // MARK: - Quadrant helpers

    private func quadrantBounds() -> [(xRange: ClosedRange<CGFloat>, yRange: ClosedRange<CGFloat>)] {
        let halfW = mapWidth / 2
        let halfH = mapHeight / 2
        return [
            (0...halfW,        0...halfH),        // 0: Top-Left
            (halfW...mapWidth,  0...halfH),        // 1: Top-Right
            (0...halfW,        halfH...mapHeight), // 2: Bottom-Left
            (halfW...mapWidth,  halfH...mapHeight)  // 3: Bottom-Right
        ]
    }

    private func clustersInQuadrant(_ index: Int) -> Int {
        cloudClusters.filter { $0.quadrantIndex == index }.count
    }

    // MARK: - Iceberg Layer (static)

    private func loadIcebergImages() -> [UIImage] {
        guard let icebergImage = UIImage(named: GardenAssetHelper.icebergImage) else {
            return []
        }

        let splitImages = CloudImageSplitter.splitCloudsImage(icebergImage)
        return splitImages.isEmpty ? [icebergImage] : splitImages
    }

    private func generateIcebergPieces(from images: [UIImage]) -> [IcebergPiece] {
        guard !images.isEmpty, mapWidth > 0, mapHeight > 0 else { return [] }

        var pieces: [IcebergPiece] = []
        let maxAttempts = GardenMapConfig.icebergCount * 20
        var attempts = 0

        while pieces.count < GardenMapConfig.icebergCount, attempts < maxAttempts {
            attempts += 1

            let position = CGPoint(
                x: CGFloat.random(in: 0...mapWidth),
                y: CGFloat.random(in: (mapHeight * 0.08)...(mapHeight * 0.72))
            )

            let tooClose = pieces.contains { existing in
                hypot(position.x - existing.position.x, position.y - existing.position.y) < GardenMapConfig.icebergMinSpacing
            }

            if tooClose {
                continue
            }

            pieces.append(
                IcebergPiece(
                    image: images.randomElement() ?? images[0],
                    position: position,
                    scale: CGFloat.random(in: 0.5...1.05),
                    opacity: Double.random(in: 0.78...0.96)
                )
            )
        }

        return pieces
    }

    // MARK: - Cloud Animation Tick (single timer drives everything)

    private func updateClouds() {
        guard isReady, !cloudClusters.isEmpty else { return }

        // Advance all clusters
        for i in cloudClusters.indices {
            cloudClusters[i].driftOffset += cloudClusters[i].speed
        }

        // Remove clusters that drifted completely off the right edge
        cloudClusters.removeAll { cluster in
            cluster.position.x + cluster.driftOffset > mapWidth + 300
        }

        // Respawn into whichever quadrants are below target count
        let target = GardenMapConfig.clustersPerQuadrant
        for qi in 0..<4 {
            var attempts = 0
            while clustersInQuadrant(qi) < target && attempts < 10 {
                attempts += 1
                if let newCluster = spawnReplacementCluster(forQuadrant: qi) {
                    cloudClusters.append(newCluster)
                }
            }
        }
    }

    // MARK: - Initial Cloud Generation (equal per quadrant)

    private func generateInitialClusters() -> [CloudCluster] {
        guard !cloudQuadrants.isEmpty else { return [] }

        let allBounds = quadrantBounds()
        var clusters: [CloudCluster] = []

        for (qi, bounds) in allBounds.enumerated() {
            var placed: [CloudCluster] = []
            var attempts = 0

            while placed.count < GardenMapConfig.clustersPerQuadrant && attempts < 60 {
                attempts += 1

                let x = CGFloat.random(in: bounds.xRange)
                let y = CGFloat.random(in: bounds.yRange)

                let tooClose = placed.contains { existing in
                    hypot(x - existing.position.x, y - existing.position.y) < GardenMapConfig.minClusterSpacing
                }

                if !tooClose {
                    placed.append(makeCluster(at: CGPoint(x: x, y: y), quadrant: qi))
                }
            }
            clusters.append(contentsOf: placed)
        }

        return clusters
    }

    // MARK: - Spawn replacement cluster into a specific quadrant

    private func spawnReplacementCluster(forQuadrant qi: Int) -> CloudCluster? {
        guard !cloudQuadrants.isEmpty else { return nil }

        let bounds = quadrantBounds()[qi]

        // Spawn just off the left edge of this quadrant's Y band so it drifts in naturally
        let x = CGFloat.random(in: -250 ... -50)
        let y = CGFloat.random(in: bounds.yRange)

        // Check spacing against existing clusters (use actual rendered X)
        let tooClose = cloudClusters.contains { existing in
            let existingX = existing.position.x + existing.driftOffset
            let existingY = existing.position.y
            return hypot(x - existingX, y - existingY) < GardenMapConfig.minClusterSpacing
        }

        return tooClose ? nil : makeCluster(at: CGPoint(x: x, y: y), quadrant: qi)
    }
    
    // MARK: - Cluster Factory
    
    private func makeCluster(at position: CGPoint, quadrant: Int = 0) -> CloudCluster {
        let pieceCount = Int.random(in: GardenMapConfig.minPiecesPerCluster...GardenMapConfig.maxPiecesPerCluster)

        guard !cloudQuadrants.isEmpty else {
            return CloudCluster(position: position, cloudPieces: [], speed: CGFloat.random(in: 0.3...0.8), direction: CGFloat.random(in: -0.3...0.3), quadrantIndex: quadrant, spawnTime: Date())
        }

        let pieces: [CloudPiece] = (0..<pieceCount).map { pieceIndex in
            // Fan pieces around the cluster center so clouds overlap less and read as larger masses.
            let angle = (CGFloat(pieceIndex) / CGFloat(max(pieceCount, 1))) * .pi * 2 + CGFloat.random(in: -0.35...0.35)
            let radius = CGFloat.random(in: 80...190)
            let xOffset = cos(angle) * radius + CGFloat.random(in: -20...20)
            let yOffset = sin(angle) * radius * 0.6 + CGFloat.random(in: -14...14)

            return CloudPiece(
                image: cloudQuadrants.randomElement()!,
                offset: CGPoint(
                    x: xOffset,
                    y: yOffset
                ),
                scale: CGFloat.random(in: 0.6...1.2),
                opacity: Double.random(in: 0.4...0.8)
            )
        }

        return CloudCluster(
            position: position,
            cloudPieces: pieces,
            speed: CGFloat.random(in: 0.3...0.8),
            direction: CGFloat.random(in: -0.3...0.3),
            quadrantIndex: quadrant,
            spawnTime: Date()
        )
    }
}

// MARK: - Iceberg Piece View (static render)

struct IcebergPieceView: View {
    let piece: IcebergPiece
    var zoomScale: CGFloat = 1.0
    var panOffset: CGSize = .zero
    var viewportSize: CGSize = .zero

    var body: some View {
        let screenX = piece.position.x * zoomScale + panOffset.width
        let screenY = piece.position.y * zoomScale + panOffset.height
        let margin: CGFloat = 300 * zoomScale
        let isVisible = screenX > -margin && screenX < viewportSize.width + margin
            && screenY > -margin && screenY < viewportSize.height + margin

        if isVisible {
            Image(uiImage: piece.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: piece.image.size.width * piece.scale * GardenMapConfig.icebergAssetScaleMultiplier * zoomScale,
                    height: piece.image.size.height * piece.scale * GardenMapConfig.icebergAssetScaleMultiplier * zoomScale
                )
                .opacity(piece.opacity)
                .position(x: screenX, y: screenY)
        }
    }
}

// MARK: - Cloud Cluster View (pure render, no timers)

struct CloudClusterView: View {
    let cluster: CloudCluster
    var zoomScale: CGFloat = 1.0
    var panOffset: CGSize = .zero
    var viewportSize: CGSize = .zero
    
    // Fade-in duration in seconds
    private let fadeInDuration: Double = 2.0

    var body: some View {
        // Map-space position of this cluster
        let mapX = cluster.position.x + cluster.driftOffset
        let mapY = cluster.position.y + sin(cluster.direction) * cluster.driftOffset * 0.1

        // Convert to screen-space
        let screenX = mapX * zoomScale + panOffset.width
        let screenY = mapY * zoomScale + panOffset.height

        // Cull clouds that are off-screen (with generous margin)
        let margin: CGFloat = 400 * zoomScale
        let fadeMargin: CGFloat = 200 * zoomScale // Start fading before the hard margin
        
        let isVisible = screenX > -margin && screenX < viewportSize.width + margin
            && screenY > -margin && screenY < viewportSize.height + margin

        if isVisible {
            // Calculate fade-out opacity based on distance from viewport edges
            let distanceFromLeft = max(0, -screenX)
            let distanceFromRight = max(0, screenX - viewportSize.width)
            let distanceFromTop = max(0, -screenY)
            let distanceFromBottom = max(0, screenY - viewportSize.height)
            
            let maxEdgeDistance = max(distanceFromLeft, distanceFromRight, distanceFromTop, distanceFromBottom)
            let edgeFadeOpacity = maxEdgeDistance > 0 ? max(0.0, 1.0 - (maxEdgeDistance / fadeMargin)) : 1.0
            
            ZStack {
                ForEach(cluster.cloudPieces) { piece in
                    Image(uiImage: piece.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: piece.image.size.width * piece.scale * GardenMapConfig.cloudAssetScaleMultiplier * zoomScale,
                            height: piece.image.size.height * piece.scale * GardenMapConfig.cloudAssetScaleMultiplier * zoomScale
                        )
                        .opacity(fadeInOpacity(for: piece.opacity) * edgeFadeOpacity)
                        .offset(
                            x: piece.offset.x * zoomScale,
                            y: piece.offset.y * zoomScale
                        )
                }
            }
            .position(x: screenX, y: screenY)
        }
    }
    
    // Calculate fade-in opacity based on spawn time - starts at 0 and fades to target
    private func fadeInOpacity(for targetOpacity: Double) -> Double {
        let elapsed = Date().timeIntervalSince(cluster.spawnTime)
        guard elapsed >= 0 else { return 0 } // Ensure we don't go negative
        let fadeProgress = min(1.0, max(0.0, elapsed / fadeInDuration))
        return targetOpacity * fadeProgress
    }
}

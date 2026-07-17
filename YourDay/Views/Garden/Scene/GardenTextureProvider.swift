//
//  GardenTextureProvider.swift
//  YourDay
//
//  Shared SKTexture cache for the garden scene. All asset names are resolved
//  through GardenAssetHelper so the day/night/season quirks (including the
//  "sprint_main_island" and "water_winter_back_drop (1)" names) stay funneled
//  through one place. SwiftUI-drawn art (empty tile, rarity placeholder) is
//  pre-rendered once with ImageRenderer instead of being rebuilt per frame.
//

import SpriteKit
import SwiftUI

@MainActor
final class GardenTextureProvider {
    private var cache: [String: SKTexture] = [:]
    private var splitCache: [String: [SKTexture]] = [:]

    // MARK: - Basic named textures

    func texture(named name: String) -> SKTexture? {
        if let cached = cache[name] { return cached }
        guard let image = UIImage(named: name) else { return nil }
        let texture = SKTexture(image: image)
        cache[name] = texture
        return texture
    }

    var backdropTexture: SKTexture? {
        texture(named: GardenAssetHelper.backdropImageName())
    }

    var islandTexture: SKTexture? {
        texture(named: GardenAssetHelper.islandImageName())
    }

    // MARK: - Split textures (clouds / icebergs share the quadrant splitter)

    func cloudQuadrantTextures() -> [SKTexture] {
        splitTextures(named: GardenAssetHelper.cloudsImageName(), fallbackToWhole: false)
    }

    func icebergTextures() -> [SKTexture] {
        splitTextures(named: GardenAssetHelper.icebergImage, fallbackToWhole: true)
    }

    private func splitTextures(named name: String, fallbackToWhole: Bool) -> [SKTexture] {
        if let cached = splitCache[name] { return cached }
        guard let image = UIImage(named: name) else { return [] }
        var pieces = CloudImageSplitter.splitCloudsImage(image)
        if pieces.isEmpty && fallbackToWhole { pieces = [image] }
        let textures = pieces.map { SKTexture(image: $0) }
        splitCache[name] = textures
        return textures
    }

    // MARK: - Pre-rendered SwiftUI art

    /// Rendering scale for SwiftUI→texture pre-renders: map-space points are
    /// only ever displayed at ≤ maxZoomScale, so rendering at
    /// maxZoom × screenScale keeps textures crisp at max zoom-in without
    /// allocating full map-space-resolution bitmaps.
    private var prerenderScale: CGFloat {
        GardenCamera.maxZoomScale * UIScreen.main.scale
    }

    private var emptyTileTextureCache: SKTexture?
    private var particleDotTextureCache: SKTexture?

    /// The soil plot art, identical for every empty tile — rendered once from
    /// the existing EmptyTileView so it stays pixel-identical to the legacy UI.
    func emptyTileTexture(tileSize: CGSize) -> SKTexture? {
        if let cached = emptyTileTextureCache { return cached }
        let renderer = ImageRenderer(content: EmptyTileView(tileSize: tileSize))
        renderer.scale = prerenderScale
        guard let image = renderer.uiImage else { return nil }
        let texture = SKTexture(image: image)
        emptyTileTextureCache = texture
        return texture
    }

    /// A tiny soft white dot that emitters tint at runtime. One cached texture
    /// supports dirt and magic particles without adding plant-specific VFX art.
    func particleDotTexture() -> SKTexture {
        if let cached = particleDotTextureCache { return cached }

        let size = CGSize(width: 12, height: 12)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let colors = [
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0.75).cgColor,
                UIColor.clear.cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.42, 1]
            ) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: size.width / 2,
                options: [.drawsAfterEndLocation]
            )
        }
        let texture = SKTexture(image: image)
        particleDotTextureCache = texture
        return texture
    }

    /// Fallback plant visual for missing assets — same placeholder branch as
    /// PlantVisualDisplayView, rendered lazily per (rarity, name).
    func placeholderTexture(assetName: String, rarity: Rarity, displayName: String, size: CGSize) -> SKTexture? {
        let key = "placeholder_\(rarity.rawValue)_\(displayName)"
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(
            content: PlantVisualDisplayView(
                assetName: assetName,
                rarity: rarity,
                displayName: displayName,
                isIcon: false
            )
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = prerenderScale
        guard let image = renderer.uiImage else { return nil }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    /// Plant stage texture: real asset if it exists, placeholder otherwise.
    func plantTexture(assetName: String, rarity: Rarity, displayName: String, tileSize: CGSize) -> SKTexture? {
        if let real = texture(named: assetName) { return real }
        return placeholderTexture(assetName: assetName, rarity: rarity, displayName: displayName, size: tileSize)
    }

    // MARK: - Environment refresh support

    /// Drops caches for time/season-dependent art so the next access reloads
    /// the correct variant. Static art (plants, growth stages) stays cached.
    func invalidateEnvironmentTextures() {
        cache[GardenAssetHelper.backdropImageName()] = nil
        for name in ["water_back_drop", "water_back_drop_night", GardenAssetHelper.winterBackdropImage] {
            cache[name] = nil
        }
        for name in ["sprint_main_island", "summer_main_island", "fall_main_island", "winter_main_island"] {
            cache[name] = nil
        }
        splitCache.removeAll()
    }
}

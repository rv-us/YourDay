//
//  GardenSceneCoordinates.swift
//  YourDay
//
//  Map-space (top-left origin, y-down — the coordinate system shared with
//  IslandGridConfig / GardenMapConfig) ↔ SpriteKit scene-space (bottom-left
//  origin, y-up) conversion, plus the camera math ported verbatim from the
//  legacy SwiftUI zoom/pan gestures in Gardenview.swift.
//

import UIKit
import SpriteKit

/// Every node placement in GardenScene must go through `scenePoint(fromMap:)`
/// so the y-axis flip lives in exactly one place.
struct GardenSceneGeometry {
    let mapWidth: CGFloat
    let mapHeight: CGFloat

    init?() {
        guard let dims = GardenMapConfig.mapDimensions() else { return nil }
        mapWidth = dims.width
        mapHeight = dims.height
    }

    func scenePoint(fromMap p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: mapHeight - p.y)
    }

    func mapPoint(fromScene p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: mapHeight - p.y)
    }
}

/// Camera state kept in the legacy `zoomScale` / `panOffset` vocabulary so the
/// focal-anchored pinch and pan clamping port character-for-character. Only
/// `apply(to:)` converts to SKCameraNode position/scale.
///
/// `panOffset` is the screen-space (UIKit, y-down) offset of the map origin,
/// exactly as in the legacy `.scaleEffect(zoomScale, anchor: .topLeading).offset(panOffset)`.
struct GardenCamera {
    var zoomScale: CGFloat = GardenCamera.minZoomScale
    var panOffset: CGSize = .zero

    // Legacy zoom limits from Gardenview.swift (max zoom-out / max zoom-in).
    static let minZoomScale: CGFloat = 0.03566673968241224
    static let maxZoomScale: CGFloat = 0.13157511832349003

    /// Map point currently under a view-space (UIKit, y-down) point.
    func mapPoint(atViewPoint v: CGPoint) -> CGPoint {
        CGPoint(
            x: (v.x - panOffset.width) / zoomScale,
            y: (v.y - panOffset.height) / zoomScale
        )
    }

    /// View-space point where a map point currently appears.
    func viewPoint(atMapPoint m: CGPoint) -> CGPoint {
        CGPoint(
            x: m.x * zoomScale + panOffset.width,
            y: m.y * zoomScale + panOffset.height
        )
    }

    /// Port of GardenView.clampedPanOffset: never reveal empty area past the
    /// map edges. Clamps against the full screen bounds because the scene view
    /// extends into the safe areas, matching the legacy behavior.
    func clamped(_ proposed: CGSize) -> CGSize {
        guard let mapDims = GardenMapConfig.mapDimensions() else { return proposed }

        let screenSize = UIScreen.main.bounds.size
        guard screenSize.width > 0, screenSize.height > 0 else { return proposed }

        let scaledW = mapDims.width * zoomScale
        let scaledH = mapDims.height * zoomScale

        let clampedWidth: CGFloat
        let clampedHeight: CGFloat

        if scaledW <= screenSize.width {
            clampedWidth = (screenSize.width - scaledW) / 2
        } else {
            let minX = screenSize.width - scaledW // negative
            clampedWidth = max(minX, min(0, proposed.width))
        }

        if scaledH <= screenSize.height {
            clampedHeight = (screenSize.height - scaledH) / 2
        } else {
            let minY = screenSize.height - scaledH
            clampedHeight = max(minY, min(0, proposed.height))
        }

        return CGSize(width: clampedWidth, height: clampedHeight)
    }

    mutating func setPan(_ proposed: CGSize) {
        panOffset = clamped(proposed)
    }

    /// Port of the legacy MagnifyGesture handler: zoom anchored so a chosen
    /// map point stays pinned under a view point. The legacy code pinned the
    /// map point under the gesture's start location; the scene pins the map
    /// point captured at pinch-begin under the live centroid, which is the
    /// same formula and additionally lets a two-finger drag pan while zooming.
    mutating func zoom(to scale: CGFloat, anchoringMapPoint anchor: CGPoint, atViewPoint focal: CGPoint) {
        zoomScale = max(Self.minZoomScale, min(Self.maxZoomScale, scale))
        panOffset = clamped(CGSize(
            width: focal.x - anchor.x * zoomScale,
            height: focal.y - anchor.y * zoomScale
        ))
    }

    /// Converts zoomScale/panOffset into SKCameraNode position + scale.
    /// The camera looks at whatever map point sits at the viewport center.
    func apply(to camera: SKCameraNode, geometry: GardenSceneGeometry, viewSize: CGSize) {
        guard zoomScale > 0, viewSize.width > 0, viewSize.height > 0 else { return }
        let mapCenter = mapPoint(atViewPoint: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        camera.position = geometry.scenePoint(fromMap: mapCenter)
        camera.setScale(1 / zoomScale)
    }
}

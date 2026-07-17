//
//  GardenScene.swift
//  YourDay
//
//  SpriteKit renderer for the garden world (ocean, clouds, island, plots,
//  plants). Pure renderer + input translator: game logic, SwiftData, and
//  Firebase all stay in GardenView, which pushes GardenSnapshot in through
//  GardenSceneBridge and receives GardenSceneEvent back.
//

import SpriteKit
import UIKit

final class GardenScene: SKScene {
    /// Migration flag: when false, GardenView renders the legacy SwiftUI path.
    /// Removed (along with the legacy path) once the SpriteKit port has parity.
    static let useSpriteKitGarden = true

    weak var bridge: GardenSceneBridge?

    enum ZPos {
        static let ocean: CGFloat = 0      // OceanBackgroundNode internal: ocean 0, icebergs 10
        static let clouds: CGFloat = 15    // parity: clouds render UNDER the island
        static let island: CGFloat = 20
        static let tiles: CGFloat = 30
        static let wind: CGFloat = 39
        static let plants: CGFloat = 40
        static let draggedPlant: CGFloat = 55
        static let feedback: CGFloat = 60
    }

    private(set) var geometry: GardenSceneGeometry?
    let textures = GardenTextureProvider()

    private let worldNode = SKNode()
    private let oceanBackground = OceanBackgroundNode()
    private let cloudLayer = CloudLayerNode()
    private var islandSprite: SKSpriteNode?
    let tileLayer = SKNode()
    private let windLayer = SKNode()
    let plantLayer = SKNode()
    let feedbackLayer = SKNode()
    private let cameraNode = SKCameraNode()

    var gardenCamera = GardenCamera()

    private var isWorldBuilt = false
    private(set) var currentSnapshot: GardenSnapshot?

    private var plantNodes: [UUID: PlantNode] = [:]
    private var tileNodes: [GridPosition: PlotTileNode] = [:]
    private var pendingPlantingAnimationIDs = Set<UUID>()
    private var nextWindGustTime: TimeInterval?
    private var windGustIndex = 0

    // Environment (day/night/season) the world was last built for.
    private var currentBackdropName = ""
    private var currentIslandName = ""

    // Gesture state
    private weak var recognizerHostView: SKView?
    private var userHasMovedCamera = false
    private var isPinching = false
    private var pinchStartZoom: CGFloat = GardenCamera.minZoomScale
    private var pinchAnchorMapPoint: CGPoint = .zero
    /// When the last pinch ended. Pan input is ignored for a short grace
    /// window afterward so the trailing finger's peel-off movement (fingers
    /// never lift simultaneously) can't smear the camera at zoom end.
    private var lastPinchEndTime: CFTimeInterval = 0
    private let pinchEndPanGrace: CFTimeInterval = 0.12

    // Plant drag state (long-press that moved past the threshold)
    private struct DragState {
        let plantID: UUID
        let node: PlantNode
        let startScenePosition: CGPoint
        let startViewPoint: CGPoint
        var isDragging = false
    }
    private var dragState: DragState?
    private var swapTargetID: UUID?
    private var isPlantDragging: Bool { dragState?.isDragging == true }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        // Teal fallback shown when the backdrop asset is missing (legacy parity).
        backgroundColor = UIColor(red: 0.0, green: 0.5, blue: 0.5, alpha: 1.0)

        buildWorldIfNeeded()
        installGestureRecognizers(on: view)
        centerOnIslandIfUntouched(viewSize: view.bounds.size)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard isWorldBuilt else { return }
        // .resizeFill resizes the scene to the SKView; until the user moves the
        // camera, keep the initial island-centered framing pinned to the final
        // view size (the first layout pass can arrive with a temporary size).
        centerOnIslandIfUntouched(viewSize: size)
        applyCamera()
    }

    // MARK: - World construction

    private func buildWorldIfNeeded() {
        guard !isWorldBuilt else { return }
        // No backdrop asset → keep the teal fallback and skip the world build,
        // matching the legacy Color.teal branch.
        guard let geo = GardenSceneGeometry() else { return }
        geometry = geo
        isWorldBuilt = true

        addChild(worldNode)
        camera = cameraNode
        addChild(cameraNode)

        currentBackdropName = GardenAssetHelper.backdropImageName()
        currentIslandName = GardenAssetHelper.islandImageName()

        oceanBackground.zPosition = ZPos.ocean
        oceanBackground.build(geometry: geo, textures: textures)
        worldNode.addChild(oceanBackground)

        cloudLayer.zPosition = ZPos.clouds
        cloudLayer.build(geometry: geo, textures: textures)
        worldNode.addChild(cloudLayer)

        if let islandTexture = textures.islandTexture {
            let sprite = SKSpriteNode(texture: islandTexture)
            sprite.size = IslandGridConfig.islandDisplaySize
            sprite.position = geo.scenePoint(fromMap: IslandGridConfig.islandCenterInMapSpace())
            sprite.zPosition = ZPos.island
            worldNode.addChild(sprite)
            islandSprite = sprite
        }

        tileLayer.zPosition = ZPos.tiles
        windLayer.zPosition = ZPos.wind
        plantLayer.zPosition = ZPos.plants
        feedbackLayer.zPosition = ZPos.feedback
        worldNode.addChild(tileLayer)
        worldNode.addChild(windLayer)
        worldNode.addChild(plantLayer)
        worldNode.addChild(feedbackLayer)

        if let pending = currentSnapshot {
            applySnapshotToWorld(pending)
        }
    }

    // MARK: - Camera

    private func centerOnIslandIfUntouched(viewSize: CGSize) {
        guard isWorldBuilt, !userHasMovedCamera,
              viewSize.width > 0, viewSize.height > 0 else { return }

        // Legacy onAppear framing: start fully zoomed out, island centered.
        gardenCamera.zoomScale = GardenCamera.minZoomScale
        gardenCamera.panOffset = IslandGridConfig.panOffsetToCenterIsland(
            for: viewSize,
            zoomScale: gardenCamera.zoomScale
        )
        applyCamera()
    }

    func applyCamera() {
        guard let geo = geometry else { return }
        gardenCamera.apply(to: cameraNode, geometry: geo, viewSize: size)
    }

    // MARK: - Gestures

    private func installGestureRecognizers(on view: SKView) {
        // Re-install if SwiftUI handed us a fresh SKView (the old view took
        // its recognizers with it).
        guard recognizerHostView !== view else { return }
        recognizerHostView = view

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)

        // Stationary long-press = water/sell dialog; long-press that moves
        // past ~12pt = drag-to-swap. allowableMovement stays small so a swipe
        // never accidentally arms a drag; movement after recognition is fine.
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.allowableMovement = 20
        longPress.delegate = self
        view.addGestureRecognizer(longPress)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let view = recognizer.view else { return }
        switch recognizer.state {
        case .began:
            isPinching = true
            userHasMovedCamera = true
            pinchStartZoom = gardenCamera.zoomScale
            pinchAnchorMapPoint = gardenCamera.mapPoint(atViewPoint: recognizer.location(in: view))
        case .changed:
            // Frames delivered while a finger is lifting can report a
            // collapsed centroid (single touch) — never move the camera on
            // them or the anchor point teleports.
            guard recognizer.numberOfTouches >= 2 else { return }
            gardenCamera.zoom(
                to: pinchStartZoom * recognizer.scale,
                anchoringMapPoint: pinchAnchorMapPoint,
                atViewPoint: recognizer.location(in: view)
            )
            applyCamera()
        case .ended, .cancelled, .failed:
            isPinching = false
            lastPinchEndTime = CACurrentMediaTime()
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view else { return }
        switch recognizer.state {
        case .began:
            userHasMovedCamera = true
            recognizer.setTranslation(.zero, in: view)
        case .changed:
            // While pinching or dragging a plant, other handlers own the input.
            // Translation is zeroed unconditionally so ignored movement never
            // accumulates into a jump once panning resumes.
            let translation = recognizer.translation(in: view)
            recognizer.setTranslation(.zero, in: view)
            guard !isPinching, !isPlantDragging,
                  CACurrentMediaTime() - lastPinchEndTime > pinchEndPanGrace else { return }
            gardenCamera.setPan(CGSize(
                width: gardenCamera.panOffset.width + translation.x,
                height: gardenCamera.panOffset.height + translation.y
            ))
            applyCamera()
        default:
            break
        }
    }

    // MARK: - World hit-testing (grid math, not node frames — deterministic)

    private func plantID(atViewPoint point: CGPoint) -> UUID? {
        let mapPoint = gardenCamera.mapPoint(atViewPoint: point)
        let tileSize = IslandGridConfig.displayTileSize
        for (id, node) in plantNodes {
            let center = IslandGridConfig.mapPosition(for: node.model.position)
            if abs(mapPoint.x - center.x) <= tileSize.width / 2,
               abs(mapPoint.y - center.y) <= tileSize.height / 2 {
                return id
            }
        }
        return nil
    }

    private func emptyTilePosition(atViewPoint point: CGPoint) -> GridPosition? {
        let mapPoint = gardenCamera.mapPoint(atViewPoint: point)
        let tileSize = IslandGridConfig.displayTileSize
        for (position, _) in tileNodes {
            let center = IslandGridConfig.mapPosition(for: position)
            if abs(mapPoint.x - center.x) <= tileSize.width / 2,
               abs(mapPoint.y - center.y) <= tileSize.height / 2 {
                return position
            }
        }
        return nil
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let view = recognizer.view else { return }
        let point = recognizer.location(in: view)
        if let id = plantID(atViewPoint: point) {
            bridge?.emit(.tappedPlant(id: id))
        } else if let position = emptyTilePosition(atViewPoint: point) {
            bridge?.emit(.tappedEmptyTile(position))
        }
    }

    // MARK: - Long-press: stationary → dialog, moved → drag-to-swap

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let point = recognizer.location(in: view)

        switch recognizer.state {
        case .began:
            guard let id = plantID(atViewPoint: point), let node = plantNodes[id] else { return }
            dragState = DragState(
                plantID: id,
                node: node,
                startScenePosition: node.position,
                startViewPoint: point
            )
        case .changed:
            guard var state = dragState else { return }
            if !state.isDragging {
                let moved = hypot(point.x - state.startViewPoint.x, point.y - state.startViewPoint.y)
                guard moved > 12 else { return }
                guard currentSnapshot?.dragEnabled == true else { return }
                state.isDragging = true
                dragState = state
                state.node.zPosition = ZPos.draggedPlant - ZPos.plants // plantLayer adds ZPos.plants
                state.node.setLifted(true)
            }
            state.node.position = convertPoint(fromView: point)
            updateSwapTarget(draggedID: state.plantID, viewPoint: point)
        case .ended:
            finishLongPress(cancelled: false)
        case .cancelled, .failed:
            finishLongPress(cancelled: true)
        default:
            break
        }
    }

    private func updateSwapTarget(draggedID: UUID, viewPoint: CGPoint) {
        let newTargetID: UUID? = {
            guard let id = plantID(atViewPoint: viewPoint), id != draggedID else { return nil }
            return id
        }()
        guard newTargetID != swapTargetID else { return }
        if let old = swapTargetID { plantNodes[old]?.setSwapTargetHighlight(false) }
        if let new = newTargetID { plantNodes[new]?.setSwapTargetHighlight(true) }
        swapTargetID = newTargetID
    }

    private func finishLongPress(cancelled: Bool) {
        guard let state = dragState else { return }
        let targetID = swapTargetID
        if let old = targetID { plantNodes[old]?.setSwapTargetHighlight(false) }
        swapTargetID = nil
        dragState = nil

        if state.isDragging {
            state.node.setLifted(false)
            state.node.zPosition = 0
            if !cancelled, let targetID, targetID != state.plantID,
               let targetNode = plantNodes[targetID] {
                // Optimistic settle onto the target tile; the snapshot diff
                // confirms both positions after SwiftUI performs the swap.
                if let targetScenePos = scenePosition(for: targetNode.model.position) {
                    state.node.run(.move(to: targetScenePos, duration: 0.15))
                }
                bridge?.emit(.swapRequested(draggedID: state.plantID, targetID: targetID))
            } else {
                state.node.run(.move(to: state.startScenePosition, duration: 0.2))
            }
        } else if !cancelled {
            bridge?.emit(.longPressedPlant(id: state.plantID))
        }
    }

    // MARK: - Per-frame work

    override func update(_ currentTime: TimeInterval) {
        guard isWorldBuilt else { return }
        cloudLayer.updateEdgeFade(camera: gardenCamera, viewSize: size)
        updateWind(at: currentTime)
    }

    private func updateWind(at currentTime: TimeInterval) {
        guard let snapshot = currentSnapshot, !snapshot.reduceMotion else {
            nextWindGustTime = nil
            windLayer.removeAllChildren()
            return
        }

        guard let scheduledTime = nextWindGustTime else {
            // Let the player take in the garden before the first gust arrives.
            nextWindGustTime = currentTime + 2.2
            return
        }
        guard currentTime >= scheduledTime else { return }

        playWindGust(index: windGustIndex)
        nextWindGustTime = currentTime + GardenWindProfile.intervalAfterGust(windGustIndex)
        windGustIndex += 1
    }

    private func playWindGust(index: Int) {
        guard let geometry, currentSnapshot?.reduceMotion == false else { return }

        let islandSize = IslandGridConfig.islandDisplaySize
        let islandCenter = geometry.scenePoint(fromMap: IslandGridConfig.islandCenterInMapSpace())
        let islandFrame = CGRect(
            x: islandCenter.x - islandSize.width / 2,
            y: islandCenter.y - islandSize.height / 2,
            width: islandSize.width,
            height: islandSize.height
        )
        let direction = GardenWindProfile.direction(forGust: index)
        let gustStrength = GardenWindProfile.strength(forGust: index)
        let travelPadding = islandFrame.width * GardenWindProfile.horizontalOverscanFraction
        let travelMinimumX = islandFrame.minX - travelPadding
        let travelMaximumX = islandFrame.maxX + travelPadding
        let tileSize = IslandGridConfig.displayTileSize

        GardenWindVFXFactory.playTravelingGust(
            on: windLayer,
            islandFrame: islandFrame,
            direction: direction,
            tileSize: tileSize
        )

        for (plantID, node) in plantNodes {
            let progress = GardenWindProfile.travelProgress(
                x: node.position.x,
                minimumX: travelMinimumX,
                maximumX: travelMaximumX,
                direction: direction
            )
            let delay = GardenWindProfile.travelDuration * TimeInterval(progress)
            node.playWindRustle(
                direction: direction,
                gustStrength: gustStrength,
                delay: delay
            )

            if GardenWindProfile.liftsGrass(plantID: plantID, gustIndex: index) {
                GardenWindVFXFactory.playGrassLift(
                    on: windLayer,
                    at: node.position,
                    tileSize: tileSize,
                    direction: direction,
                    delay: delay,
                    plantID: plantID,
                    gustIndex: index
                )
            }
        }
    }

    // MARK: - State sync (full diffing lands in the plants phase)

    func apply(_ snapshot: GardenSnapshot) {
        currentSnapshot = snapshot
        if snapshot.reduceMotion {
            nextWindGustTime = nil
            windLayer.removeAllChildren()
        }
        guard isWorldBuilt else { return }
        applySnapshotToWorld(snapshot)
    }

    func queuePlantingAnimation(for plantID: UUID) {
        pendingPlantingAnimationIDs.insert(plantID)
    }

    /// Scene position for a grid tile — same IslandGridConfig map math as the
    /// legacy overlay, flipped through the single scenePoint funnel.
    func scenePosition(for gridPosition: GridPosition) -> CGPoint? {
        guard let geo = geometry else { return nil }
        return geo.scenePoint(fromMap: IslandGridConfig.mapPosition(for: gridPosition))
    }

    private func applySnapshotToWorld(_ snapshot: GardenSnapshot) {
        guard geometry != nil else { return }
        let tileSize = IslandGridConfig.displayTileSize

        // Diff plants by UUID: explicitly queued user planting gets a growth
        // reveal, removals fade, swaps move, and existing nodes refresh state.
        var seenIDs = Set<UUID>()
        for model in snapshot.plants {
            seenIDs.insert(model.id)
            guard let targetPosition = scenePosition(for: model.position) else { continue }

            if let node = plantNodes[model.id] {
                if node.model.position != model.position {
                    node.run(.move(to: targetPosition, duration: 0.25))
                }
                node.update(
                    model: model,
                    mode: snapshot.mode,
                    textures: textures,
                    reduceMotion: snapshot.reduceMotion
                )
            } else {
                let shouldAnimatePlanting = pendingPlantingAnimationIDs.remove(model.id) != nil
                let node = PlantNode(
                    model: model,
                    tileSize: tileSize,
                    textures: textures,
                    reduceMotion: snapshot.reduceMotion
                )
                node.position = targetPosition
                plantLayer.addChild(node)
                plantNodes[model.id] = node

                node.update(
                    model: model,
                    mode: snapshot.mode,
                    textures: textures,
                    reduceMotion: snapshot.reduceMotion
                )
                if shouldAnimatePlanting {
                    node.playPlantingReveal(textures: textures)
                }
            }
        }
        for (id, node) in plantNodes where !seenIDs.contains(id) {
            plantNodes[id] = nil
            node.run(.sequence([
                .group([.fadeOut(withDuration: 0.25), .scale(to: 0.7, duration: 0.25)]),
                .removeFromParent()
            ]))
        }

        // Empty tiles = unlocked positions minus occupied ones.
        let unlocked = IslandGridConfig.unlockedPositions(count: snapshot.unlockedPlotCount)
        let occupied = Set(snapshot.plants.map(\.position))
        let wanted = Set(unlocked).subtracting(occupied)

        for (position, node) in tileNodes where !wanted.contains(position) {
            node.removeFromParent()
            tileNodes[position] = nil
        }
        for position in wanted where tileNodes[position] == nil {
            guard let scenePos = scenePosition(for: position) else { continue }
            let node = PlotTileNode(
                gridPosition: position,
                texture: textures.emptyTileTexture(tileSize: tileSize),
                tileSize: tileSize
            )
            node.position = scenePos
            tileLayer.addChild(node)
            tileNodes[position] = node
        }
    }

    // MARK: - Feedback labels ("+NP", "Grown!")

    func showFeedback(text: String, color: UIColor, at position: GridPosition) {
        guard let scenePos = scenePosition(for: position) else { return }
        let tileSize = IslandGridConfig.displayTileSize

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = tileSize.height * 0.18
        label.fontColor = color
        label.verticalAlignmentMode = .center

        let horizontalPadding = tileSize.width * 0.1
        let verticalPadding = tileSize.height * 0.06
        let pill = SKShapeNode(
            rectOf: CGSize(
                width: label.frame.width + horizontalPadding * 2,
                height: label.frame.height + verticalPadding * 2
            ),
            cornerRadius: tileSize.height * 0.08
        )
        pill.fillColor = UIColor(white: 0.12, alpha: 0.8)
        pill.strokeColor = .clear

        let container = SKNode()
        container.position = CGPoint(x: scenePos.x, y: scenePos.y + tileSize.height * 0.2)
        container.addChild(pill)
        container.addChild(label)
        feedbackLayer.addChild(container)

        // Legacy: float up 150 screen-ish units over 0.3s, fade over 1s after
        // a 0.2s delay. Scene-space up is +y.
        let floatUp = SKAction.moveBy(x: 0, y: tileSize.height * 0.35, duration: 0.3)
        floatUp.timingMode = .easeOut
        container.run(.sequence([
            .group([
                floatUp,
                .sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 1.0)])
            ]),
            .removeFromParent()
        ]))
    }

    // MARK: - Environment refresh (day/night boundary, season change)

    func refreshEnvironment() {
        guard isWorldBuilt, let geo = geometry else { return }

        let newBackdrop = GardenAssetHelper.backdropImageName()
        let newIsland = GardenAssetHelper.islandImageName()
        guard newBackdrop != currentBackdropName || newIsland != currentIslandName else { return }
        currentBackdropName = newBackdrop
        currentIslandName = newIsland

        textures.invalidateEnvironmentTextures()
        oceanBackground.build(geometry: geo, textures: textures) // ocean + icebergs
        cloudLayer.build(geometry: geo, textures: textures)      // day/night cloud variant
        islandSprite?.texture = textures.islandTexture

        // Plant label colors depend on day/night — re-apply refreshes them.
        if let snapshot = currentSnapshot {
            applySnapshotToWorld(snapshot)
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension GardenScene: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

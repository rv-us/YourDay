//
//  WateringSystem.swift
//  YourDay
//
//  Draggable watering can + falling water droplets for the SpriteKit garden.
//  The scene routes finger input in and calls update() once per frame; the
//  system simulates droplets under gravity, splashes them on plants and soil,
//  and reports onPlantWatered once a plant has caught enough water. Pure
//  presentation + accounting — the actual watering stays in GardenView.
//

import SpriteKit

// MARK: - Watering can

@MainActor
final class WateringCanNode: SKNode {
    private let sprite: SKSpriteNode
    private(set) var canSize: CGSize

    private enum ActionKey {
        static let tilt = "tilt"
        static let bob = "bob"
        static let pourBurst = "pourBurst"
    }

    init(texture: SKTexture?, tileSize: CGSize) {
        let box = CGSize(width: tileSize.width * 1.24, height: tileSize.height * 1.24)
        sprite = SKSpriteNode(texture: texture)
        if let texture {
            let textureSize = texture.size()
            var fitted = box
            if textureSize.width > 0, textureSize.height > 0 {
                let scale = min(box.width / textureSize.width, box.height / textureSize.height)
                fitted = CGSize(width: textureSize.width * scale, height: textureSize.height * scale)
            }
            sprite.size = fitted
        } else {
            // Missing-asset fallback: a plain blue block still functions.
            sprite.color = UIColor(red: 0.16, green: 0.55, blue: 0.9, alpha: 1)
            sprite.size = CGSize(width: box.width * 0.6, height: box.height * 0.45)
        }
        canSize = sprite.size

        super.init()
        addChild(sprite)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Spout opening (matches the Water_icon artwork's spout head) in the
    /// can's own unrotated coordinates.
    var spoutLocalOffset: CGPoint {
        CGPoint(x: canSize.width * 0.30, y: -canSize.height * 0.02)
    }

    /// Spout opening converted into `node`'s coordinate space — rotation-aware,
    /// so the pour tilt moves the emission point with the art.
    func spoutPosition(in node: SKNode) -> CGPoint {
        convert(spoutLocalOffset, to: node)
    }

    func setPouring(_ pouring: Bool) {
        removeAction(forKey: ActionKey.tilt)
        let tilt = SKAction.rotate(toAngle: pouring ? -0.34 : 0, duration: 0.16, shortestUnitArc: true)
        tilt.timingMode = .easeOut
        run(tilt, withKey: ActionKey.tilt)

        sprite.removeAction(forKey: ActionKey.bob)
        sprite.position = .zero
        if !pouring {
            let rise = SKAction.moveBy(x: 0, y: canSize.height * 0.03, duration: 0.7)
            let fall = SKAction.moveBy(x: 0, y: -canSize.height * 0.03, duration: 0.7)
            rise.timingMode = .easeInEaseOut
            fall.timingMode = .easeInEaseOut
            sprite.run(.repeatForever(.sequence([rise, fall])), withKey: ActionKey.bob)
        }
    }

    /// Keeps pouring for `duration`, then tips back upright (tap-to-shower).
    func schedulePourStop(after duration: TimeInterval, onStop: @escaping () -> Void) {
        removeAction(forKey: ActionKey.pourBurst)
        run(.sequence([.wait(forDuration: duration), .run(onStop)]), withKey: ActionKey.pourBurst)
    }

    func cancelScheduledPourStop() {
        removeAction(forKey: ActionKey.pourBurst)
    }

    func playDisappearAndRemove() {
        removeAllActions()
        run(.sequence([
            .group([.fadeOut(withDuration: 0.18), .scale(to: 0.6, duration: 0.18)]),
            .removeFromParent()
        ]))
    }
}

// MARK: - Droplet simulation

@MainActor
final class WateringSystem {

    /// Per-frame view of a placed plant the droplets can interact with.
    struct PlantTarget {
        let id: UUID
        let sceneCenter: CGPoint
        let needsWater: Bool
        let node: PlantNode
    }

    /// Droplets a plant must catch before it counts as watered — roughly half
    /// a second of pouring, so watering feels earned but never tedious.
    private static let hitsToWater = 8
    private static let maxLiveDroplets = 70

    private enum ActionKey {
        static let canFade = "canFade"
    }

    var onPlantWatered: ((UUID) -> Void)?

    private(set) var isActive = false
    private(set) var isPouring = false

    private let layer = SKNode()
    private var canNode: WateringCanNode?
    private var dropletTexture: SKTexture?
    private var tileSize: CGSize = .zero
    private var currentZoomScale: CGFloat = GardenCamera.minZoomScale

    private struct Droplet {
        let node: SKSpriteNode
        var velocity: CGVector
        let landingY: CGFloat
        let targetPlantID: UUID?
    }

    private var droplets: [Droplet] = []
    private var spawnAccumulator: Double = 0
    private var hitCounts: [UUID: Int] = [:]
    private var wateredThisSession: Set<UUID> = []
    private var targetsByID: [UUID: PlantTarget] = [:]

    // Finger-follow state
    private var followTarget: CGPoint?
    private var lastCanPosition: CGPoint = .zero
    private var canVelocity: CGVector = .zero

    // MARK: Lifecycle

    func activate(
        on worldNode: SKNode,
        at startPoint: CGPoint,
        tileSize: CGSize,
        textures: GardenTextureProvider,
        zoomScale: CGFloat
    ) {
        guard !isActive else { return }
        isActive = true
        self.tileSize = tileSize
        currentZoomScale = zoomScale
        dropletTexture = textures.particleDotTexture()

        layer.zPosition = 50 // above plants (40), below feedback (60)
        if layer.parent == nil { worldNode.addChild(layer) }

        let can = WateringCanNode(texture: textures.texture(named: "Water_icon"), tileSize: tileSize)
        can.position = startPoint
        can.zPosition = 2
        // Invisible until the finger goes down; grabCan() reveals it.
        can.alpha = 0
        layer.addChild(can)
        canNode = can
        lastCanPosition = startPoint
        followTarget = nil
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        isPouring = false
        followTarget = nil
        spawnAccumulator = 0
        hitCounts.removeAll()
        wateredThisSession.removeAll()
        targetsByID.removeAll()

        canNode?.playDisappearAndRemove()
        canNode = nil
        for droplet in droplets {
            droplet.node.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        }
        droplets.removeAll()
    }

    // MARK: Finger input

    /// Finger down / drag began: reveal the can at the finger and start pouring.
    func grabCan(at fingerPoint: CGPoint) {
        guard isActive, let can = canNode else { return }
        let target = canTarget(forFinger: fingerPoint)
        followTarget = target
        // If the can is hidden (or mostly faded out), snap it to the finger
        // before revealing so it never sails across the garden from wherever
        // the last pour ended.
        if can.alpha < 0.4 {
            can.position = target
            lastCanPosition = target
            canVelocity = .zero
            can.setScale(0.85)
        }
        can.removeAction(forKey: ActionKey.canFade)
        can.run(.group([
            .fadeIn(withDuration: 0.12),
            .scale(to: 1, duration: 0.15)
        ]), withKey: ActionKey.canFade)
        beginPour()
    }

    func moveCan(to fingerPoint: CGPoint) {
        guard isActive else { return }
        followTarget = canTarget(forFinger: fingerPoint)
    }

    func beginPour() {
        guard isActive, let can = canNode else { return }
        can.cancelScheduledPourStop()
        guard !isPouring else { return }
        isPouring = true
        can.setPouring(true)
    }

    func endPour() {
        guard isPouring else { return }
        isPouring = false
        canNode?.setPouring(false)
        followTarget = nil
        canNode?.removeAction(forKey: ActionKey.canFade)
        canNode?.run(.fadeOut(withDuration: 0.15), withKey: ActionKey.canFade)
    }

    /// Tap: show the can there and pour a short shower.
    func pourBurst(at fingerPoint: CGPoint, duration: TimeInterval = 0.9) {
        guard isActive, let can = canNode else { return }
        grabCan(at: fingerPoint)
        can.schedulePourStop(after: duration) { [weak self] in self?.endPour() }
    }

    /// Screen-point offset from the fingertip to the can's spout: the pour
    /// stream starts this far above-and-right of the finger, so neither the
    /// finger nor the artwork hides the tile being showered.
    private static let spoutScreenOffset = CGVector(dx: 60, dy: 88)

    /// Can position for a finger point, holding `spoutScreenOffset` as a
    /// *visual* distance at every zoom level. The scene camera's scale is
    /// 1/zoomScale, so one screen point spans 1/zoomScale scene units —
    /// divide by zoom to convert. Anchoring the spout (not the can's center)
    /// keeps the pour stream a fixed visual distance from the fingertip even
    /// though the artwork's on-screen size changes with zoom.
    private func canTarget(forFinger point: CGPoint) -> CGPoint {
        let sceneUnitsPerScreenPoint = 1 / max(currentZoomScale, 0.0001)
        let spout = canNode?.spoutLocalOffset ?? .zero
        return CGPoint(
            x: point.x + Self.spoutScreenOffset.dx * sceneUnitsPerScreenPoint - spout.x,
            y: point.y + Self.spoutScreenOffset.dy * sceneUnitsPerScreenPoint - spout.y
        )
    }

    // MARK: Per-frame simulation

    func update(deltaTime: TimeInterval, plantTargets: [PlantTarget], reduceMotion: Bool, zoomScale: CGFloat) {
        guard isActive, deltaTime > 0, let can = canNode else { return }
        currentZoomScale = zoomScale

        targetsByID = Dictionary(uniqueKeysWithValues: plantTargets.map { ($0.id, $0) })

        // Smooth trailing finger-follow; the can's velocity feeds droplets so
        // a sweeping pour arcs naturally instead of dropping straight down.
        if let target = followTarget {
            let blend = CGFloat(min(1, deltaTime * 14))
            can.position = CGPoint(
                x: can.position.x + (target.x - can.position.x) * blend,
                y: can.position.y + (target.y - can.position.y) * blend
            )
        }
        canVelocity = CGVector(
            dx: (can.position.x - lastCanPosition.x) / CGFloat(deltaTime),
            dy: (can.position.y - lastCanPosition.y) / CGFloat(deltaTime)
        )
        lastCanPosition = can.position

        if isPouring {
            spawnAccumulator += deltaTime * (reduceMotion ? 10 : 17)
            while spawnAccumulator >= 1 {
                spawnAccumulator -= 1
                spawnDroplet(plantTargets: plantTargets)
            }
        } else {
            spawnAccumulator = 0
        }

        integrateDroplets(deltaTime: deltaTime, reduceMotion: reduceMotion)
    }

    private func spawnDroplet(plantTargets: [PlantTarget]) {
        guard droplets.count < Self.maxLiveDroplets,
              let can = canNode,
              let texture = dropletTexture else { return }

        let spout = can.spoutPosition(in: layer)
        let spawn = CGPoint(
            x: spout.x + CGFloat.random(in: -0.05...0.05) * tileSize.width,
            y: spout.y
        )

        let node = SKSpriteNode(texture: texture)
        node.color = UIColor(red: 0.33, green: 0.68, blue: 0.95, alpha: 1)
        node.colorBlendFactor = 1
        node.alpha = 0.9
        node.size = CGSize(width: tileSize.width * 0.05, height: tileSize.width * 0.065)
        node.position = spawn
        layer.addChild(node)

        let velocity = CGVector(
            dx: canVelocity.dx * 0.22 + CGFloat.random(in: -0.05...0.05) * tileSize.width,
            dy: min(0, canVelocity.dy * 0.1) - CGFloat.random(in: 0.05...0.2) * tileSize.height
        )

        // Fall to the highest plant surface below the spout in this column,
        // or splash on open ground after ~1.5 tiles of air.
        var landingY = spawn.y - tileSize.height * 1.5
        var targetID: UUID?
        for target in plantTargets {
            guard abs(spawn.x - target.sceneCenter.x) <= tileSize.width * 0.45 else { continue }
            let surfaceY = target.sceneCenter.y + tileSize.height * 0.02
            if surfaceY < spawn.y - tileSize.height * 0.1, surfaceY > landingY {
                landingY = surfaceY
                targetID = target.id
            }
        }
        landingY += CGFloat.random(in: -0.03...0.03) * tileSize.height

        droplets.append(Droplet(node: node, velocity: velocity, landingY: landingY, targetPlantID: targetID))
    }

    private func integrateDroplets(deltaTime: TimeInterval, reduceMotion: Bool) {
        guard !droplets.isEmpty else { return }
        let dt = CGFloat(deltaTime)
        let gravity = tileSize.height * 5.4
        var survivors: [Droplet] = []
        survivors.reserveCapacity(droplets.count)

        for var droplet in droplets {
            droplet.velocity.dy -= gravity * dt
            droplet.node.position.x += droplet.velocity.dx * dt
            droplet.node.position.y += droplet.velocity.dy * dt
            // Stretch with fall speed for a nicer raindrop read.
            droplet.node.yScale = 1 + min(0.6, abs(droplet.velocity.dy) / (tileSize.height * 6))

            if droplet.node.position.y <= droplet.landingY {
                land(droplet, reduceMotion: reduceMotion)
            } else {
                survivors.append(droplet)
            }
        }
        droplets = survivors
    }

    private func land(_ droplet: Droplet, reduceMotion: Bool) {
        let impact = CGPoint(x: droplet.node.position.x, y: droplet.landingY)
        droplet.node.removeFromParent()
        playSplash(at: impact, reduceMotion: reduceMotion)

        guard let plantID = droplet.targetPlantID,
              let target = targetsByID[plantID] else { return }
        target.node.playWaterDropletHit()

        guard target.needsWater, !wateredThisSession.contains(plantID) else { return }
        let hits = (hitCounts[plantID] ?? 0) + 1
        hitCounts[plantID] = hits
        if hits >= Self.hitsToWater {
            wateredThisSession.insert(plantID)
            playWateredBurst(at: target.sceneCenter, reduceMotion: reduceMotion)
            onPlantWatered?(plantID)
        }
    }

    // MARK: Impact VFX

    private func playSplash(at point: CGPoint, reduceMotion: Bool) {
        let ripple = SKShapeNode(ellipseOf: CGSize(
            width: tileSize.width * 0.09,
            height: tileSize.width * 0.035
        ))
        ripple.position = point
        ripple.strokeColor = UIColor(red: 0.62, green: 0.85, blue: 1, alpha: 0.75)
        ripple.lineWidth = max(1, tileSize.width * 0.008)
        ripple.fillColor = .clear
        layer.addChild(ripple)
        ripple.run(.sequence([
            .group([
                .scale(to: reduceMotion ? 1.6 : 2.4, duration: 0.28),
                .fadeOut(withDuration: 0.28)
            ]),
            .removeFromParent()
        ]))

        guard !reduceMotion, let texture = dropletTexture else { return }
        for _ in 0..<2 {
            let fleck = SKSpriteNode(texture: texture)
            fleck.color = UIColor(red: 0.55, green: 0.8, blue: 1, alpha: 1)
            fleck.colorBlendFactor = 1
            fleck.size = CGSize(width: tileSize.width * 0.028, height: tileSize.width * 0.028)
            fleck.position = point
            layer.addChild(fleck)

            let driftX = CGFloat.random(in: -0.12...0.12) * tileSize.width
            let hop = SKAction.moveBy(
                x: driftX,
                y: tileSize.height * CGFloat.random(in: 0.06...0.12),
                duration: 0.12
            )
            hop.timingMode = .easeOut
            let fall = SKAction.moveBy(x: driftX * 0.4, y: -tileSize.height * 0.08, duration: 0.14)
            fall.timingMode = .easeIn
            fleck.run(.sequence([
                hop,
                .group([fall, .fadeOut(withDuration: 0.14)]),
                .removeFromParent()
            ]))
        }
    }

    private func playWateredBurst(at center: CGPoint, reduceMotion: Bool) {
        let ring = SKShapeNode(circleOfRadius: tileSize.width * 0.2)
        ring.position = CGPoint(x: center.x, y: center.y + tileSize.height * 0.08)
        ring.strokeColor = UIColor(red: 0.45, green: 0.78, blue: 1, alpha: 0.9)
        ring.fillColor = .clear
        ring.lineWidth = max(1, tileSize.width * 0.018)
        ring.setScale(0.45)
        layer.addChild(ring)

        let duration = reduceMotion ? 0.2 : 0.45
        ring.run(.sequence([
            .group([
                .scale(to: reduceMotion ? 1.0 : 1.65, duration: duration),
                .fadeOut(withDuration: duration)
            ]),
            .removeFromParent()
        ]))
    }
}

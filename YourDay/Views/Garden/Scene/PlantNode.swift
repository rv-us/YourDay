//
//  PlantNode.swift
//  YourDay
//
//  A placed plant: independently animated stage art plus stable labels,
//  status, interaction highlights, and drag feedback.
//

import SpriteKit

final class PlantNode: SKNode {
    let plantID: UUID
    private(set) var model: PlantRenderModel

    private let tileSize: CGSize
    private let animationProfile: PlantAnimationProfile
    private let artContainer = SKNode()
    private let effectLayer = SKNode()
    private let sprite = SKSpriteNode()
    private let nameLabel: SKLabelNode
    private let statusLabel: SKLabelNode
    private let statusPill: SKShapeNode
    private let highlightRing: SKShapeNode
    private let sellBadge: SKLabelNode

    private var displayedStage: GrowthStage
    private var transitionTargetStage: GrowthStage?
    private var transitionGeneration = 0
    private var reduceMotion: Bool
    private var isLifted = false
    private var isDroopingAndPanting = false

    private enum ActionKey {
        static let wind = "windSway"
        static let passive = "passivePlantMotion"
        static let transition = "growthTransition"
        static let planting = "plantingReveal"
        static let labelReveal = "labelReveal"
        static let lift = "lift"
        static let waterHit = "waterDropletHit"
        static let droop = "droopingMesh"
        static let pant = "pantingBreath"
        static let tint = "droopTint"
    }

    /// Wilted look for a thirsty plant — a muted, dry brown blended over the
    /// existing art rather than replacing it.
    private static let droopTintColor = UIColor(red: 0.5, green: 0.38, blue: 0.22, alpha: 1.0)
    private static let droopTintBlend: CGFloat = 0.4

    init(
        model: PlantRenderModel,
        tileSize: CGSize,
        textures: GardenTextureProvider,
        reduceMotion: Bool
    ) {
        plantID = model.id
        self.model = model
        self.tileSize = tileSize
        animationProfile = PlantAnimationProfile(plantID: model.id)
        displayedStage = model.stage
        self.reduceMotion = reduceMotion

        nameLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        statusLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        statusPill = SKShapeNode(
            rectOf: CGSize(width: tileSize.width * 0.62, height: tileSize.height * 0.2),
            cornerRadius: tileSize.height * 0.06
        )
        highlightRing = SKShapeNode(
            rectOf: CGSize(width: tileSize.width * 0.95, height: tileSize.height * 0.95),
            cornerRadius: tileSize.width * 0.12
        )
        sellBadge = SKLabelNode(fontNamed: "AvenirNext-Bold")

        super.init()

        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        artContainer.addChild(sprite)
        addChild(artContainer)

        effectLayer.zPosition = 1
        addChild(effectLayer)

        nameLabel.fontSize = tileSize.height * 0.15
        nameLabel.verticalAlignmentMode = .center
        nameLabel.position = CGPoint(x: 0, y: -tileSize.height * 0.28)
        nameLabel.zPosition = 2
        addChild(nameLabel)

        statusPill.lineWidth = 0
        statusPill.position = CGPoint(x: 0, y: -tileSize.height * 0.45)
        statusPill.zPosition = 2
        addChild(statusPill)

        statusLabel.fontSize = tileSize.height * 0.12
        statusLabel.verticalAlignmentMode = .center
        statusLabel.position = statusPill.position
        statusLabel.zPosition = 3
        addChild(statusLabel)

        highlightRing.lineWidth = tileSize.width * 0.035
        highlightRing.fillColor = .clear
        highlightRing.isHidden = true
        addChild(highlightRing)

        sellBadge.text = "$"
        sellBadge.fontSize = tileSize.height * 0.3
        sellBadge.verticalAlignmentMode = .center
        sellBadge.isHidden = true
        sellBadge.zPosition = 3
        addChild(sellBadge)

        applyStageTexture(for: model.stage, textures: textures)
        applyLabels()
        applyMode(.normal)
        sprite.warpGeometry = PlantWarpFactory.neutralGrid()
        startPassiveAnimationIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State

    func update(
        model: PlantRenderModel,
        mode: GardenSceneMode,
        textures: GardenTextureProvider,
        reduceMotion: Bool
    ) {
        let previousModel = self.model
        let reduceMotionChanged = self.reduceMotion != reduceMotion
        self.model = model
        self.reduceMotion = reduceMotion

        applyLabels()
        applyMode(mode)
        updateDroopAndPantState()

        if displayedStage != model.stage {
            if transitionTargetStage != model.stage || reduceMotionChanged {
                beginStageTransition(to: model.stage, textures: textures)
            }
        } else if transitionTargetStage != nil {
            cancelTransitionAndApplyCurrentStage(textures: textures)
        } else if previousModel.assetName != model.assetName
                    || previousModel.rarity != model.rarity
                    || previousModel.name != model.name {
            applyStageTexture(for: model.stage, textures: textures)
        }

        if reduceMotionChanged, transitionTargetStage == nil {
            cancelWindAnimation(resetWarp: true)
            startPassiveAnimationIfNeeded()
        }
    }

    func playPlantingReveal(textures: GardenTextureProvider) {
        cancelWindAnimation(resetWarp: true)
        stopPassiveAnimation(resetTransform: true)
        stopDroopAndPant()
        sprite.removeAction(forKey: ActionKey.transition)
        sprite.removeAction(forKey: ActionKey.planting)
        transitionTargetStage = nil

        PlantVFXFactory.playNatureBurst(
            on: effectLayer,
            tileSize: tileSize,
            dotTexture: textures.particleDotTexture(),
            reduceMotion: reduceMotion
        )

        let labelNodes: [SKNode] = [nameLabel, statusLabel, statusPill]
        labelNodes.forEach {
            $0.removeAction(forKey: ActionKey.labelReveal)
            $0.alpha = 0
        }

        sprite.alpha = 0
        sprite.xScale = reduceMotion ? 1 : 0.75
        sprite.yScale = reduceMotion ? 1 : 0.15

        let revealDuration = reduceMotion ? 0.2 : 0.45
        let reveal = SKAction.group([
            .fadeIn(withDuration: revealDuration),
            .scaleX(to: 1, duration: revealDuration),
            .scaleY(to: 1, duration: revealDuration)
        ])
        reveal.timingMode = reduceMotion ? .easeOut : .easeInEaseOut

        sprite.run(.sequence([
            reveal,
            .run { [weak self] in self?.startPassiveAnimationIfNeeded() }
        ]), withKey: ActionKey.planting)

        let labelDelay = reduceMotion ? 0 : 0.25
        for node in labelNodes {
            node.run(.sequence([
                .wait(forDuration: labelDelay),
                .fadeIn(withDuration: 0.2)
            ]), withKey: ActionKey.labelReveal)
        }
    }

    private func beginStageTransition(to stage: GrowthStage, textures: GardenTextureProvider) {
        transitionGeneration += 1
        let generation = transitionGeneration
        transitionTargetStage = stage

        sprite.removeAction(forKey: ActionKey.planting)
        sprite.removeAction(forKey: ActionKey.transition)
        cancelWindAnimation(resetWarp: true)
        stopPassiveAnimation(resetTransform: true)
        stopDroopAndPant()
        sprite.alpha = 1
        sprite.xScale = 1
        sprite.yScale = 1
        [nameLabel, statusLabel, statusPill].forEach { $0.alpha = 1 }

        PlantVFXFactory.playNatureBurst(
            on: effectLayer,
            tileSize: tileSize,
            dotTexture: textures.particleDotTexture(),
            reduceMotion: reduceMotion
        )

        let hideDuration = reduceMotion ? 0.1 : 0.15
        let revealDuration = reduceMotion ? 0.1 : 0.38
        let preSwapDelay = reduceMotion ? 0 : 0.07
        let hiddenScaleX: CGFloat = reduceMotion ? 1 : 0.88
        let hiddenScaleY: CGFloat = reduceMotion ? 1 : 0.82
        let incomingScaleX: CGFloat = reduceMotion ? 1 : 0.78
        let incomingScaleY: CGFloat = reduceMotion ? 1 : 0.55

        let hide = SKAction.group([
            .fadeAlpha(to: reduceMotion ? 0 : 0.12, duration: hideDuration),
            .scaleX(to: hiddenScaleX, duration: hideDuration),
            .scaleY(to: hiddenScaleY, duration: hideDuration)
        ])
        hide.timingMode = .easeIn

        let reveal = SKAction.group([
            .fadeIn(withDuration: revealDuration),
            .scaleX(to: 1, duration: revealDuration),
            .scaleY(to: 1, duration: revealDuration)
        ])
        reveal.timingMode = .easeOut

        sprite.run(.sequence([
            .wait(forDuration: preSwapDelay),
            hide,
            .run { [weak self] in
                guard let self, self.transitionGeneration == generation else { return }
                self.displayedStage = stage
                self.applyStageTexture(for: stage, textures: textures)
                self.sprite.alpha = 0
                self.sprite.xScale = incomingScaleX
                self.sprite.yScale = incomingScaleY
            },
            reveal,
            .run { [weak self] in
                guard let self, self.transitionGeneration == generation else { return }
                self.transitionTargetStage = nil
                self.sprite.alpha = 1
                self.sprite.xScale = 1
                self.sprite.yScale = 1
                self.sprite.warpGeometry = PlantWarpFactory.neutralGrid()
                self.startPassiveAnimationIfNeeded()
            }
        ]), withKey: ActionKey.transition)
    }

    private func cancelTransitionAndApplyCurrentStage(textures: GardenTextureProvider) {
        transitionGeneration += 1
        transitionTargetStage = nil
        sprite.removeAction(forKey: ActionKey.transition)
        effectLayer.removeAction(forKey: "vfxCleanup")
        effectLayer.removeAllChildren()
        displayedStage = model.stage
        applyStageTexture(for: model.stage, textures: textures)
        sprite.alpha = 1
        sprite.xScale = 1
        sprite.yScale = 1
        cancelWindAnimation(resetWarp: true)
        stopDroopAndPant()
        startPassiveAnimationIfNeeded()
    }

    private func applyStageTexture(for stage: GrowthStage, textures: GardenTextureProvider) {
        let texture: SKTexture?
        let boxScale: CGFloat
        switch stage {
        case .grown:
            texture = textures.plantTexture(
                assetName: model.assetName,
                rarity: model.rarity,
                displayName: model.name,
                tileSize: tileSize
            )
            boxScale = 0.72
        case .seedling:
            texture = textures.texture(named: "seedling")
            boxScale = 0.6
        case .seed:
            texture = textures.texture(named: "seed")
            boxScale = 0.5
        }

        guard let texture else {
            sprite.texture = nil
            sprite.color = UIColor(model.rarity.backgroundColor)
            sprite.size = CGSize(width: tileSize.width * 0.5, height: tileSize.height * 0.5)
            alignArtBaseline()
            return
        }

        let box = CGSize(width: tileSize.width * boxScale, height: tileSize.height * boxScale)
        let textureSize = texture.size()
        var fitted = box
        if textureSize.width > 0, textureSize.height > 0 {
            let scale = min(box.width / textureSize.width, box.height / textureSize.height)
            fitted = CGSize(width: textureSize.width * scale, height: textureSize.height * scale)
        }
        sprite.texture = texture
        sprite.size = fitted
        alignArtBaseline()
    }

    private func alignArtBaseline() {
        let baselineY = tileSize.height * 0.12 - sprite.size.height / 2
        sprite.position = CGPoint(x: 0, y: baselineY)
        effectLayer.position = CGPoint(x: 0, y: baselineY)
    }

    private func applyLabels() {
        let isDay = GardenAssetHelper.isDayTime()

        nameLabel.text = model.name
        nameLabel.fontColor = isDay
            ? UIColor(red: 0.18, green: 0.27, blue: 0.0, alpha: 1.0)
            : .white

        if model.isFullyGrown {
            statusLabel.text = ""
            statusPill.isHidden = true
        } else {
            statusLabel.text = "\(model.daysLeftTillFullyGrown)d left"
            statusPill.isHidden = true
            statusLabel.fontColor = model.wateredToday
                ? (isDay
                    ? UIColor(red: 0.38, green: 0.38, blue: 0.38, alpha: 0.9)
                    : UIColor.white.withAlphaComponent(0.85))
                : UIColor(red: 0.85, green: 0.25, blue: 0.22, alpha: 1.0)
        }
    }

    private func applyMode(_ mode: GardenSceneMode) {
        switch mode {
        case .watering where !model.wateredToday:
            // Blue guide ring: this plant still wants water today.
            highlightRing.isHidden = false
            highlightRing.strokeColor = UIColor(red: 0.3, green: 0.68, blue: 0.98, alpha: 0.65)
            sellBadge.isHidden = true
        case .fertilizer where !model.isFullyGrown:
            highlightRing.isHidden = false
            highlightRing.strokeColor = UIColor(red: 1.0, green: 0.65, blue: 0.15, alpha: 0.7)
            sellBadge.isHidden = true
        case .sell where model.isFullyGrown:
            highlightRing.isHidden = false
            highlightRing.strokeColor = UIColor(red: 0.4, green: 0.73, blue: 0.42, alpha: 0.7)
            sellBadge.isHidden = false
            sellBadge.fontColor = UIColor(red: 0.4, green: 0.73, blue: 0.42, alpha: 0.9)
        default:
            highlightRing.isHidden = true
            sellBadge.isHidden = true
        }
    }

    // MARK: - Droop and pant state

    private func updateDroopAndPantState() {
        let shouldDroop = !model.wateredToday && !isLifted
        if shouldDroop && !isDroopingAndPanting {
            startDroopAndPant()
        } else if !shouldDroop && isDroopingAndPanting {
            stopDroopAndPant()
        }
    }

    private func startDroopAndPant() {
        guard !reduceMotion, transitionTargetStage == nil else { return }
        isDroopingAndPanting = true

        let stageStrength: CGFloat
        switch displayedStage {
        case .seed: return
        case .seedling: stageStrength = 0.55
        case .grown: stageStrength = 1
        }

        cancelWindAnimation(resetWarp: false)
        stopPassiveAnimation(resetTransform: false)

        // Slow sag that settles into a rest droop and eases slightly deeper
        // and back — a gentle wilt instead of a single rigid bend.
        let restDroop = -stageStrength * 0.1
        let deepDroop = -stageStrength * 0.15
        let sagCycle = 3.2
        let sinkIn = warpAction(to: restDroop, duration: 1.1, timingMode: .easeIn)
        let deepen = warpAction(to: deepDroop, duration: sagCycle * 0.5, timingMode: .easeInEaseOut)
        let ease = warpAction(to: restDroop, duration: sagCycle * 0.5, timingMode: .easeInEaseOut)
        guard let sinkIn, let deepen, let ease else { return }

        sprite.run(.sequence([
            sinkIn,
            .repeatForever(.sequence([deepen, ease]))
        ]), withKey: ActionKey.droop)

        sprite.removeAction(forKey: ActionKey.tint)
        sprite.run(
            .colorize(with: Self.droopTintColor, colorBlendFactor: Self.droopTintBlend, duration: 0.7),
            withKey: ActionKey.tint
        )

        // Slow, shallow breathing — a tired sag-and-lift, not rapid panting.
        let breatheCycle = 2.4
        let breatheDown = SKAction.scaleY(to: 1 - 0.025 * stageStrength, duration: breatheCycle * 0.55)
        breatheDown.timingMode = .easeInEaseOut
        let breatheUp = SKAction.scaleY(to: 1.0, duration: breatheCycle * 0.45)
        breatheUp.timingMode = .easeInEaseOut

        artContainer.run(.repeatForever(.sequence([breatheDown, breatheUp])), withKey: ActionKey.pant)
    }

    private func stopDroopAndPant() {
        isDroopingAndPanting = false
        sprite.removeAction(forKey: ActionKey.droop)
        artContainer.removeAction(forKey: ActionKey.pant)
        sprite.warpGeometry = PlantWarpFactory.neutralGrid()
        artContainer.yScale = 1
        sprite.removeAction(forKey: ActionKey.tint)
        sprite.run(.colorize(withColorBlendFactor: 0, duration: 0.35), withKey: ActionKey.tint)
        startPassiveAnimationIfNeeded()
    }

    // MARK: - Watering droplet response

    /// Quick droplet-impact jiggle. Runs on the sprite's scale/rotation, so it
    /// never fights the warp-based wind sway or the artContainer passive
    /// motion. The key guard keeps rapid droplets from stacking shakes.
    func playWaterDropletHit() {
        guard !reduceMotion, !isLifted, transitionTargetStage == nil,
              sprite.action(forKey: ActionKey.planting) == nil,
              sprite.action(forKey: ActionKey.waterHit) == nil else { return }

        let direction: CGFloat = Bool.random() ? 1 : -1
        let squash = SKAction.group([
            .scaleX(to: 1.05, duration: 0.05),
            .scaleY(to: 0.94, duration: 0.05),
            .rotate(toAngle: direction * 0.03, duration: 0.05)
        ])
        squash.timingMode = .easeOut
        let rebound = SKAction.group([
            .scaleX(to: 0.98, duration: 0.07),
            .scaleY(to: 1.03, duration: 0.07),
            .rotate(toAngle: -direction * 0.018, duration: 0.07)
        ])
        rebound.timingMode = .easeInEaseOut
        let settle = SKAction.group([
            .scaleX(to: 1, duration: 0.08),
            .scaleY(to: 1, duration: 0.08),
            .rotate(toAngle: 0, duration: 0.08)
        ])
        settle.timingMode = .easeOut
        sprite.run(.sequence([squash, rebound, settle]), withKey: ActionKey.waterHit)
    }

    // MARK: - Traveling wind response

    /// Called by GardenScene at the moment the scene-wide gust reaches this
    /// plant's x-position. The small rebounds form a damped settle, so the art
    /// reaches its neutral grid through interpolation rather than a reset.
    func playWindRustle(direction: CGFloat, gustStrength: CGFloat, delay: TimeInterval) {
        guard !reduceMotion, !isLifted, transitionTargetStage == nil else { return }

        let stageStrength: CGFloat
        switch displayedStage {
        case .seed: return
        case .seedling: stageStrength = 0.58
        case .grown: stageStrength = 1
        }

        cancelWindAnimation(resetWarp: false)
        let primaryOffset = direction
            * animationProfile.bendAmplitude
            * animationProfile.responseStrength
            * gustStrength
            * stageStrength
        let settle = animationProfile.settleDuration

        guard let gust = warpAction(
            to: primaryOffset,
            duration: settle * 0.24,
            timingMode: .easeOut
        ), let firstRebound = warpAction(
            to: -primaryOffset * 0.34,
            duration: settle * 0.27,
            timingMode: .easeInEaseOut
        ), let secondRebound = warpAction(
            to: primaryOffset * 0.13,
            duration: settle * 0.21,
            timingMode: .easeInEaseOut
        ), let finalSettle = warpAction(
            to: 0,
            duration: settle * 0.28,
            timingMode: .easeOut
        ) else { return }

        sprite.run(.sequence([
            .wait(forDuration: delay),
            gust,
            firstRebound,
            secondRebound,
            finalSettle,
            .run { [weak self] in
                // The preceding action has already reached neutral; assigning
                // the exact grid here only prevents accumulated float drift.
                self?.sprite.warpGeometry = PlantWarpFactory.neutralGrid()
            }
        ]), withKey: ActionKey.wind)
    }

    private func warpAction(
        to horizontalOffset: CGFloat,
        duration: TimeInterval,
        timingMode: SKActionTimingMode
    ) -> SKAction? {
        guard let action = SKAction.warp(
            to: PlantWarpFactory.grid(horizontalOffset: horizontalOffset),
            duration: duration
        ) else { return nil }
        action.timingMode = timingMode
        return action
    }

    private func cancelWindAnimation(resetWarp: Bool) {
        sprite.removeAction(forKey: ActionKey.wind)
        if resetWarp {
            sprite.warpGeometry = PlantWarpFactory.neutralGrid()
        }
    }

    // MARK: - Passive life

    private func startPassiveAnimationIfNeeded() {
        stopPassiveAnimation(resetTransform: true)
        guard !reduceMotion, !isLifted, transitionTargetStage == nil else { return }

        let stageStrength: CGFloat
        switch displayedStage {
        case .seed: return
        case .seedling: stageStrength = 0.55
        case .grown: stageStrength = 1
        }

        let tilt = animationProfile.passiveTilt
            * animationProfile.passiveDirection
            * stageStrength
        let lift = animationProfile.passiveLift * stageStrength
        let duration = animationProfile.passiveCycleDuration

        let lean = SKAction.group([
            .rotate(toAngle: tilt, duration: duration * 0.34),
            .scaleX(to: 1 - lift * 0.28, duration: duration * 0.34),
            .scaleY(to: 1 + lift, duration: duration * 0.34)
        ])
        let counterLean = SKAction.group([
            .rotate(toAngle: -tilt * 0.58, duration: duration * 0.32),
            .scaleX(to: 1 + lift * 0.16, duration: duration * 0.32),
            .scaleY(to: 1 + lift * 0.22, duration: duration * 0.32)
        ])
        let settle = SKAction.group([
            .rotate(toAngle: 0, duration: duration * 0.34),
            .scaleX(to: 1, duration: duration * 0.34),
            .scaleY(to: 1, duration: duration * 0.34)
        ])
        [lean, counterLean, settle].forEach { $0.timingMode = .easeInEaseOut }

        let cycle = SKAction.sequence([lean, counterLean, settle])
        artContainer.run(.sequence([
            .wait(forDuration: animationProfile.passiveDelay),
            .repeatForever(cycle)
        ]), withKey: ActionKey.passive)
    }

    private func stopPassiveAnimation(resetTransform: Bool) {
        artContainer.removeAction(forKey: ActionKey.passive)
        if resetTransform {
            artContainer.zRotation = 0
            artContainer.xScale = 1
            artContainer.yScale = 1
        }
    }

    // MARK: - Drag visuals

    func setLifted(_ lifted: Bool) {
        isLifted = lifted
        if lifted {
            cancelWindAnimation(resetWarp: true)
            stopPassiveAnimation(resetTransform: true)
            stopDroopAndPant()
        } else {
            updateDroopAndPantState()
            startPassiveAnimationIfNeeded()
        }

        removeAction(forKey: ActionKey.lift)
        let action: SKAction = lifted
            ? .group([.scale(to: 1.12, duration: 0.15), .fadeAlpha(to: 0.85, duration: 0.15)])
            : .group([.scale(to: 1.0, duration: 0.15), .fadeAlpha(to: 1.0, duration: 0.15)])
        run(action, withKey: ActionKey.lift)
    }

    func setSwapTargetHighlight(_ highlighted: Bool) {
        if highlighted {
            highlightRing.isHidden = false
            highlightRing.strokeColor = UIColor(red: 0.16, green: 0.71, blue: 0.96, alpha: 0.85)
        } else {
            highlightRing.isHidden = true
        }
    }
}

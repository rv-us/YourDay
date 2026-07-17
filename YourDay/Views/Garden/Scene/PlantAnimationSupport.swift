//
//  PlantAnimationSupport.swift
//  YourDay
//
//  Deterministic wind responses, reusable warp geometry, traveling gust VFX,
//  and short-lived nature VFX for static plant artwork.
//

import SpriteKit
import simd

struct PlantAnimationProfile: Equatable {
    let bendAmplitude: CGFloat
    let responseStrength: CGFloat
    let settleDuration: TimeInterval
    let passiveTilt: CGFloat
    let passiveLift: CGFloat
    let passiveCycleDuration: TimeInterval
    let passiveDelay: TimeInterval
    let passiveDirection: CGFloat

    init(plantID: UUID) {
        var uuid = plantID.uuid
        let bytes = withUnsafeBytes(of: &uuid) { Array($0) }

        func unit(_ index: Int) -> CGFloat {
            CGFloat(bytes[index % bytes.count]) / 255
        }

        bendAmplitude = 0.065 + unit(1) * 0.04
        responseStrength = 0.92 + unit(2) * 0.2
        settleDuration = 1.35 + TimeInterval(unit(3) * 0.45)
        passiveTilt = 0.0035 + unit(4) * 0.003
        passiveLift = 0.004 + unit(5) * 0.003
        passiveCycleDuration = 4.8 + TimeInterval(unit(6) * 2.2)
        passiveDelay = TimeInterval(unit(8) * 1.8)
        passiveDirection = bytes[9].isMultiple(of: 2) ? -1 : 1
    }
}

enum GardenWindProfile {
    static let travelDuration: TimeInterval = 4.2
    static let horizontalOverscanFraction: CGFloat = 0.45

    static func direction(forGust index: Int) -> CGFloat {
        index.isMultiple(of: 2) ? 1 : -1
    }

    static func strength(forGust index: Int) -> CGFloat {
        let pattern: [CGFloat] = [1.0, 1.12, 0.94, 1.06]
        return pattern[index % pattern.count]
    }

    static func intervalAfterGust(_ index: Int) -> TimeInterval {
        _ = index
        return 10
    }

    static func travelProgress(
        x: CGFloat,
        minimumX: CGFloat,
        maximumX: CGFloat,
        direction: CGFloat
    ) -> CGFloat {
        guard maximumX > minimumX else { return 0 }
        let leftToRight = min(1, max(0, (x - minimumX) / (maximumX - minimumX)))
        return direction >= 0 ? leftToRight : 1 - leftToRight
    }

    /// Roughly one quarter of occupied plots throw a few grass clippings on
    /// each gust. The selection changes per gust but is stable for replays.
    static func liftsGrass(plantID: UUID, gustIndex: Int) -> Bool {
        var uuid = plantID.uuid
        let bytes = withUnsafeBytes(of: &uuid) { Array($0) }
        let mixed = Int(bytes[7]) ^ Int(bytes[13]) ^ (gustIndex &* 47)
        return mixed & 3 == 0
    }
}

enum PlantWarpFactory {
    static let columns = 2
    static let rows = 3

    static func neutralGrid() -> SKWarpGeometryGrid {
        SKWarpGeometryGrid(columns: columns, rows: rows)
    }

    static func grid(horizontalOffset: CGFloat) -> SKWarpGeometryGrid {
        let positions = destinationPositions(horizontalOffset: horizontalOffset)

        return SKWarpGeometryGrid(
            columns: columns,
            rows: rows,
            sourcePositions: neutralPositions(),
            destinationPositions: positions
        )
    }

    static func destinationPositions(horizontalOffset: CGFloat) -> [SIMD2<Float>] {
        var positions: [SIMD2<Float>] = []
        positions.reserveCapacity((columns + 1) * (rows + 1))

        for row in 0...rows {
            let verticalProgress = CGFloat(row) / CGFloat(rows)
            let bendProgress = pow(verticalProgress, 1.35)
            let offset = horizontalOffset * bendProgress
            let compression = abs(horizontalOffset) * 0.12 * bendProgress

            for column in 0...columns {
                let x = CGFloat(column) / CGFloat(columns)
                positions.append(
                    SIMD2(
                        Float(x + offset),
                        Float(verticalProgress - compression)
                    )
                )
            }
        }
        return positions
    }

    private static func neutralPositions() -> [SIMD2<Float>] {
        var positions: [SIMD2<Float>] = []
        positions.reserveCapacity((columns + 1) * (rows + 1))
        for row in 0...rows {
            for column in 0...columns {
                positions.append(
                    SIMD2(
                        Float(column) / Float(columns),
                        Float(row) / Float(rows)
                    )
                )
            }
        }
        return positions
    }
}

@MainActor
enum GardenWindVFXFactory {
    static func playTravelingGust(
        on layer: SKNode,
        islandFrame: CGRect,
        direction: CGFloat,
        tileSize: CGSize
    ) {
        layer.removeAction(forKey: "windCleanup")
        layer.removeAllChildren()

        let overscan = islandFrame.width * GardenWindProfile.horizontalOverscanFraction
        let leadingX = direction >= 0
            ? islandFrame.minX - overscan
            : islandFrame.maxX + overscan
        let trailingX = direction >= 0
            ? islandFrame.maxX + overscan
            : islandFrame.minX - overscan

        // Each wisp owns its shape, start time, speed, and curved flight path.
        // The loose vertical spread deliberately includes the ocean around the
        // island, so the wind feels like part of the world rather than an
        // effect clipped to the garden plots.
        let verticalOffsets: [CGFloat] = [-0.62, -0.37, -0.13, 0.16, 0.4, 0.63]
        let startDelays: [TimeInterval] = [0, 0.2, 0.07, 0.34, 0.14, 0.42]
        let durationScales: [CGFloat] = [1.0, 1.08, 0.96, 1.12, 0.91, 1.04]
        let lengthScales: [CGFloat] = [0.14, 0.2, 0.11, 0.17, 0.23, 0.13]
        let verticalDrifts: [CGFloat] = [0.1, -0.07, 0.13, -0.11, 0.06, -0.09]

        for index in verticalOffsets.indices {
            let wispNode = SKNode()
            wispNode.alpha = 0
            layer.addChild(wispNode)

            let signedLength = islandFrame.width * lengthScales[index] * direction
            let localCurve = tileSize.height * (index.isMultiple(of: 2) ? 0.22 : -0.18)
            let shapePath = CGMutablePath()
            shapePath.move(to: CGPoint(x: -signedLength * 0.52, y: -localCurve * 0.22))
            shapePath.addCurve(
                to: CGPoint(x: signedLength * 0.08, y: localCurve * 0.18),
                control1: CGPoint(x: -signedLength * 0.34, y: localCurve),
                control2: CGPoint(x: -signedLength * 0.08, y: -localCurve * 0.55)
            )
            shapePath.addCurve(
                to: CGPoint(x: signedLength * 0.52, y: 0),
                control1: CGPoint(x: signedLength * 0.22, y: localCurve * 0.65),
                control2: CGPoint(x: signedLength * 0.4, y: -localCurve * 0.28)
            )

            let streak = SKShapeNode(path: shapePath)
            streak.strokeColor = UIColor(
                red: 0.86,
                green: 0.96,
                blue: 1,
                alpha: 0.38 - CGFloat(index % 3) * 0.035
            )
            streak.lineWidth = max(1.5, tileSize.width * (index.isMultiple(of: 2) ? 0.032 : 0.024))
            streak.lineCap = .round
            streak.glowWidth = tileSize.width * 0.035
            wispNode.addChild(streak)

            if index == 1 || index == 4 {
                let curlPath = CGMutablePath()
                curlPath.move(to: CGPoint(x: -signedLength * 0.2, y: -tileSize.height * 0.1))
                curlPath.addCurve(
                    to: CGPoint(x: signedLength * 0.18, y: tileSize.height * 0.03),
                    control1: CGPoint(x: -signedLength * 0.02, y: tileSize.height * 0.18),
                    control2: CGPoint(x: signedLength * 0.2, y: tileSize.height * 0.15)
                )
                let curl = SKShapeNode(path: curlPath)
                curl.strokeColor = UIColor.white.withAlphaComponent(0.2)
                curl.lineWidth = max(1, tileSize.width * 0.015)
                curl.lineCap = .round
                wispNode.addChild(curl)
            }

            let extraStartOffset = CGFloat(index % 3) * tileSize.width * 0.7 * -direction
            let start = CGPoint(
                x: leadingX + extraStartOffset,
                y: islandFrame.midY + islandFrame.height * verticalOffsets[index]
            )
            let end = CGPoint(
                x: trailingX,
                y: start.y + islandFrame.height * verticalDrifts[index]
            )
            wispNode.position = start

            let flightPath = CGMutablePath()
            flightPath.move(to: start)
            flightPath.addCurve(
                to: end,
                control1: CGPoint(
                    x: start.x + (end.x - start.x) * 0.31,
                    y: start.y + islandFrame.height * verticalDrifts[(index + 2) % verticalDrifts.count]
                ),
                control2: CGPoint(
                    x: start.x + (end.x - start.x) * 0.7,
                    y: end.y - islandFrame.height * verticalDrifts[(index + 3) % verticalDrifts.count] * 0.8
                )
            )

            let flightDuration = GardenWindProfile.travelDuration * TimeInterval(durationScales[index])
            let fly = SKAction.follow(
                flightPath,
                asOffset: false,
                orientToPath: false,
                duration: flightDuration
            )
            fly.timingMode = .easeInEaseOut
            let fade = SKAction.sequence([
                .fadeAlpha(to: 0.78, duration: 0.16),
                .wait(forDuration: max(0, flightDuration - 0.46)),
                .fadeOut(withDuration: 0.3)
            ])
            wispNode.run(.sequence([
                .wait(forDuration: startDelays[index]),
                .group([fly, fade]),
                .removeFromParent()
            ]))
        }

        layer.run(.sequence([
            .wait(forDuration: GardenWindProfile.travelDuration * 1.12 + 0.65),
            .run { [weak layer] in layer?.removeAllChildren() }
        ]), withKey: "windCleanup")
    }

    static func playGrassLift(
        on layer: SKNode,
        at position: CGPoint,
        tileSize: CGSize,
        direction: CGFloat,
        delay: TimeInterval,
        plantID: UUID,
        gustIndex: Int
    ) {
        let clippingGroup = SKNode()
        clippingGroup.position = CGPoint(x: position.x, y: position.y - tileSize.height * 0.08)
        layer.addChild(clippingGroup)

        var uuid = plantID.uuid
        let bytes = withUnsafeBytes(of: &uuid) { Array($0) }
        let colors = [
            UIColor(red: 0.28, green: 0.58, blue: 0.2, alpha: 0.85),
            UIColor(red: 0.42, green: 0.7, blue: 0.25, alpha: 0.82),
            UIColor(red: 0.58, green: 0.76, blue: 0.3, alpha: 0.78)
        ]

        let clippingCount = 3 + (Int(bytes[(gustIndex + 3) % bytes.count]) % 2)
        for index in 0..<clippingCount {
            let byte = CGFloat(bytes[(index + gustIndex) % bytes.count]) / 255
            let blade = SKShapeNode(
                rectOf: CGSize(
                    width: max(2, tileSize.width * 0.022),
                    height: tileSize.height * (0.07 + byte * 0.035)
                ),
                cornerRadius: tileSize.width * 0.012
            )
            blade.fillColor = colors[index % colors.count]
            blade.strokeColor = .clear
            blade.alpha = 0
            blade.position.x = (byte - 0.5) * tileSize.width * 0.42
            blade.zRotation = (byte - 0.5) * 0.55
            clippingGroup.addChild(blade)

            let localDelay = delay + TimeInterval(index) * 0.035
            let duration = 0.46 + TimeInterval(byte) * 0.15
            let travel = SKAction.moveBy(
                x: direction * tileSize.width * (0.32 + byte * 0.25),
                y: tileSize.height * (0.17 + byte * 0.14),
                duration: duration
            )
            travel.timingMode = .easeOut
            let fade = SKAction.sequence([
                .fadeAlpha(to: 0.82, duration: 0.07),
                .wait(forDuration: duration * 0.36),
                .fadeOut(withDuration: duration * 0.5)
            ])
            let rotate = SKAction.rotate(byAngle: -direction * (0.65 + byte * 0.7), duration: duration)
            rotate.timingMode = .easeInEaseOut
            blade.run(.sequence([
                .wait(forDuration: localDelay),
                .group([travel, fade, rotate]),
                .removeFromParent()
            ]))
        }

        clippingGroup.run(.sequence([
            .wait(forDuration: delay + 0.9),
            .removeFromParent()
        ]))
    }
}

@MainActor
enum PlantVFXFactory {
    static func playNatureBurst(
        on layer: SKNode,
        tileSize: CGSize,
        dotTexture: SKTexture,
        reduceMotion: Bool
    ) {
        layer.removeAction(forKey: "vfxCleanup")
        layer.removeAllChildren()

        if !reduceMotion {
            let dirt = makeEmitter(
                texture: dotTexture,
                color: UIColor(red: 0.42, green: 0.27, blue: 0.12, alpha: 0.9),
                count: 11,
                tileSize: tileSize,
                speed: tileSize.height * 0.34,
                lifetime: 0.48,
                scale: 0.055,
                blendMode: .alpha
            )
            dirt.emissionAngle = .pi / 2
            dirt.emissionAngleRange = .pi * 0.85
            dirt.yAcceleration = -tileSize.height * 0.55
            dirt.particlePositionRange = CGVector(dx: tileSize.width * 0.28, dy: tileSize.height * 0.04)
            layer.addChild(dirt)
            dirt.targetNode = layer
        }

        let moteCount = reduceMotion ? 3 : 7
        let greenMotes = makeMagicMotes(
            texture: dotTexture,
            color: UIColor(red: 0.48, green: 0.88, blue: 0.46, alpha: 0.95),
            count: moteCount,
            tileSize: tileSize,
            reduceMotion: reduceMotion
        )
        let goldMotes = makeMagicMotes(
            texture: dotTexture,
            color: UIColor(red: 1.0, green: 0.82, blue: 0.3, alpha: 0.95),
            count: moteCount,
            tileSize: tileSize,
            reduceMotion: reduceMotion
        )
        greenMotes.position.x = -tileSize.width * 0.04
        goldMotes.position.x = tileSize.width * 0.04
        layer.addChild(greenMotes)
        layer.addChild(goldMotes)
        greenMotes.targetNode = layer
        goldMotes.targetNode = layer

        let ring = SKShapeNode(circleOfRadius: tileSize.width * 0.2)
        ring.strokeColor = UIColor(red: 0.66, green: 0.94, blue: 0.55, alpha: 0.9)
        ring.fillColor = .clear
        ring.lineWidth = max(1, tileSize.width * 0.018)
        ring.alpha = 0.9
        ring.setScale(0.45)
        ring.position.y = tileSize.height * 0.08
        layer.addChild(ring)

        let ringDuration = reduceMotion ? 0.2 : 0.45
        ring.run(.sequence([
            .group([
                .scale(to: reduceMotion ? 1.0 : 1.65, duration: ringDuration),
                .fadeOut(withDuration: ringDuration)
            ]),
            .removeFromParent()
        ]))

        layer.run(.sequence([
            .wait(forDuration: reduceMotion ? 0.5 : 1.0),
            .run { [weak layer] in layer?.removeAllChildren() }
        ]), withKey: "vfxCleanup")
    }

    private static func makeMagicMotes(
        texture: SKTexture,
        color: UIColor,
        count: Int,
        tileSize: CGSize,
        reduceMotion: Bool
    ) -> SKEmitterNode {
        let emitter = makeEmitter(
            texture: texture,
            color: color,
            count: count,
            tileSize: tileSize,
            speed: tileSize.height * (reduceMotion ? 0.22 : 0.48),
            lifetime: reduceMotion ? 0.32 : 0.68,
            scale: reduceMotion ? 0.04 : 0.05,
            blendMode: .add
        )
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi * 0.38
        emitter.yAcceleration = tileSize.height * 0.08
        emitter.particlePosition = CGPoint(x: 0, y: tileSize.height * 0.04)
        emitter.particlePositionRange = CGVector(dx: tileSize.width * 0.25, dy: tileSize.height * 0.08)
        return emitter
    }

    private static func makeEmitter(
        texture: SKTexture,
        color: UIColor,
        count: Int,
        tileSize: CGSize,
        speed: CGFloat,
        lifetime: TimeInterval,
        scale: CGFloat,
        blendMode: SKBlendMode
    ) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = texture
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = blendMode
        emitter.particleBirthRate = CGFloat(count) * 90
        emitter.numParticlesToEmit = count
        emitter.particleLifetime = lifetime
        emitter.particleLifetimeRange = lifetime * 0.22
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.35
        emitter.particleAlpha = 0.95
        emitter.particleAlphaRange = 0.05
        emitter.particleAlphaSpeed = -1.25 / lifetime
        emitter.particleScale = scale * max(tileSize.width, tileSize.height) / max(texture.size().width, 1)
        emitter.particleScaleRange = emitter.particleScale * 0.35
        emitter.particleScaleSpeed = -emitter.particleScale * 0.55
        emitter.particleRotationRange = .pi
        emitter.particleRotationSpeed = .pi
        return emitter
    }
}

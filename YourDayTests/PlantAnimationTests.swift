//
//  PlantAnimationTests.swift
//  YourDayTests
//

import Foundation
import Testing
@testable import YourDay

struct PlantAnimationTests {
    @Test func animationProfileIsStableAndBounded() throws {
        let id = try #require(UUID(uuidString: "12345678-1234-5678-90AB-CDEF12345678"))
        let first = PlantAnimationProfile(plantID: id)
        let second = PlantAnimationProfile(plantID: id)

        #expect(first == second)
        #expect((0.065...0.105).contains(first.bendAmplitude))
        #expect((0.92...1.12).contains(first.responseStrength))
        #expect((1.35...1.8).contains(first.settleDuration))
        #expect((0.0035...0.0065).contains(first.passiveTilt))
        #expect((0.004...0.007).contains(first.passiveLift))
        #expect((4.8...7.0).contains(first.passiveCycleDuration))
        #expect((0...1.8).contains(first.passiveDelay))
        #expect(first.passiveDirection == -1 || first.passiveDirection == 1)
    }

    @Test func differentPlantsReceiveDifferentPersonalities() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFE"))

        #expect(
            PlantAnimationProfile(plantID: firstID)
                != PlantAnimationProfile(plantID: secondID)
        )
    }

    @Test func warpKeepsRootsFixedAndBendsProgressively() {
        let positions = PlantWarpFactory.destinationPositions(horizontalOffset: 0.04)

        #expect(positions.count == 12)
        #expect(positions[0] == SIMD2<Float>(0, 0))
        #expect(positions[1] == SIMD2<Float>(0.5, 0))
        #expect(positions[2] == SIMD2<Float>(1, 0))

        let lowerShift = positions[3].x
        let middleShift = positions[6].x
        let topShift = positions[9].x
        #expect(lowerShift > 0)
        #expect(middleShift > lowerShift)
        #expect(topShift > middleShift)
    }

    @Test func gustTravelProgressFollowsWindDirection() {
        let leftPlant = GardenWindProfile.travelProgress(
            x: 25,
            minimumX: 0,
            maximumX: 100,
            direction: 1
        )
        let rightPlant = GardenWindProfile.travelProgress(
            x: 75,
            minimumX: 0,
            maximumX: 100,
            direction: 1
        )
        let reversedLeftPlant = GardenWindProfile.travelProgress(
            x: 25,
            minimumX: 0,
            maximumX: 100,
            direction: -1
        )

        #expect(leftPlant < rightPlant)
        #expect(reversedLeftPlant > leftPlant)
        #expect(GardenWindProfile.direction(forGust: 0) == 1)
        #expect(GardenWindProfile.direction(forGust: 1) == -1)
        #expect(GardenWindProfile.intervalAfterGust(0) == 10)
        #expect(GardenWindProfile.intervalAfterGust(7) == 10)
    }

    @Test func grassLiftSelectionIsSparseAndChangesAcrossGusts() throws {
        let plantID = try #require(UUID(uuidString: "12345678-1234-5678-90AB-CDEF12345678"))
        let firstPass = (0..<16).map {
            GardenWindProfile.liftsGrass(plantID: plantID, gustIndex: $0)
        }
        let secondPass = (0..<16).map {
            GardenWindProfile.liftsGrass(plantID: plantID, gustIndex: $0)
        }

        #expect(firstPass == secondPass)
        #expect(firstPass.contains(true))
        #expect(firstPass.contains(false))
    }

    @Test func growthStageRulesRemainCompatibleWithGardenState() {
        #expect(GrowthStage.stage(daysLeft: 4, initialDaysToGrow: 5) == .seed)
        #expect(GrowthStage.stage(daysLeft: 2, initialDaysToGrow: 5) == .seedling)
        #expect(GrowthStage.stage(daysLeft: 0, initialDaysToGrow: 5) == .grown)
    }
}

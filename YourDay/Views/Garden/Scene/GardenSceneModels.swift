//
//  GardenSceneModels.swift
//  YourDay
//
//  Value types passed between SwiftUI (game logic) and GardenScene (renderer).
//  The scene never reads SwiftData/Firebase — SwiftUI pushes GardenSnapshot in,
//  and the scene emits GardenSceneEvent back out.
//

import Foundation
import CoreGraphics

enum GrowthStage: Equatable {
    case seed
    case seedling
    case grown

    /// Same rule as the legacy PlantPlotView.currentPlantVisual().
    static func stage(daysLeft: Int, initialDaysToGrow: Int) -> GrowthStage {
        if daysLeft <= 0 { return .grown }
        if initialDaysToGrow > 1 && daysLeft <= initialDaysToGrow / 2 { return .seedling }
        return .seed
    }
}

struct PlantRenderModel: Equatable, Identifiable {
    let id: UUID
    var position: GridPosition
    var name: String
    var assetName: String
    var rarity: Rarity
    var stage: GrowthStage
    var daysLeftTillFullyGrown: Int
    var wateredToday: Bool

    init(from plant: PlacedPlant) {
        id = plant.id
        position = plant.position
        name = plant.name
        assetName = plant.assetName
        rarity = plant.rarity
        stage = GrowthStage.stage(
            daysLeft: plant.daysLeftTillFullyGrown,
            initialDaysToGrow: plant.initialDaysToGrow
        )
        daysLeftTillFullyGrown = plant.daysLeftTillFullyGrown
        wateredToday = plant.lastWateredOnDay != nil
            && Calendar.current.isDateInToday(plant.lastWateredOnDay!)
    }

    var isFullyGrown: Bool { stage == .grown }
}

enum GardenSceneMode: Equatable {
    case normal
    case sell
    case fertilizer
}

/// Semantic world events emitted by the scene. All mode/tutorial routing
/// happens in GardenView.handleSceneEvent — the scene only reports what was
/// touched, never decides what it means.
enum GardenSceneEvent {
    case tappedPlant(id: UUID)
    case tappedEmptyTile(GridPosition)
    case longPressedPlant(id: UUID)
    case swapRequested(draggedID: UUID, targetID: UUID)
}

struct GardenSnapshot: Equatable {
    var plants: [PlantRenderModel]
    var unlockedPlotCount: Int
    var mode: GardenSceneMode
    var dragEnabled: Bool
    var reduceMotion: Bool
}

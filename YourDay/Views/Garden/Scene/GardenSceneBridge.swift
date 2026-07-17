//
//  GardenSceneBridge.swift
//  YourDay
//
//  Owns the GardenScene and mediates between SwiftUI and SpriteKit:
//  SwiftUI pushes GardenSnapshot in, the scene emits GardenSceneEvent out
//  through `onEvent`. The bridge never publishes per-frame state — camera
//  movement stays entirely inside the scene.
//

import SwiftUI
import SpriteKit

@MainActor
final class GardenSceneBridge: ObservableObject {
    private(set) var gardenScene: GardenScene?

    /// Set by GardenView; receives all world interaction events.
    var onEvent: ((GardenSceneEvent) -> Void)?

    func scene(for size: CGSize) -> GardenScene {
        if let existing = gardenScene { return existing }
        let scene = GardenScene(size: size)
        scene.scaleMode = .resizeFill
        scene.bridge = self
        gardenScene = scene
        return scene
    }

    func apply(_ snapshot: GardenSnapshot) {
        gardenScene?.apply(snapshot)
    }

    func queuePlantingAnimation(for plantID: UUID) {
        gardenScene?.queuePlantingAnimation(for: plantID)
    }

    func setSceneActive(_ isActive: Bool) {
        gardenScene?.isPaused = !isActive
    }

    func showFeedback(text: String, color: UIColor, at position: GridPosition) {
        gardenScene?.showFeedback(text: text, color: color, at: position)
    }

    func refreshEnvironment() {
        gardenScene?.refreshEnvironment()
    }

    func emit(_ event: GardenSceneEvent) {
        onEvent?(event)
    }
}

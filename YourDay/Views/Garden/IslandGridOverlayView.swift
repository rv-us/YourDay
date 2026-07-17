//
//  IslandGridOverlayView.swift
//  YourDay
//

import SwiftUI

struct IslandGridOverlayView: View {
    let playerStats: PlayerStats
    @Binding var isFertilizerModeActive: Bool
    @Binding var isSellModeActive: Bool
    @Binding var plantFeedbackItems: [UUID: PlantActionFeedback]
    @Binding var draggedPlant: PlacedPlant?
    let isTutorialActive: Bool
    let currentTutorialStep: TutorialStep

    // Action callbacks
    var onEmptyTileTap: (GridPosition) -> Void
    var onWaterAction: (Int) -> Void
    var onSellAction: (PlacedPlant) -> Void
    var onFertilizeAction: (PlacedPlant) -> Void
    var onTapInSellModeAction: (PlacedPlant) -> Void
    var onInfoAction: (PlacedPlant) -> Void
    var onAlertAction: (String, String) -> Void

    let firebaseManager: FirebaseManager

    // MARK: - Dev Mode State
    @State private var devDragOffset: CGSize = .zero
    @State private var devLastDragOffset: CGSize = .zero
    @State private var deletedPositions: Set<String> = []   // "x,y" keys

    var body: some View {
        if IslandGridConfig.devMode {
            devModeBody
        } else {
            normalModeBody
        }
    }

    // MARK: - Normal Mode

    private var normalModeBody: some View {
        let unlockedPositions = IslandGridConfig.unlockedPositions(count: playerStats.numberOfOwnedPlots)
        let tileSize = IslandGridConfig.displayTileSize

        return ZStack {
            ForEach(Array(unlockedPositions.enumerated()), id: \.element) { _, position in
                let mapPos = IslandGridConfig.mapPosition(for: position)

                if let plantIndex = playerStats.placedPlants.firstIndex(where: { $0.position == position }) {
                    let plant = playerStats.placedPlants[plantIndex]

                    PlantPlotView(
                        plant: plant,
                        feedbackItem: $plantFeedbackItems[plant.id],
                        isFertilizerModeActive: $isFertilizerModeActive,
                        isSellModeActive: $isSellModeActive,
                        onWaterAction: { onWaterAction(plantIndex) },
                        onSellAction: { onSellAction(plant) },
                        onFertilizeAction: { onFertilizeAction(plant) },
                        onTapInSellModeAction: { onTapInSellModeAction(plant) },
                        onInfoAction: { onInfoAction(plant) }
                    )
                    .frame(width: tileSize.width, height: tileSize.height)
                    .onDrag {
                        self.draggedPlant = plant
                        return NSItemProvider(object: plant.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: GardenDropDelegate(
                        targetPlant: plant,
                        draggedPlant: $draggedPlant,
                        placedPlants: Binding(
                            get: { playerStats.placedPlants },
                            set: { playerStats.placedPlants = $0 }
                        ),
                        playerStats: playerStats,
                        firebaseManager: firebaseManager
                    ))
                    .position(mapPos)
                    .allowsHitTesting(
                        !isTutorialActive ||
                        (currentTutorialStep == .explainFertilizer && !plant.isFullyGrown) ||
                        (currentTutorialStep == .explainSell && plant.isFullyGrown) ||
                        currentTutorialStep == .explainPlanting
                    )
                } else {
                    islandEmptyTile(position: position, tileSize: tileSize)
                        .position(mapPos)
                        .allowsHitTesting(!isTutorialActive || currentTutorialStep == .explainPlanting)
                }
            }
        }
    }

    // MARK: - Dev Mode

    private var devModeBody: some View {
        let allPositions = IslandGridConfig.allGridPositions
        let tileSize = IslandGridConfig.displayTileSize

        return ZStack {
            // All grid tiles (map-space coordinates — parent transform handles zoom/pan)
            ForEach(allPositions, id: \.self) { position in
                let key = devKey(for: position)
                let isDeleted = deletedPositions.contains(key)
                let basePos = IslandGridConfig.mapPosition(for: position)
                let mapPos = CGPoint(
                    x: basePos.x + devDragOffset.width,
                    y: basePos.y + devDragOffset.height
                )

                devTileView(position: position, isDeleted: isDeleted, tileSize: tileSize)
                    .position(mapPos)
            }

            // Print button at top-left of screen
            VStack {
                HStack {
                    Button(action: printDevGridLayout) {
                        Text("Print Grid Layout")
                            .font(.caption.bold())
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 60)
            .padding(.leading, 16)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    devDragOffset = CGSize(
                        width: devLastDragOffset.width + value.translation.width,
                        height: devLastDragOffset.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    devLastDragOffset = devDragOffset
                    printDevGridLayout()
                }
        )
    }

    // MARK: - Dev Tile View

    @ViewBuilder
    private func devTileView(position: GridPosition, isDeleted: Bool, tileSize: CGSize) -> some View {
        let tileW = tileSize.width * 0.92
        let tileH = tileSize.height * 0.92

        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(isDeleted ? Color.red.opacity(0.15) : Color.green.opacity(0.25))
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isDeleted ? Color.red.opacity(0.4) : Color.white.opacity(0.6),
                    lineWidth: 1
                )
            Text("(\(position.x),\(position.y))")
                .font(.system(size: max(8, min(tileW, tileH) * 0.28), weight: .bold, design: .monospaced))
                .foregroundColor(isDeleted ? Color.red.opacity(0.5) : .white)
        }
        .frame(width: tileW, height: tileH)
        .opacity(isDeleted ? 0.4 : 1.0)
        .onTapGesture {
            let key = devKey(for: position)
            if deletedPositions.contains(key) {
                deletedPositions.remove(key)
            } else {
                deletedPositions.insert(key)
            }
            printDevGridLayout()
        }
    }

    // MARK: - Dev Helpers

    private func devKey(for pos: GridPosition) -> String {
        "\(pos.x),\(pos.y)"
    }

    private func printDevGridLayout() {
        let allPositions = IslandGridConfig.allGridPositions

        let active = allPositions.filter { !deletedPositions.contains(devKey(for: $0)) }
        let deleted = allPositions.filter { deletedPositions.contains(devKey(for: $0)) }

        let activeStr = active.map { "(\($0.x),\($0.y))" }.joined(separator: ", ")
        let deletedStr = deleted.map { "(\($0.x),\($0.y))" }.joined(separator: ", ")

        print("─────────────────────────────────────────────")
        print("[DEV GRID] Offset: (dx: \(devDragOffset.width), dy: \(devDragOffset.height))")
        print("[DEV GRID] Active tiles (\(active.count)): [\(activeStr)]")
        print("[DEV GRID] Deleted tiles (\(deleted.count)): [\(deletedStr)]")
        print("─────────────────────────────────────────────")
    }

    // MARK: - Normal Empty Tile

    @ViewBuilder
    private func islandEmptyTile(position: GridPosition, tileSize: CGSize) -> some View {
        EmptyTileView(tileSize: tileSize)
            .onTapGesture {
                if isTutorialActive && currentTutorialStep == .explainPlanting {
                    onEmptyTileTap(position)
                } else if !isTutorialActive && !isFertilizerModeActive && !isSellModeActive {
                    onEmptyTileTap(position)
                } else if isFertilizerModeActive {
                    onAlertAction("Empty Plot", "Select a plant to use fertilizer on.")
                } else if isSellModeActive {
                    onAlertAction("Empty Plot", "Select a grown plant to sell.")
                }
            }
    }
}

// MARK: - Empty Tile View with Enhanced Visibility

struct EmptyTileView: View {
    let tileSize: CGSize

    var body: some View {
        let w = tileSize.width * 0.92
        let h = tileSize.height * 0.92
        let badgeSize = min(tileSize.width, tileSize.height) * 0.32
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        ZStack {
            // Tilled soil base
            shape.fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.62, green: 0.44, blue: 0.27).opacity(0.92),
                        Color(red: 0.42, green: 0.28, blue: 0.16).opacity(0.94)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Soft depression toward the middle so the plot reads as dug earth
            shape.fill(
                RadialGradient(
                    colors: [Color.black.opacity(0.22), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(w, h) * 0.6
                )
            )

            // Furrow rows
            VStack(spacing: h * 0.16) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(Color.black.opacity(0.14))
                        .frame(height: max(1.5, h * 0.045))
                        .padding(.horizontal, w * 0.14)
                }
            }

            // Top light catch
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.5
            )

            // Dashed planting guide
            shape
                .strokeBorder(
                    Color(red: 0.30, green: 0.20, blue: 0.11).opacity(0.9),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .padding(2)

            // Plus badge
            ZStack {
                Circle().fill(Color.white.opacity(0.30))
                Circle().strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                Image(systemName: "plus")
                    .font(.system(size: badgeSize * 0.55, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: badgeSize, height: badgeSize)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: w, height: h)
        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

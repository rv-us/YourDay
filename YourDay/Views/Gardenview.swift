//
//  GardenView.swift
//  YourDay
//
//  Created by Rachit Verma on 5/8/25.
//

import SwiftUI
import SwiftData

// Wrapper to make GridPosition identifiable for the .sheet(item:...) modifier
struct IdentifiableGridPositionWrapper: Identifiable {
    let id = UUID()
    let position: GridPosition
}

// MARK: - Notification Structures
struct PlantActionFeedback: Identifiable {
    let id = UUID()
    var text: String
    var color: Color = .yellow
    var yOffset: CGFloat = 0
    var opacity: Double = 1.0
    var creationDate: Date = Date()
}

struct GeneralNotificationFeedback: Identifiable {
    let id = UUID()
    var text: String
    var icon: String? = nil
    var color: Color = .blue
    var opacity: Double = 1.0
    var scale: CGFloat = 1.0
}


struct GardenView: View {
    @Environment(\.modelContext) private var context
    
    @Query(filter: #Predicate<PlayerStats> { _ in true } ) private var playerStatsList: [PlayerStats]
    
    @State private var showingStandardAlert = false
    @State private var standardAlertTitle = ""
    @State private var standardAlertMessage = ""
    
    @State private var showingShopView = false
    @State private var showingInventoryView = false
    
    @State private var plantingSheetItem: IdentifiableGridPositionWrapper? = nil

    @State private var showWateringEffect = false

    // MARK: - Mode States
    @State private var isFertilizerModeActive = false
    @State private var isSellModeActive = false

    // MARK: - Notification States
    @State private var plantFeedbackItems: [UUID: PlantActionFeedback] = [:]

    @State private var generalNotification: GeneralNotificationFeedback? = nil
    
    @State private var hasShownFertilizerModeAlert = false
    @State private var hasShownSellModeAlert = false


    private var playerStats: PlayerStats {
        playerStatsList.first ?? PlayerStats()
    }

    private var currentSeason: PlantTheme? {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .fall
        case 12, 1, 2: return .winter
        default: return nil
        }
    }
    
    private var allPlantsWateredOrGrownToday: Bool {
        guard !playerStats.placedPlants.isEmpty else { return true }
        let today = Calendar.current.startOfDay(for: Date())
        for plant in playerStats.placedPlants {
            if !plant.isFullyGrown && (plant.lastWateredOnDay == nil || !Calendar.current.isDate(plant.lastWateredOnDay!, inSameDayAs: today)) {
                return false
            }
        }
        return true
    }
    
    private var hasGrownPlantsToSell: Bool {
        playerStats.placedPlants.contains { $0.isFullyGrown }
    }


    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 10) {
                    currentSeasonDisplay
                    plotInfoAndPurchaseSection
                    gardenGridSection
                    Spacer()
                    actionButtonsSection
                }
                // .navigationTitle("My Garden") // REMOVED as per request
                .toolbar { gardenToolbarContent }
                .onAppear(perform: ensurePlayerStatsExists)
                .alert(standardAlertTitle, isPresented: $showingStandardAlert) {
                    Button("OK") {}
                } message: {
                    Text(standardAlertMessage)
                }
                .sheet(isPresented: $showingShopView) {
                    ShopView().environment(\.modelContext, context)
                }
                .sheet(isPresented: $showingInventoryView) {
                    InventoryView(
                        isPlantingMode: false,
                        onPlantSelected: nil
                    )
                    .environment(\.modelContext, context)
                }
                .sheet(item: $plantingSheetItem) { itemWrapper in
                    InventoryView(
                        isPlantingMode: true,
                        onPlantSelected: { selectedBlueprintID in
                            plantSelectedPlantFromInventory(blueprintID: selectedBlueprintID, positionToPlantAt: itemWrapper.position)
                        }
                    )
                    .environment(\.modelContext, context)
                }
                
                if showWateringEffect {
                    Color.blue.opacity(0.3).edgesIgnoringSafeArea(.all)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation { showWateringEffect = false }
                            }
                        }
                }

                if let notification = generalNotification {
                    GeneralNotificationView(notification: notification)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    self.generalNotification = nil
                                }
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - UI Sections

    private var currentSeasonDisplay: some View {
        Group {
            if let season = currentSeason {
                Text("Current Season: \(season.rawValue)")
                    .font(.headline)
                    .foregroundColor(seasonColor(season))
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            } else {
                EmptyView()
            }
        }
    }
    
    private var plotInfoAndPurchaseSection: some View {
        VStack {
            Text("Plots: \(playerStats.numberOfOwnedPlots) / \(playerStats.maxPlotsForCurrentLevel)")
                .font(.subheadline).foregroundColor(.secondary)
            
            if playerStats.numberOfOwnedPlots < playerStats.maxPlotsForCurrentLevel {
                Button(action: attemptToBuyPlot) {
                    Text("Buy New Plot (\(Int(playerStats.costToBuyNextPlot())) Points)")
                        .font(.callout).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(playerStats.totalPoints >= playerStats.costToBuyNextPlot() ? Color.blue : Color.gray.opacity(0.5))
                        .foregroundColor(.white).cornerRadius(8)
                }
                .disabled((playerStats.totalPoints < playerStats.costToBuyNextPlot()) || isSellModeActive || isFertilizerModeActive)
            } else {
                Text("Max plots for current level reached.").font(.callout).foregroundColor(.gray)
            }
        }.padding(.top)
    }

    private var gardenGridSection: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 85, maximum: 100))], spacing: 12) {
                ForEach(0..<playerStats.numberOfOwnedPlots, id: \.self) { index in
                    let currentPosition = GridPosition(x: index, y: 0)
                    
                    if let plantIndexInStats = playerStats.placedPlants.firstIndex(where: { $0.position == currentPosition }) {
                        if plantIndexInStats < playerStats.placedPlants.count {
                            let plant = playerStats.placedPlants[plantIndexInStats]
                            PlantPlotView(
                                plant: plant,
                                feedbackItem: $plantFeedbackItems[plant.id],
                                isFertilizerModeActive: $isFertilizerModeActive,
                                isSellModeActive: $isSellModeActive,
                                onWaterAction: { waterSinglePlant(at: plantIndexInStats) },
                                onSellAction: {
                                    triggerPlantFeedback(plantID: plant.id, text: "+\(Int(plant.baseValue * 1.5))P", color: .green)
                                    sellSinglePlant(plantId: plant.id)
                                },
                                onFertilizeAction: {
                                    attemptToFertilize(plant: plant)
                                },
                                onTapInSellModeAction: {
                                    if plant.isFullyGrown {
                                        triggerPlantFeedback(plantID: plant.id, text: "+\(Int(plant.baseValue * 1.5))P", color: .green)
                                        sellSinglePlant(plantId: plant.id)
                                    } else {
                                        showStandardAlert(title: "Not Grown", message: "\(plant.name) is not fully grown and cannot be sold yet.")
                                    }
                                }
                            )
                        }
                    } else {
                        EmptyPlotIconView(plotIndex: index)
                            .onTapGesture {
                                if isFertilizerModeActive {
                                    showStandardAlert(title: "Empty Plot", message: "Select a plant to use fertilizer on.")
                                } else if isSellModeActive {
                                     showStandardAlert(title: "Empty Plot", message: "Select a grown plant to sell.")
                                } else {
                                    self.plantingSheetItem = IdentifiableGridPositionWrapper(position: currentPosition)
                                }
                            }
                    }
                }
            }
            .padding()
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 10) {
            waterAllButton
            HStack(spacing: 10) {
                sellModeButton
                useFertilizerButton
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var waterAllButton: some View {
        Button(action: waterAllPlants) {
            HStack {
                Image(systemName: "cloud.rain.fill")
                Text("Water All Plants")
            }
            .font(.headline).padding().frame(maxWidth: .infinity)
            .background(allPlantsWateredOrGrownToday ? Color.gray.opacity(0.7) : Color.cyan.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(10).shadow(radius: 3)
        }
        .disabled(allPlantsWateredOrGrownToday || isSellModeActive || isFertilizerModeActive)
    }

    private var sellModeButton: some View {
        Button(action: toggleSellMode) {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                Text(isSellModeActive ? "Cancel Selling" : "Sell Plants")
            }
            .font(.callout).padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
            .frame(maxWidth: .infinity)
            .background(isSellModeActive ? Color.red.opacity(0.8) : (hasGrownPlantsToSell ? Color.green.opacity(0.8) : Color.gray.opacity(0.5)))
            .foregroundColor(.white)
            .cornerRadius(10).shadow(radius: 2)
        }
        .disabled((!hasGrownPlantsToSell && !isSellModeActive) || isFertilizerModeActive)
    }

    private var useFertilizerButton: some View {
        Button(action: toggleFertilizerMode) {
            HStack {
                Image(systemName: "leaf.arrow.triangle.circlepath")
                Text(isFertilizerModeActive ? "Cancel Fertilizing" : "Use Fertilizer (\(playerStats.fertilizerCount))")
            }
            .font(.callout).padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
            .frame(maxWidth: .infinity)
            .background(isFertilizerModeActive ? Color.orange.opacity(0.8) : (playerStats.fertilizerCount > 0 ? Color.purple.opacity(0.7) : Color.gray.opacity(0.5)))
            .foregroundColor(.white)
            .cornerRadius(10).shadow(radius: 2)
        }
        .disabled((playerStats.fertilizerCount == 0 && !isFertilizerModeActive) || isSellModeActive)
    }

    // MARK: - Toolbar Content Definition
    @ToolbarContentBuilder
    private var gardenToolbarContent: some ToolbarContent {
        // Leading items (Level and Garden Value)
        ToolbarItem(placement: .navigationBarLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Level: \(playerStats.playerLevel)")
                    .font(.headline)
                    .foregroundColor(.blue)
                Text("Value: \(Int(playerStats.gardenValue))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        
        // Trailing items (Inventory, Shop, Points)
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Inventory Button
            Button {
                if isSellModeActive || isFertilizerModeActive { return }
                showingInventoryView = true
            } label: {
                Image(systemName: "briefcase.fill")
                    .font(.title3)
            }
            .disabled(isSellModeActive || isFertilizerModeActive)

            // Shop Button
            Button {
                if isSellModeActive || isFertilizerModeActive { return }
                showingShopView = true
            } label: {
                Image(systemName: "cart.fill")
                    .font(.title2)
            }
            .padding(.trailing, 5)
            .disabled(isSellModeActive || isFertilizerModeActive)
            
            Spacer() // Pushes points display to the far right

            // Points Display HStack - MODIFIED to match old formatting
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(.orange) // Font modifier removed from Image
                Text("\(Int(playerStats.totalPoints))")
                    .font(.headline)
                    .foregroundColor(.orange)
                // .id() and .padding() removed from HStack
            }
        }
    }

    // MARK: - Methods
    
    func showStandardAlert(title: String, message: String) {
        standardAlertTitle = title
        standardAlertMessage = message
        showingStandardAlert = true
    }

    func triggerPlantFeedback(plantID: UUID, text: String, color: Color = .yellow) {
        plantFeedbackItems.removeValue(forKey: plantID)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            var newItem = PlantActionFeedback(text: text, color: color)
            plantFeedbackItems[plantID] = newItem

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if plantFeedbackItems[plantID]?.id == newItem.id {
                    plantFeedbackItems.removeValue(forKey: plantID)
                }
            }
        }
    }
    
    func triggerGeneralNotification(text: String, icon: String? = nil, color: Color = .blue) {
        withAnimation(.spring()) {
            generalNotification = GeneralNotificationFeedback(text: text, icon: icon, color: color)
        }
    }


    func ensurePlayerStatsExists() {
        if playerStatsList.isEmpty {
            let newStats = PlayerStats(); context.insert(newStats)
        }
    }

    func attemptToBuyPlot() {
        guard !isFertilizerModeActive && !isSellModeActive else {
            showStandardAlert(title: "Mode Active", message: "Please exit the current mode (Fertilizer/Sell) before buying plots.")
            return
        }
        guard let mutablePlayerStats = playerStatsList.first else { return }
        let cost = mutablePlayerStats.costToBuyNextPlot()
        if mutablePlayerStats.numberOfOwnedPlots < mutablePlayerStats.maxPlotsForCurrentLevel {
            if mutablePlayerStats.totalPoints >= cost {
                if mutablePlayerStats.buyNextPlot() {
                    showStandardAlert(title: "Plot Purchased!", message: "You now have \(mutablePlayerStats.numberOfOwnedPlots) plots.")
                }
            } else {
                showStandardAlert(title: "Not Enough Points", message: "Need \(Int(cost)) points to buy a new plot.")
            }
        } else {
            showStandardAlert(title: "Max Plots Reached", message: "You've reached the maximum number of plots for your current level.")
        }
    }
    
    func waterAllPlants() {
        guard let mutablePlayerStats = playerStatsList.first else { return }
        var wateredCount = 0
        var potentiallyGrownPlant = false

        for i in mutablePlayerStats.placedPlants.indices {
            guard i < mutablePlayerStats.placedPlants.count else { continue }
            var plantToWater = mutablePlayerStats.placedPlants[i]
            
            if !plantToWater.isFullyGrown &&
               (plantToWater.lastWateredOnDay == nil || !Calendar.current.isDate(plantToWater.lastWateredOnDay!, inSameDayAs: Calendar.current.startOfDay(for: Date()))) {
                
                plantToWater.waterPlant()
                mutablePlayerStats.placedPlants[i] = plantToWater
                wateredCount += 1
                
                if plantToWater.isFullyGrown {
                    potentiallyGrownPlant = true
                     triggerPlantFeedback(plantID: plantToWater.id, text: "Grown!", color: .cyan)
                }
            }
        }
        
        if wateredCount > 0 {
            withAnimation { showWateringEffect = true }
        } else {
            showStandardAlert(title: "All Set!", message: "Your plants are either fully grown or already watered for today.")
        }
        
        if wateredCount > 0 || potentiallyGrownPlant {
             mutablePlayerStats.updateGardenValue()
        }
    }
    
    func waterSinglePlant(at plantIndexInStatsArray: Int) {
        guard let mutablePlayerStats = playerStatsList.first,
              plantIndexInStatsArray < mutablePlayerStats.placedPlants.count else { return }
        
        var plantToWater = mutablePlayerStats.placedPlants[plantIndexInStatsArray]

        if !plantToWater.isFullyGrown &&
           (plantToWater.lastWateredOnDay == nil || !Calendar.current.isDate(plantToWater.lastWateredOnDay!, inSameDayAs: Calendar.current.startOfDay(for: Date()))) {
            
            let wasGrownBeforeWatering = plantToWater.isFullyGrown
            plantToWater.waterPlant()
            mutablePlayerStats.placedPlants[plantIndexInStatsArray] = plantToWater
            
            withAnimation { showWateringEffect = true }

            if !wasGrownBeforeWatering && plantToWater.isFullyGrown {
                mutablePlayerStats.updateGardenValue()
                triggerPlantFeedback(plantID: plantToWater.id, text: "Grown!", color: .cyan)
            }

        } else if plantToWater.isFullyGrown {
             // No feedback needed
        } else {
             // No feedback needed
        }
    }

    func sellSinglePlant(plantId: UUID) {
        guard let mutablePlayerStats = playerStatsList.first else { return }
        
        let plantName = mutablePlayerStats.placedPlants.first(where: { $0.id == plantId })?.name ?? "Plant"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let currentStats = self.playerStatsList.first else { return }

            if currentStats.sellPlant(plantId: plantId) {
                if self.isSellModeActive && !currentStats.placedPlants.contains(where: { $0.isFullyGrown }) {
                    self.isSellModeActive = false
                    self.showStandardAlert(title: "All Grown Plants Sold", message: "Sell mode deactivated.")
                }
            } else {
                self.showStandardAlert(title: "Cannot Sell", message: "\(plantName) could not be sold (it might no longer be eligible).")
            }
        }
    }
    
    func plantSelectedPlantFromInventory(blueprintID: String, positionToPlantAt: GridPosition) {
        defer {
            self.plantingSheetItem = nil
        }

        guard let mutablePlayerStats = playerStatsList.first,
              let blueprint = PlantLibrary.blueprint(withId: blueprintID) else {
            showStandardAlert(title: "Planting Error", message: "Could not get plant details.")
            return
        }

        if mutablePlayerStats.placedPlants.contains(where: { $0.position == positionToPlantAt }) {
            showStandardAlert(title: "Plot Occupied", message: "This plot was just taken. Please try another empty plot.")
            return
        }

        if let currentQuantity = mutablePlayerStats.unplacedPlantsInventory[blueprintID], currentQuantity > 0 {
            let newPlant = PlacedPlant(
                name: blueprint.name,
                position: positionToPlantAt,
                initialDaysToGrow: blueprint.initialDaysToGrow,
                rarity: blueprint.rarity,
                theme: blueprint.theme,
                baseValue: blueprint.baseValue,
                assetName: blueprint.assetName,
                iconName: blueprint.iconName
            )
            mutablePlayerStats.placedPlants.append(newPlant)
            
            mutablePlayerStats.unplacedPlantsInventory[blueprintID]? -= 1
            if mutablePlayerStats.unplacedPlantsInventory[blueprintID] ?? 0 <= 0 {
                mutablePlayerStats.unplacedPlantsInventory.removeValue(forKey: blueprintID)
            }
            
            mutablePlayerStats.updateGardenValue()
            triggerGeneralNotification(text: "\(blueprint.name) Planted!", icon: "plus.circle.fill", color: .green)

        } else {
            showStandardAlert(title: "Out of Stock", message: "You don't have any \(blueprint.name) left in your inventory to plant.")
        }
    }
    
    private func seasonColor(_ season: PlantTheme) -> Color {
        switch season {
        case .spring: return .green
        case .summer: return .orange
        case .fall: return .red
        case .winter: return .blue
        }
    }

    // MARK: - Mode Toggling Methods

    func toggleFertilizerMode() {
        if isFertilizerModeActive {
            isFertilizerModeActive = false
        } else {
            if playerStats.fertilizerCount > 0 {
                isFertilizerModeActive = true
                isSellModeActive = false
                if !hasShownFertilizerModeAlert {
                    showStandardAlert(title: "Fertilizer Mode Active", message: "Tap on a plant that is not fully grown to use fertilizer. Tap the button again to cancel.")
                    hasShownFertilizerModeAlert = true
                }
            } else {
                showStandardAlert(title: "No Fertilizer", message: "You don't have any fertilizer to use.")
            }
        }
    }
    
    func toggleSellMode() {
        if isSellModeActive {
            isSellModeActive = false
        } else {
            if hasGrownPlantsToSell {
                isSellModeActive = true
                isFertilizerModeActive = false
                if !hasShownSellModeAlert {
                    showStandardAlert(title: "Sell Mode Active", message: "Tap on a fully grown plant to sell it. Tap the button again to cancel.")
                    hasShownSellModeAlert = true
                }
            } else {
                showStandardAlert(title: "No Grown Plants", message: "You don't have any fully grown plants to sell.")
            }
        }
    }

    func attemptToFertilize(plant: PlacedPlant) {
        guard let mutablePlayerStats = playerStatsList.first else { return }
        
        if !isFertilizerModeActive {
            return
        }

        triggerPlantFeedback(plantID: plant.id, text: "Grown!", color: .purple)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let result = mutablePlayerStats.useFertilizer(onPlantID: plant.id)
            
            if !result.success {
                self.plantFeedbackItems.removeValue(forKey: plant.id)
                self.showStandardAlert(title: "Fertilizer Failed", message: result.message)
            } else {
                if mutablePlayerStats.fertilizerCount == 0 {
                    self.isFertilizerModeActive = false
                    self.showStandardAlert(title: "Out of Fertilizer", message: "You've used your last fertilizer. Fertilizer mode deactivated.")
                }
            }
        }
    }
}

// MARK: - Subviews

struct GeneralNotificationView: View {
    let notification: GeneralNotificationFeedback
    @State private var opacity: Double = 0.0
    @State private var scale: CGFloat = 0.8

    var body: some View {
        HStack(spacing: 10) {
            if let iconName = notification.icon {
                Image(systemName: iconName)
                    .foregroundColor(notification.color)
            }
            Text(notification.text)
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(10)
        .shadow(radius: 5)
        .opacity(opacity)
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.interpolatingSpring(stiffness: 170, damping: 15).delay(0.1)) {
                opacity = 1.0
                scale = 1.0
            }
        }
    }
}


struct EmptyPlotIconView: View {
    let plotIndex: Int
    var body: some View {
        RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.2))
            .frame(minHeight: 80, maxHeight: 100).aspectRatio(1, contentMode: .fit)
            .overlay( VStack {
                Text("Plot \(plotIndex + 1)").font(.caption2).foregroundColor(.secondary)
                Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.green.opacity(0.7))
            })
    }
}

struct PlantPlotView: View {
    let plant: PlacedPlant
    @Binding var feedbackItem: PlantActionFeedback?
    
    @Binding var isFertilizerModeActive: Bool
    @Binding var isSellModeActive: Bool
    
    let onWaterAction: () -> Void
    let onSellAction: () -> Void
    let onFertilizeAction: () -> Void
    let onTapInSellModeAction: () -> Void

    @State private var showingContextMenu = false
    
    @State private var localFeedbackText: String?
    @State private var localFeedbackColor: Color = .yellow
    @State private var localFeedbackOpacity: Double = 0.0
    @State private var localFeedbackYOffset: CGFloat = 0


    var body: some View {
        VStack(spacing: 2) {
            currentPlantVisual()
                .frame(minHeight: 60, maxHeight: 80)
                .aspectRatio(1, contentMode: .fit)
                .cornerRadius(8)
                .padding(.top, 2)
                .overlay(
                    Group {
                        if isFertilizerModeActive && !plant.isFullyGrown {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.purple, lineWidth: 3)
                                .opacity(0.7)
                        } else if isSellModeActive && plant.isFullyGrown {
                             RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.green, lineWidth: 3)
                                .opacity(0.7)
                                .overlay(
                                    Image(systemName: "dollarsign.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(Color.green.opacity(0.9))
                                        .padding(5)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                )
                        }
                    }
                )
                .overlay(
                    Group {
                        if let text = localFeedbackText {
                            Text(text)
                                .font(.caption.weight(.bold))
                                .foregroundColor(localFeedbackColor)
                                .padding(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
                                .background(.ultraThinMaterial)
                                .cornerRadius(5)
                                .shadow(radius: 2)
                                .offset(y: localFeedbackYOffset)
                                .opacity(localFeedbackOpacity)
                        }
                    }
                )


            VStack(alignment: .center, spacing: 1) {
                Text(plant.name).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                if plant.isFullyGrown {
                    Text("Grown!").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 3).padding(.vertical, 1).background(Color.green.opacity(0.9)).cornerRadius(3)
                } else {
                    Text("\(plant.daysLeftTillFullyGrown)d left").font(.system(size: 8))
                        .foregroundColor(plant.lastWateredOnDay != nil && Calendar.current.isDateInToday(plant.lastWateredOnDay!) ? .gray.opacity(0.8) : .orange)
                }
            }.padding(.bottom, 3)
        }
        .frame(minHeight: 80, maxHeight: 100)
        .background(plotBackgroundColor())
        .cornerRadius(10)
        .onTapGesture {
            if isFertilizerModeActive {
                if !plant.isFullyGrown {
                    onFertilizeAction()
                }
            } else if isSellModeActive {
                if plant.isFullyGrown {
                    onTapInSellModeAction()
                }
            }
        }
        .onLongPressGesture {
            if !isFertilizerModeActive && !isSellModeActive {
                if plant.isFullyGrown {
                    showingContextMenu = true
                } else if !plant.isFullyGrown && !(plant.lastWateredOnDay != nil && Calendar.current.isDateInToday(plant.lastWateredOnDay!)) {
                    showingContextMenu = true
                }
            }
        }
        .confirmationDialog("Plant Options: \(plant.name)", isPresented: $showingContextMenu, titleVisibility: .visible) {
            if !isFertilizerModeActive && !isSellModeActive {
                if !plant.isFullyGrown && !(plant.lastWateredOnDay != nil && Calendar.current.isDateInToday(plant.lastWateredOnDay!)) {
                    Button("Water Plant") { onWaterAction() }
                }
                
                if plant.isFullyGrown {
                    Button("Sell Plant (\(Int(plant.baseValue * 1.5)) Points)", role: .destructive) { onSellAction() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onChange(of: feedbackItem?.id) { oldValue, newValue in
            if let newFeedback = feedbackItem {
                localFeedbackText = newFeedback.text
                localFeedbackColor = newFeedback.color
                localFeedbackYOffset = newFeedback.yOffset
                localFeedbackOpacity = newFeedback.opacity

                withAnimation(.easeOut(duration: 0.3)) {
                    localFeedbackYOffset = -30
                }
                withAnimation(.easeOut(duration: 1.0).delay(0.2)) {
                    localFeedbackOpacity = 0.0
                }
            }
        }
    }
    
    @ViewBuilder
    private func currentPlantVisual() -> some View {
        if plant.isFullyGrown {
            PlantVisualDisplayView(assetName: plant.assetName, rarity: plant.rarity, displayName: plant.name, isIcon: false)
        } else if plant.daysLeftTillFullyGrown <= plant.initialDaysToGrow / 2 && plant.initialDaysToGrow > 1 {
             Image(systemName: "leaf.fill")
                .resizable().scaledToFit().foregroundColor(.green).padding(15)
        } else {
            Image(systemName: "circle.dotted")
                .resizable().scaledToFit().foregroundColor(Color.brown.opacity(0.7)).padding(25)
        }
    }
    
    private func plotBackgroundColor() -> Color {
        if plant.isFullyGrown { return .yellow.opacity(0.25) }
        if !plant.isFullyGrown && (plant.lastWateredOnDay == nil || !Calendar.current.isDateInToday(plant.lastWateredOnDay!)) {
            return Color.blue.opacity(0.15)
        }
        return Color(UIColor.systemGray6).opacity(0.7)
    }
}

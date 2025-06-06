import SwiftUI
import SwiftData
import Lottie

struct VibrantLightTheme {
    static let backgroundGradient = Gradient(colors: [Color(hex: "#A8E063"), Color(hex: "#56AB2F")])
    static let plotBackground = Color(hex: "#F5DEB3") // Wheat
    static let plotNeedsWater = Color(hex: "#D2B48C") // Tan
    static let plotGrown = Color(hex: "#C8E6C9") // Light Green
    static let primaryText = Color(hex: "#2E4600")
    static let secondaryText = Color(hex: "#616161")
    static let accent = Color(hex: "#FFA000")
    static let waterButton = Color(hex: "#29B6F6")
    static let sellButton = Color(hex: "#66BB6A")
    static let fertilizerButton = Color(hex: "#FFA726")
}

struct VibrantDarkTheme {
    static let backgroundGradient = Gradient(colors: [Color(hex: "#0f2027"), Color(hex: "#203a43"), Color(hex: "#2c5364")])
    static let plotBackground = Color(hex: "#5D4037") // Dark Brown
    static let plotNeedsWater = Color(hex: "#795548") // Brown
    static let plotGrown = Color(hex: "#388E3C") // Darker Green
    static let primaryText = Color(hex: "#E0F2F1")
    static let secondaryText = Color(hex: "#BDBDBD")
    static let accent = Color(hex: "#FFC107")
    static let waterButton = Color(hex: "#4FC3F7")
    static let sellButton = Color(hex: "#81C784")
    static let fertilizerButton = Color(hex: "#FFB74D")
}

// Dynamic Colors for Garden View
let vibrantGardenBackground = LinearGradient(gradient: Gradient(colors: [
    Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(VibrantDarkTheme.backgroundGradient.stops[0].color) : UIColor(VibrantLightTheme.backgroundGradient.stops[0].color) }),
    Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(VibrantDarkTheme.backgroundGradient.stops[1].color) : UIColor(VibrantLightTheme.backgroundGradient.stops[1].color) })
]), startPoint: .top, endPoint: .bottom)

let vibrantPlotColor = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(VibrantDarkTheme.plotBackground) : UIColor(VibrantLightTheme.plotBackground) })
let vibrantPlotNeedsWaterColor = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(VibrantDarkTheme.plotNeedsWater) : UIColor(VibrantLightTheme.plotNeedsWater) })
let vibrantPlotGrownColor = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(VibrantDarkTheme.plotGrown) : UIColor(VibrantLightTheme.plotGrown) })

let vibrantPrimaryTextColor = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(VibrantDarkTheme.primaryText) : UIColor(VibrantLightTheme.primaryText) })
let vibrantSecondaryTextColor = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(VibrantDarkTheme.secondaryText) : UIColor(VibrantLightTheme.secondaryText) })

let vibrantWaterButtonColor = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(VibrantDarkTheme.waterButton) : UIColor(VibrantLightTheme.waterButton) })
let vibrantSellButtonColor = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(VibrantDarkTheme.sellButton) : UIColor(VibrantLightTheme.sellButton) })
let vibrantFertilizerButtonColor = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(VibrantDarkTheme.fertilizerButton) : UIColor(VibrantLightTheme.fertilizerButton) })
let vibrantAccentColor = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(VibrantDarkTheme.accent) : UIColor(VibrantLightTheme.accent) })



struct IdentifiableGridPositionWrapper: Identifiable {
    let id = UUID()
    let position: GridPosition
}

struct PlantActionFeedback: Identifiable {
    let id = UUID()
    var text: String
    var color: Color = dynamicSecondaryColor
    var yOffset: CGFloat = 0
    var opacity: Double = 1.0
    var creationDate: Date = Date()
}

struct GeneralNotificationFeedback: Identifiable {
    let id = UUID()
    var text: String
    var icon: String? = nil
    var color: Color = dynamicSecondaryTextColor
    var opacity: Double = 1.0
    var scale: CGFloat = 1.0
}

enum TutorialStep: Int, Identifiable {
    case welcome = 0
    case explainShop
    case explainPlanting
    case explainWatering
    case explainFertilizer
    case explainSell
    case explainPlotsValue
    case finished

    var id: Int { self.rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome to Your Garden!"
        case .explainShop: return "Visit the Shop"
        case .explainPlanting: return "Plant Your Seeds"
        case .explainFertilizer: return "Speed Up Growth"
        case .explainSell: return "Sell Your Plants"
        case .explainPlotsValue: return "Expand & Prosper"
        case .explainWatering: return "Keep Them Hydrated"
        case .finished: return "Tutorial Complete!"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "This is your personal garden. You'll use points earned from your tasks to buy seeds, nurture plants, and watch them grow!"
        case .explainShop:
            return "First, let's get some plants. Tap the Shop icon in the top right to buy plant packs. Hint: Check the current season and try to pull for plants of that theme for a bonus!"
        case .explainPlanting:
            return "Great! Now that you have some plants, tap on an empty plot to open your inventory and choose a plant."
        case .explainFertilizer:
            return "See the 'Use Fertilizer' button? If you have fertilizer, tap this button, then tap a growing plant to make it grow instantly! Convert 10 unplaced plants in your inventory to get 1 fertilizer."
        case .explainSell:
            return "The 'Sell Plants' button allows you to enter sell mode. Tap it, then tap on any fully grown plant to sell it for points."
        case .explainPlotsValue:
            return "As you level up, you can buy more plots to expand your garden. Your garden's 'Value' (top left) increases as your plants grow, especially with seasonal theme bonuses!"
        case .explainWatering:
            return "Don't forget to water your plants using the 'Water All Plants' button or by long-pressing individual plants. They need water daily (in-game) to grow. Neglected plants might wither!"
        case .finished:
            return "You're all set to cultivate a beautiful and valuable garden. Happy planting!"
        }
    }
    
    var iconForMessage: String? {
        switch self {
        case .explainShop: return "cart.fill"
        case .explainPlanting: return "plus.circle.fill"
        case .explainFertilizer: return "leaf.arrow.triangle.circlepath"
        case .explainSell: return "dollarsign.circle.fill"
        case .explainWatering: return "cloud.rain.fill"
        case .explainPlotsValue: return "chart.bar.xaxis"
        default: return nil
        }
    }
    
    var nextButtonText: String {
        switch self {
        case .explainShop: return "Go to Shop"
        case .finished: return "Start Gardening!"
        case .explainPlanting, .explainFertilizer, .explainSell, .explainWatering:
            return "Okay, Got It!"
        default: return "Next Tip"
        }
    }
}

struct GardenView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var loginViewModel: LoginViewModel
    @Query(filter: #Predicate<PlayerStats> { _ in true } ) private var playerStatsList: [PlayerStats]
    @State private var showingStandardAlert = false
    @State private var standardAlertTitle = ""
    @State private var standardAlertMessage = ""
    
    @State private var showingShopView = false
    @State private var showingInventoryView = false
    @State private var showingLeaderboardView = false
    
    @State private var plantingSheetItem: IdentifiableGridPositionWrapper? = nil

    @State private var playWateringAnimation = false

    @State private var isFertilizerModeActive = false
    @State private var isSellModeActive = false

    @State private var plantFeedbackItems: [UUID: PlantActionFeedback] = [:]

    @State private var generalNotification: GeneralNotificationFeedback? = nil
    
    @State private var hasShownFertilizerModeAlert = false
    @State private var hasShownSellModeAlert = false

    @State private var selectedPlantForInfo: PlacedPlant? = nil

    @AppStorage("hasCompletedGardenTutorial_v1") var hasCompletedGardenTutorial: Bool = false
    @State private var isTutorialActive: Bool = false
    @State private var currentTutorialStep: TutorialStep = .welcome
    @State private var wasShopVisitedForTutorial: Bool = false


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
    
    private func checkTutorialStatusAfterShopReturn() {
        if wasShopVisitedForTutorial {
            wasShopVisitedForTutorial = false
            
            guard !playerStatsList.isEmpty else { return }

            let canAffordAnyPlant = playerStats.totalPoints >= 100

            if !playerStats.unplacedPlantsInventory.isEmpty {
                currentTutorialStep = .explainPlanting
                isTutorialActive = true
            } else if !canAffordAnyPlant {
                currentTutorialStep = .explainPlotsValue
                isTutorialActive = true
                showStandardAlert(
                    title: "Out of Points",
                    message: "You don't have enough points to buy plants right now. Earn more points and come back anytime!"
                )
            } else {
                currentTutorialStep = .explainShop
                isTutorialActive = true
                showStandardAlert(
                    title: "Still Need Plants!",
                    message: "It looks like you haven't acquired any plants yet. Please visit the shop to get some seeds or saplings!"
                )
            }
        }
    }


    var body: some View {
        NavigationView {
            ZStack {
                vibrantGardenBackground.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 10) {
                    currentSeasonDisplay
                    plotInfoAndPurchaseSection
                    gardenGridSection
                    Spacer()
                    actionButtonsSection
                }
                .toolbar { gardenToolbarContent }
                .onAppear {
                    ensurePlayerStatsExists()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if !playerStatsList.isEmpty {
                            if !hasCompletedGardenTutorial && !isTutorialActive && !wasShopVisitedForTutorial {
                                currentTutorialStep = .welcome
                                isTutorialActive = true
                            }
                        }
                    }
                }
                .alert(standardAlertTitle, isPresented: $showingStandardAlert) {
                    Button("OK") {}
                } message: {
                    Text(standardAlertMessage)
                }
                .sheet(isPresented: $showingShopView, onDismiss: {
                    if wasShopVisitedForTutorial {
                        checkTutorialStatusAfterShopReturn()
                    }
                }) {
                    ShopView().environment(\.modelContext, context)
                }
                .sheet(isPresented: $showingInventoryView) {
                    InventoryView(isPlantingMode: false, onPlantSelected: nil)
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
                .sheet(item: $selectedPlantForInfo) { plant in
                    PlantInfoView(plant: plant)
                }
                .sheet(isPresented: $showingLeaderboardView) {
                    LeaderboardView()
                }
                
                if playWateringAnimation {
                    LottieView(name: "watering", play: $playWateringAnimation)
                        .edgesIgnoringSafeArea(.all)
                        .background(Color.black.opacity(0.3))
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                        .zIndex(20)
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

                if isTutorialActive && !playerStatsList.isEmpty {
                    TutorialOverlayView(
                        currentStep: $currentTutorialStep,
                        isActive: $isTutorialActive,
                        hasPlantsInInventory: !playerStats.unplacedPlantsInventory.isEmpty,
                        hasCompletedTutorialPreviously: $hasCompletedGardenTutorial,
                        onNavigateToShop: {
                            isTutorialActive = false
                            wasShopVisitedForTutorial = true
                            showingShopView = true
                        },
                        onReturnToGarden: {
                            isTutorialActive = false
                        },
                        onAcknowledgeActionStep: {
                            self.isTutorialActive = false
                        }
                    )
                    .zIndex(10)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var currentSeasonDisplay: some View {
        Group {
            if let season = currentSeason {
                Text("Current Season: \(season.rawValue)")
                    .font(.headline)
                    .foregroundColor(vibrantPrimaryTextColor)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                    .cornerRadius(8)
                    .padding(.horizontal)
            } else { EmptyView() }
        }
        .allowsHitTesting(!isTutorialActive)
    }
    
    private var plotInfoAndPurchaseSection: some View {
        VStack {
            Text("Plots: \(playerStats.numberOfOwnedPlots) / \(playerStats.maxPlotsForCurrentLevel)")
                .font(.subheadline)
                .foregroundColor(vibrantPrimaryTextColor)
            
            if playerStats.numberOfOwnedPlots < playerStats.maxPlotsForCurrentLevel {
                Button(action: attemptToBuyPlot) {
                    Text("Buy New Plot (\(Int(playerStats.costToBuyNextPlot())) Points)")
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(playerStats.totalPoints >= playerStats.costToBuyNextPlot() ? vibrantAccentColor : dynamicSecondaryTextColor.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled((playerStats.totalPoints < playerStats.costToBuyNextPlot()) || isSellModeActive || isFertilizerModeActive || (isTutorialActive && currentTutorialStep != .explainPlotsValue))
            } else {
                Text("Max plots for current level reached.")
                    .font(.callout)
                    .foregroundColor(vibrantSecondaryTextColor)
            }
        }
        .padding(.top)
        .allowsHitTesting(!isTutorialActive || currentTutorialStep == .explainPlotsValue)
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
                                    triggerPlantFeedback(plantID: plant.id, text: "+\(Int(plant.baseValue * 1.5))P", color: vibrantSellButtonColor)
                                    sellSinglePlant(plantId: plant.id)
                                },
                                onFertilizeAction: {
                                    attemptToFertilize(plant: plant)
                                },
                                onTapInSellModeAction: {
                                    if plant.isFullyGrown {
                                        triggerPlantFeedback(plantID: plant.id, text: "+\(Int(plant.baseValue * 1.5))P", color: vibrantSellButtonColor)
                                        sellSinglePlant(plantId: plant.id)
                                    } else {
                                        showStandardAlert(title: "Not Grown", message: "\(plant.name) is not fully grown and cannot be sold yet.")
                                    }
                                },
                                onInfoAction: {
                                    if !isTutorialActive && !isSellModeActive && !isFertilizerModeActive {
                                        self.selectedPlantForInfo = plant
                                    }
                                }
                            )
                            .allowsHitTesting(!isTutorialActive ||
                                             (currentTutorialStep == .explainFertilizer && !plant.isFullyGrown) ||
                                             (currentTutorialStep == .explainSell && plant.isFullyGrown) ||
                                             currentTutorialStep == .explainPlanting
                            )
                        }
                    } else {
                        EmptyPlotIconView(plotIndex: index)
                            .onTapGesture {
                                if isTutorialActive && currentTutorialStep == .explainPlanting {
                                    self.plantingSheetItem = IdentifiableGridPositionWrapper(position: currentPosition)
                                } else if !isTutorialActive && !isFertilizerModeActive && !isSellModeActive {
                                    self.plantingSheetItem = IdentifiableGridPositionWrapper(position: currentPosition)
                                } else if isFertilizerModeActive {
                                    showStandardAlert(title: "Empty Plot", message: "Select a plant to use fertilizer on.")
                                } else if isSellModeActive {
                                    showStandardAlert(title: "Empty Plot", message: "Select a grown plant to sell.")
                                }
                            }
                            .allowsHitTesting(!isTutorialActive || currentTutorialStep == .explainPlanting)
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
            HStack { Image(systemName: "cloud.rain.fill"); Text("Water All Plants") }
            .font(.headline).padding().frame(maxWidth: .infinity)
            .background(allPlantsWateredOrGrownToday ? dynamicSecondaryTextColor.opacity(0.5) : vibrantWaterButtonColor)
            .foregroundColor(.white).cornerRadius(10).shadow(radius: 3)
        }
        .disabled(allPlantsWateredOrGrownToday || isSellModeActive || isFertilizerModeActive || (isTutorialActive && currentTutorialStep != .explainWatering))
    }

    private var sellModeButton: some View {
        Button(action: toggleSellMode) {
            HStack { Image(systemName: "dollarsign.circle.fill"); Text(isSellModeActive ? "Cancel Selling" : "Sell Plants") }
            .font(.callout).padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15)).frame(maxWidth: .infinity)
            .background(isSellModeActive ? dynamicDestructiveColor.opacity(0.8) : (hasGrownPlantsToSell ? vibrantSellButtonColor : dynamicSecondaryTextColor.opacity(0.5)))
            .foregroundColor(.white).cornerRadius(10).shadow(radius: 2)
        }
        .disabled((!hasGrownPlantsToSell && !isSellModeActive) || isFertilizerModeActive || (isTutorialActive && currentTutorialStep != .explainSell))
    }

    private var useFertilizerButton: some View {
        Button(action: toggleFertilizerMode) {
            HStack { Image(systemName: "leaf.arrow.triangle.circlepath"); Text(isFertilizerModeActive ? "Cancel Fertilizing" : "Use Fertilizer (\(playerStats.fertilizerCount))") }
            .font(.callout).padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15)).frame(maxWidth: .infinity)
            .background(isFertilizerModeActive ? dynamicDestructiveColor.opacity(0.8) : (playerStats.fertilizerCount > 0 ? vibrantFertilizerButtonColor : dynamicSecondaryTextColor.opacity(0.5)))
            .foregroundColor(.white).cornerRadius(10).shadow(radius: 2)
        }
        .disabled((playerStats.fertilizerCount == 0 && !isFertilizerModeActive) || isSellModeActive || (isTutorialActive && currentTutorialStep != .explainFertilizer))
    }

    @ToolbarContentBuilder
    private var gardenToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Level: \(playerStats.playerLevel)")
                    .font(.headline)
                    .foregroundColor(vibrantPrimaryTextColor)
                Text("Value: \(Int(playerStats.gardenValue))")
                    .font(.caption)
                    .foregroundColor(vibrantSecondaryTextColor)
            }
            .allowsHitTesting(!isTutorialActive || currentTutorialStep == .explainPlotsValue)
        }
        
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                print("Leaderboard button tapped")
                showingLeaderboardView = true
            } label: {
                Image("Points_icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            }
            .disabled(isSellModeActive || isFertilizerModeActive || isTutorialActive)

            Button {
                if isSellModeActive || isFertilizerModeActive || isTutorialActive { return }
                showingInventoryView = true
            } label: {
                Image("Inventory_icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            }
            .disabled(isSellModeActive || isFertilizerModeActive || isTutorialActive)

            Button {
                if isSellModeActive || isFertilizerModeActive || (isTutorialActive && currentTutorialStep != .explainShop) { return }
                if !(isTutorialActive && currentTutorialStep == .explainShop) { showingShopView = true }
            } label: {
                Image("Shop_icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
            .padding(.trailing, 5)
            .disabled(isSellModeActive || isFertilizerModeActive || (isTutorialActive && currentTutorialStep != .explainShop) )
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(vibrantAccentColor)
                Text("\(Int(playerStats.totalPoints))")
                    .font(.headline)
                    .foregroundColor(vibrantPrimaryTextColor)
            }
        }
    }
    
    func showStandardAlert(title: String, message: String) {
        standardAlertTitle = title; standardAlertMessage = message; showingStandardAlert = true
    }

    func triggerPlantFeedback(plantID: UUID, text: String, color: Color = dynamicSecondaryColor) {
        plantFeedbackItems.removeValue(forKey: plantID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            var newItem = PlantActionFeedback(text: text, color: color)
            plantFeedbackItems[plantID] = newItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if plantFeedbackItems[plantID]?.id == newItem.id {
                    plantFeedbackItems.removeValue(forKey: plantID)
                }
            }
        }
    }
    
    func triggerGeneralNotification(text: String, icon: String? = nil, color: Color = dynamicSecondaryTextColor) {
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
        guard !isFertilizerModeActive && !isSellModeActive && !isTutorialActive else {
            if isTutorialActive { showStandardAlert(title: "Tutorial Active", message: "Please complete or skip the tutorial first.") }
            else { showStandardAlert(title: "Mode Active", message: "Please exit the current mode (Fertilizer/Sell) before buying plots.") }
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
        guard !isTutorialActive || currentTutorialStep == .explainWatering else {
            if isTutorialActive { showStandardAlert(title: "Tutorial Active", message: "Follow the current tutorial step.") }
            return
        }
        guard let mutablePlayerStats = playerStatsList.first else { return }
        var wateredCount = 0; var potentiallyGrownPlant = false
        let today = Calendar.current.startOfDay(for: Date())

        for i in mutablePlayerStats.placedPlants.indices {
            guard i < mutablePlayerStats.placedPlants.count else { continue }
            var plantToWater = mutablePlayerStats.placedPlants[i]
            if !plantToWater.isFullyGrown && (plantToWater.lastWateredOnDay == nil || !Calendar.current.isDate(plantToWater.lastWateredOnDay!, inSameDayAs: today)) {
                plantToWater.waterPlant(); mutablePlayerStats.placedPlants[i] = plantToWater; wateredCount += 1
                if plantToWater.isFullyGrown { potentiallyGrownPlant = true; triggerPlantFeedback(plantID: plantToWater.id, text: "Grown!", color: dynamicSecondaryColor) }
            }
        }
        
        if wateredCount > 0 {
            self.playWateringAnimation = true
        } else {
            showStandardAlert(title: "All Set!", message: "Your plants are either fully grown or already watered for today.")
        }
        
        if wateredCount > 0 || potentiallyGrownPlant {
            mutablePlayerStats.updateGardenValue()
            loginViewModel.syncLocalPlayerStatsToFirestore(playerStatsModel: mutablePlayerStats)
        }

        if !self.hasCompletedGardenTutorial && self.currentTutorialStep == .explainWatering && wateredCount > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.currentTutorialStep = .explainFertilizer
                if self.currentTutorialStep != .finished {
                    withAnimation {
                        self.isTutorialActive = true
                    }
                } else {
                    self.hasCompletedGardenTutorial = true
                    self.isTutorialActive = false
                }
            }
        }
    }
    
    func waterSinglePlant(at plantIndexInStatsArray: Int) {
        guard !isTutorialActive || currentTutorialStep == .explainWatering else {
            if isTutorialActive && currentTutorialStep != .explainWatering {
                showStandardAlert(title: "Tutorial Active", message: "Please use the 'Water All Plants' button as shown in the tutorial.")
            }
            return
        }
        guard let mutablePlayerStats = playerStatsList.first, plantIndexInStatsArray < mutablePlayerStats.placedPlants.count else { return }
        
        var plantToWater = mutablePlayerStats.placedPlants[plantIndexInStatsArray]
        let today = Calendar.current.startOfDay(for: Date())

        if !plantToWater.isFullyGrown && (plantToWater.lastWateredOnDay == nil || !Calendar.current.isDate(plantToWater.lastWateredOnDay!, inSameDayAs: today)) {
            let wasGrownBeforeWatering = plantToWater.isFullyGrown
            plantToWater.waterPlant()
            mutablePlayerStats.placedPlants[plantIndexInStatsArray] = plantToWater
            if !wasGrownBeforeWatering && plantToWater.isFullyGrown { mutablePlayerStats.updateGardenValue(); triggerPlantFeedback(plantID: plantToWater.id, text: "Grown!", color: dynamicSecondaryColor)
                loginViewModel.syncLocalPlayerStatsToFirestore(playerStatsModel: mutablePlayerStats)
            }
            
            if !self.hasCompletedGardenTutorial && self.currentTutorialStep == .explainWatering {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.currentTutorialStep = .explainFertilizer
                    if self.currentTutorialStep != .finished {
                        withAnimation {
                            self.isTutorialActive = true
                        }
                    } else {
                        self.hasCompletedGardenTutorial = true
                        self.isTutorialActive = false
                    }
                }
            }
        } else if plantToWater.isFullyGrown {
            showStandardAlert(title: "Fully Grown", message: "\(plantToWater.name) is already fully grown.")
        } else {
            showStandardAlert(title: "Already Watered", message: "\(plantToWater.name) has been watered today.")
        }
    }

    func sellSinglePlant(plantId: UUID) {
        guard !isTutorialActive || (currentTutorialStep == .explainSell && isSellModeActive) else {
            if isTutorialActive { showStandardAlert(title: "Tutorial Active", message: "Follow the current tutorial step or exit sell mode.") }
            return
        }
        guard let mutablePlayerStats = playerStatsList.first else { return }
        let plantName = mutablePlayerStats.placedPlants.first(where: { $0.id == plantId })?.name ?? "Plant"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let currentStats = self.playerStatsList.first else { return }
            if currentStats.sellPlant(plantId: plantId) {
                currentStats.updateGardenValue()
                self.loginViewModel.syncLocalPlayerStatsToFirestore(playerStatsModel: currentStats)
                if self.isSellModeActive && !currentStats.placedPlants.contains(where: { $0.isFullyGrown }) {
                    self.isSellModeActive = false; self.showStandardAlert(title: "All Grown Plants Sold", message: "Sell mode deactivated.")
                }
                if !self.hasCompletedGardenTutorial && self.currentTutorialStep == .explainSell {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.currentTutorialStep = .explainPlotsValue
                        if self.currentTutorialStep != .finished {
                            withAnimation {
                                self.isTutorialActive = true
                            }
                        } else {
                            self.hasCompletedGardenTutorial = true
                            self.isTutorialActive = false
                        }
                    }
                }
            } else { self.showStandardAlert(title: "Cannot Sell", message: "\(plantName) could not be sold (it might no longer be eligible).") }
        }
    }
    
    func plantSelectedPlantFromInventory(blueprintID: String, positionToPlantAt: GridPosition) {
        defer { self.plantingSheetItem = nil }
        guard let mutablePlayerStats = playerStatsList.first, let blueprint = PlantLibrary.blueprint(withId: blueprintID) else {
            showStandardAlert(title: "Planting Error", message: "Could not get plant details."); return
        }
        if mutablePlayerStats.placedPlants.contains(where: { $0.position == positionToPlantAt }) {
            showStandardAlert(title: "Plot Occupied", message: "This plot was just taken."); return
        }
        if let currentQuantity = mutablePlayerStats.unplacedPlantsInventory[blueprintID], currentQuantity > 0 {
            let newPlant = PlacedPlant(name: blueprint.name, position: positionToPlantAt, initialDaysToGrow: blueprint.initialDaysToGrow, rarity: blueprint.rarity, theme: blueprint.theme, baseValue: blueprint.baseValue, assetName: blueprint.assetName, iconName: blueprint.iconName)
            mutablePlayerStats.placedPlants.append(newPlant)
            mutablePlayerStats.unplacedPlantsInventory[blueprintID]? -= 1
            if mutablePlayerStats.unplacedPlantsInventory[blueprintID] ?? 0 <= 0 { mutablePlayerStats.unplacedPlantsInventory.removeValue(forKey: blueprintID) }
            mutablePlayerStats.updateGardenValue(); triggerGeneralNotification(text: "\(blueprint.name) Planted!", icon: "plus.circle.fill", color: dynamicSecondaryColor)
            loginViewModel.syncLocalPlayerStatsToFirestore(playerStatsModel: mutablePlayerStats)
            if !self.hasCompletedGardenTutorial && self.currentTutorialStep == .explainPlanting {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.currentTutorialStep = .explainWatering
                    if self.currentTutorialStep != .finished {
                        withAnimation {
                            self.isTutorialActive = true
                        }
                    } else {
                        self.hasCompletedGardenTutorial = true
                        self.isTutorialActive = false
                    }
                }
            }
        } else { showStandardAlert(title: "Out of Stock", message: "You don't have any \(blueprint.name) left.") }
    }
    
    private func seasonColor(_ season: PlantTheme) -> Color {
        switch season {
        case .spring: return plantMediumGreen
        case .summer: return plantPeach
        case .fall: return plantPink
        case .winter: return plantDustyBlue
        }
    }

    func toggleFertilizerMode() {
        if isTutorialActive && currentTutorialStep != .explainFertilizer {
            showStandardAlert(title: "Tutorial", message: "Please follow the current tutorial step for fertilizing.")
            return
        }
        if isFertilizerModeActive {
            isFertilizerModeActive = false
        } else {
            if playerStats.fertilizerCount > 0 {
                isFertilizerModeActive = true; isSellModeActive = false
                if !hasShownFertilizerModeAlert {
                    showStandardAlert(title: "Fertilizer Mode Active", message: "Tap on a plant that is not fully grown to use fertilizer. Tap the button again to cancel.");
                    hasShownFertilizerModeAlert = true
                }
            } else { showStandardAlert(title: "No Fertilizer", message: "You don't have any fertilizer to use.") }
        }
    }
    
    func toggleSellMode() {
        if isTutorialActive && currentTutorialStep != .explainSell {
            showStandardAlert(title: "Tutorial", message: "Please follow the current tutorial step for selling.")
            return
        }
        if isSellModeActive {
            isSellModeActive = false
        } else {
            if hasGrownPlantsToSell {
                isSellModeActive = true; isFertilizerModeActive = false
                if !hasShownSellModeAlert {
                    showStandardAlert(title: "Sell Mode Active", message: "Tap on a fully grown plant to sell it. Tap the button again to cancel.");
                    hasShownSellModeAlert = true
                }
            } else { showStandardAlert(title: "No Grown Plants", message: "You don't have any fully grown plants to sell.") }
        }
    }
    
    func attemptToFertilize(plant: PlacedPlant) {
        guard let mutablePlayerStats = playerStatsList.first else { return }
        if !isFertilizerModeActive { return }
        
        let wasTutorialFertilizerStep = !self.hasCompletedGardenTutorial && self.currentTutorialStep == .explainFertilizer && !plant.isFullyGrown
        
        triggerPlantFeedback(plantID: plant.id, text: "Grown!", color: dynamicSecondaryColor)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let result = mutablePlayerStats.useFertilizer(onPlantID: plant.id)
            if !result.success {
                self.plantFeedbackItems.removeValue(forKey: plant.id)
                self.showStandardAlert(title: "Fertilizer Failed", message: result.message)
            } else {
                self.loginViewModel.syncLocalPlayerStatsToFirestore(playerStatsModel: mutablePlayerStats)
                if self.isFertilizerModeActive && (wasTutorialFertilizerStep || mutablePlayerStats.fertilizerCount == 0) {
                    self.isFertilizerModeActive = false
                    if mutablePlayerStats.fertilizerCount == 0 && !wasTutorialFertilizerStep {
                        self.showStandardAlert(title: "Out of Fertilizer", message: "You've used your last fertilizer. Fertilizer mode deactivated.")
                    }
                }

                if wasTutorialFertilizerStep {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.currentTutorialStep = .explainSell
                        if self.currentTutorialStep != .finished {
                            withAnimation {
                                self.isTutorialActive = true
                            }
                        } else {
                            self.hasCompletedGardenTutorial = true
                            self.isTutorialActive = false
                        }
                        self.isFertilizerModeActive = false
                    }
                }
            }
        }
    }
}

struct GeneralNotificationView: View {
    let notification: GeneralNotificationFeedback
    @State private var opacity: Double = 0.0
    @State private var scale: CGFloat = 0.8
    var body: some View {
        HStack(spacing: 10) {
            if let iconName = notification.icon { Image(systemName: iconName).foregroundColor(notification.color) }
            Text(notification.text).font(.headline).foregroundColor(.white)
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor.opacity(0.9))
        .cornerRadius(10)
        .shadow(radius: 5)
        .opacity(opacity).scaleEffect(scale)
        .onAppear { withAnimation(.interpolatingSpring(stiffness: 170, damping: 15).delay(0.1)) { opacity = 1.0; scale = 1.0 } }
    }
}

struct EmptyPlotIconView: View {
    let plotIndex: Int
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(vibrantPlotColor)
            .frame(minHeight: 80, maxHeight: 100)
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                VStack {
                    Text("Plot \(plotIndex + 1)")
                        .font(.caption2)
                        .foregroundColor(vibrantSecondaryTextColor)
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(vibrantSecondaryTextColor.opacity(0.7))
                }
            )
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
    let onInfoAction: () -> Void

    @State private var showingContextMenu = false
    @State private var localFeedbackText: String?
    @State private var localFeedbackColor: Color = dynamicSecondaryColor
    @State private var localFeedbackOpacity: Double = 0.0
    @State private var localFeedbackYOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 2) {
            currentPlantVisual()
                .frame(minHeight: 60, maxHeight: 80).aspectRatio(1, contentMode: .fit).cornerRadius(8).padding(.top, 2)
                .overlay( Group {
                        if isFertilizerModeActive && !plant.isFullyGrown {
                            RoundedRectangle(cornerRadius: 8).stroke(vibrantFertilizerButtonColor, lineWidth: 3).opacity(0.7)
                        }
                        else if isSellModeActive && plant.isFullyGrown {
                            RoundedRectangle(cornerRadius: 8).stroke(vibrantSellButtonColor, lineWidth: 3).opacity(0.7)
                                .overlay(Image(systemName: "dollarsign.circle.fill").font(.title2).foregroundColor(vibrantSellButtonColor.opacity(0.9)).padding(5).background(.ultraThinMaterial).clipShape(Circle()))
                        }
                })
                .overlay( Group { if let text = localFeedbackText { Text(text).font(.caption.weight(.bold)).foregroundColor(localFeedbackColor).padding(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)).background(dynamicSecondaryBackgroundColor.opacity(0.8)).cornerRadius(5).shadow(radius: 2).offset(y: localFeedbackYOffset).opacity(localFeedbackOpacity) }})
            VStack(alignment: .center, spacing: 1) {
                Text(plant.name).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundColor(vibrantPrimaryTextColor)
                if plant.isFullyGrown {
                    Text("Grown!")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(vibrantSellButtonColor.opacity(0.9))
                        .cornerRadius(3)
                }
                else {
                    Text("\(plant.daysLeftTillFullyGrown)d left")
                        .font(.system(size: 8))
                        .foregroundColor(plant.lastWateredOnDay != nil && Calendar.current.isDateInToday(plant.lastWateredOnDay!) ? vibrantSecondaryTextColor.opacity(0.8) : dynamicDestructiveColor)
                }
            }.padding(.bottom, 3)
        }
        .frame(minHeight: 80, maxHeight: 100).background(plotBackgroundColor()).cornerRadius(10)
        .onTapGesture {
            if isFertilizerModeActive { if !plant.isFullyGrown { onFertilizeAction() } }
            else if isSellModeActive { if plant.isFullyGrown { onTapInSellModeAction() } }
            else { onInfoAction() }
        }
        .onLongPressGesture { if !isFertilizerModeActive && !isSellModeActive { if plant.isFullyGrown || (!plant.isFullyGrown && !(plant.lastWateredOnDay != nil && Calendar.current.isDateInToday(plant.lastWateredOnDay!))) { showingContextMenu = true } } }
        .confirmationDialog("Plant Options: \(plant.name)", isPresented: $showingContextMenu, titleVisibility: .visible) {
            if !isFertilizerModeActive && !isSellModeActive {
                if !plant.isFullyGrown && !(plant.lastWateredOnDay != nil && Calendar.current.isDateInToday(plant.lastWateredOnDay!)) {
                    Button("Water Plant") { onWaterAction() }
                        .foregroundColor(vibrantWaterButtonColor)
                }
                if plant.isFullyGrown {
                    Button("Sell Plant (\(Int(plant.baseValue * 1.5)) Points)", role: .destructive) { onSellAction() }
                        .foregroundColor(dynamicDestructiveColor)
                }
                Button("Cancel", role: .cancel) {}
                    .foregroundColor(vibrantSecondaryTextColor)
            }
        }
        .onChange(of: feedbackItem?.id) {
            if let newFeedback = feedbackItem {
                localFeedbackText = newFeedback.text; localFeedbackColor = newFeedback.color
                localFeedbackYOffset = newFeedback.yOffset; localFeedbackOpacity = newFeedback.opacity
                withAnimation(.easeOut(duration: 0.3)) { localFeedbackYOffset = -30 }
                withAnimation(.easeOut(duration: 1.0).delay(0.2)) { localFeedbackOpacity = 0.0 }
            }
        }
    }
    
    @ViewBuilder private func currentPlantVisual() -> some View {
        if plant.isFullyGrown {
            PlantVisualDisplayView(assetName: plant.assetName, rarity: plant.rarity, displayName: plant.name, isIcon: false)
        }
        else if plant.initialDaysToGrow > 1 && plant.daysLeftTillFullyGrown <= plant.initialDaysToGrow / 2 {
            Image("seedling")
                .resizable()
                .scaledToFit()
                .padding(15)
        }
        else {
            Image("seed")
                .resizable()
                .scaledToFit()
                .padding(25)
        }
    }
    
    private func plotBackgroundColor() -> Color {
        if plant.isFullyGrown { return vibrantPlotGrownColor }
        if !plant.isFullyGrown && (plant.lastWateredOnDay == nil || !Calendar.current.isDateInToday(plant.lastWateredOnDay!)) {
            return vibrantPlotNeedsWaterColor
        }
        return vibrantPlotColor
    }
}

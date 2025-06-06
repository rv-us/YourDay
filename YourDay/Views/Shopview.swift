import SwiftUI
import SwiftData

// MARK: - Color Definitions
let plantDarkGreen = Color(hex: "#477468")
let plantMediumGreen = Color(hex: "#3A9C75")
let plantLightMintGreen = Color(hex: "#A7E2CD")
let plantPastelGreen = Color(hex: "#CDEDDD")
let plantDustyBlue = Color(hex: "#82A9BF")
let plantVeryLightBlue = Color(hex: "#D5E8EF")
let plantPastelBlue = Color(hex: "#C0E9ED")
let plantBeige = Color(hex: "#EEE7D6")
let plantPink = Color(hex: "#FBB7C7")
let plantLightPink = Color(hex: "#FAD9D5")
let plantPeach = Color(hex: "#FCE6D3")

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}


struct ShopView: View {
    @Environment(\.dismiss) var dismiss
    private let themes: [PlantTheme] = PlantTheme.allCases

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .center, spacing: 20) {
                    Text("Plant Gacha Shop")
                        .font(.largeTitle).fontWeight(.bold).padding(.top)
                        .foregroundColor(plantDarkGreen)
                    Text("Select a theme to pull plants!")
                        .font(.headline).foregroundColor(plantMediumGreen).padding(.bottom, 10)
                    ForEach(themes, id: \.self) { theme in
                        NavigationLink(destination: ThemePullView(theme: theme)) {
                            ThemeBannerView(theme: theme)
                        }
                    }
                }.padding()
            }
            .background(plantBeige.edgesIgnoringSafeArea(.all))
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(plantLightMintGreen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundColor(plantDarkGreen)
                }
                ToolbarItem(placement: .principal) {
                    Text("Shop")
                        .fontWeight(.bold)
                        .foregroundColor(plantDarkGreen)
                }
            }
        }
    }
}

struct ThemeBannerView: View {
    let theme: PlantTheme
    private func bannerImageName() -> String {
        switch theme {
        case .spring: return "TG-banner-spring"
        case .summer: return "TG-banner-summer"
        case .fall:   return "TG-banner-fall"
        case .winter: return "TG-banner-winter"
        }
    }

    private var bannerTintColor: Color {
        switch theme {
        case .spring: return plantPink.opacity(0.6)
        case .summer: return plantPastelBlue.opacity(0.6)
        case .fall: return plantPeach.opacity(0.6)
        case .winter: return plantVeryLightBlue.opacity(0.6)
        }
    }

    var body: some View {
        ZStack {
            bannerTintColor // Tint layer as background

            Image(bannerImageName()) // Image asset on top of tint
                .resizable()
                .aspectRatio(contentMode: .fill) // Original scaling
                // Image will fill the frame of the ZStack

            VStack { // Text overlay on top of image
                Text(theme.rawValue).font(.title).fontWeight(.bold).foregroundColor(.white)
                Text("Tap to Pull!").font(.caption).foregroundColor(.white.opacity(0.8))
            }
        }
        .frame(height: 120)
        .cornerRadius(15)
        .clipped()
        .shadow(color: plantDustyBlue.opacity(0.4), radius: 5, x: 0, y: 2) 
        .padding(.vertical, 5)
    }
}

struct ThemePullView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PlayerStats> { _ in true }) private var playerStatsList: [PlayerStats]
    private var playerStats: PlayerStats { playerStatsList.first ?? PlayerStats() }

    let theme: PlantTheme
    
    enum GachaAnimationStep {
        case idle, shuffling, revealing, revealedPoppedUp
    }
    @State private var animationStep: GachaAnimationStep = .idle
    @State private var plantForAnimation: PlantBlueprint?
    @State private var truePlantForCurrentReveal: PlantBlueprint?
    @State private var currentPullQueue: [PlantBlueprint] = []
    @State private var revealedPlantsThisPull: [PlantBlueprint] = []
    
    @State private var showingFinalResultMessageAlert = false
    @State private var finalResultMessage = ""

    @State private var shuffleTimer: Timer?
    @State private var shuffleCount = 0
    
    let shuffleDurationSeconds = 1.0
    let shuffleInterval = 0.07
    var maxShuffleCycles: Int { Int(shuffleDurationSeconds / shuffleInterval) }


    private func themePageBannerImageName() -> String {
        switch theme {
        case .spring: return "TG-banner-spring"
        case .summer: return "TG-banner-summer"
        case .fall:   return "TG-banner-fall"
        case .winter: return "TG-banner-winter"
        }
    }
    
    private var themeAccentColor: Color { // Used for buttons and highlights
        switch theme {
        case .spring: return plantPink
        case .summer: return plantPastelBlue
        case .fall: return plantPeach
        case .winter: return plantVeryLightBlue
        }
    }
    
    private var themePageBannerTintColor: Color { // Used for the banner background/tint
        switch theme {
        case .spring: return plantPink.opacity(0.5)
        case .summer: return plantPastelBlue.opacity(0.5)
        case .fall: return plantPeach.opacity(0.5)
        case .winter: return plantVeryLightBlue.opacity(0.5)
        }
    }
    
    private var themePageBackgroundColor: Color { // Overall page background
        switch theme {
        case .spring: return plantLightPink.opacity(0.3)
        case .summer: return plantPastelGreen.opacity(0.3)
        case .fall: return plantPeach.opacity(0.2)
        case .winter: return plantVeryLightBlue.opacity(0.3)
        }
    }


    var body: some View {
        ZStack {
            themePageBackgroundColor.edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        themePageBannerTintColor // Tint layer as background

                        Image(themePageBannerImageName()) // Image asset on top of tint
                            .resizable()
                            .scaledToFill() // Original scaling

                        Text("\(theme.rawValue) Theme") // Text overlay on top of image
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(radius: 3) // Reverted to original simpler shadow
                    }
                    .frame(width: 350, height: 180) // Original frame dimensions
                    .cornerRadius(10) // Original corner radius
                    .clipped() // Ensures content within bounds
                    .shadow(color: plantDustyBlue.opacity(0.3), radius: 5, x: 0, y: 2) // Consistent shadow style
                    .padding(.vertical)

                    Text("Current Points: \(Int(playerStats.totalPoints))")
                        .font(.headline)
                        .foregroundColor(plantDarkGreen)

                    VStack(spacing: 15) {
                        pullButton(numPulls: 2, cost: 100)
                        pullButton(numPulls: 10, cost: 500, isGuaranteed: true)
                    }.padding(.horizontal)

                    if !revealedPlantsThisPull.isEmpty {
                        Divider().padding(.vertical)
                            .background(plantMediumGreen)
                        Text("Pulled This Session:").font(.title2).fontWeight(.semibold)
                            .foregroundColor(plantDarkGreen)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(revealedPlantsThisPull) { plantBlueprint in
                                    VStack {
                                        plantBlueprint.iconVisual
                                            .frame(width: 60, height: 60)
                                            .background(plantPastelGreen.opacity(0.7)).cornerRadius(8)
                                            .shadow(color: plantDustyBlue.opacity(0.3), radius: 2, x: 0, y: 1)
                                        Text(plantBlueprint.name).font(.caption).lineLimit(1)
                                            .foregroundColor(plantDarkGreen)
                                        Text(plantBlueprint.rarity.rawValue).font(.caption2).foregroundColor(rarityColor(plantBlueprint.rarity))
                                    }.frame(width: 70)
                                }
                            }.padding()
                        }.frame(height: 120)
                        .background(plantBeige.opacity(0.5))
                        .cornerRadius(10)
                    }
                    Spacer()
                }.padding()
                 .blur(radius: animationStep != .idle ? 3 : 0)
            }
            .navigationTitle("\(theme.rawValue) Pulls")
            .background(plantBeige.edgesIgnoringSafeArea(.all))  
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(themeAccentColor.opacity(0.8), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                 ToolbarItem(placement: .principal) {
                    Text("\(theme.rawValue) Pulls")
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton(color: .white)
                }
            }
            .alert(isPresented: $showingFinalResultMessageAlert) {
                Alert(title: Text("Pull Result").foregroundColor(plantDarkGreen),
                      message: Text(finalResultMessage).foregroundColor(plantMediumGreen),
                      dismissButton: .default(Text("OK").foregroundColor(themeAccentColor)))
            }
            .disabled(animationStep != .idle)

            if animationStep != .idle {
                gachaAnimationOverlay()
            }
        }
    }

    @ViewBuilder
    private func gachaAnimationOverlay() -> some View {
        ZStack {
            plantDarkGreen.opacity(0.7).edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    if animationStep == .revealedPoppedUp {
                        dismissRevealedPlant()
                    } else if animationStep == .shuffling {
                        skipShuffle()
                    }
                }

            VStack {
                if animationStep == .shuffling, let plant = plantForAnimation {
                    plant.iconVisual
                        .frame(width: 100, height: 100).scaleEffect(1.2)
                        .background(plantPastelGreen.opacity(0.5))
                        .cornerRadius(15)
                        .transition(.opacity.combined(with: .scale))
                        .id("shuffle_display_\(plant.id)_\(shuffleCount)")
                    Text("Shuffling...").foregroundColor(plantBeige).padding(.top)
                        .font(.title3)
                } else if (animationStep == .revealing || animationStep == .revealedPoppedUp), let plant = plantForAnimation {
                    VStack {
                        Text("You got...").font(.title2).fontWeight(.bold).foregroundColor(plantBeige)
                        plant.iconVisual
                            .frame(width: 150, height: 150)
                            .background(rarityColor(plant.rarity).opacity(0.2))
                            .cornerRadius(25)
                            .scaleEffect(animationStep == .revealing ? 0.5 : 1.8) // This scaling is for animation, not static display
                            .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(animationStep == .revealing ? 0 : 0.1), value: animationStep)
                            .padding()
                        Text(plant.name).font(.title).fontWeight(.bold).foregroundColor(plantBeige)
                        Text(plant.rarity.rawValue).font(.headline).foregroundColor(rarityColor(plant.rarity))
                        Text(plant.theme.rawValue).font(.subheadline).foregroundColor(plantPastelGreen)
                        if animationStep == .revealedPoppedUp {
                            Text("Tap plant to continue").font(.caption).foregroundColor(plantBeige.opacity(0.7)).padding(.top)
                        }
                    }
                    .padding(30)
                    .background(plantMediumGreen.opacity(0.9))
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.4), radius: 10, x:0, y:5)
                    .transition(.scale.combined(with: .opacity))
                    .onTapGesture {
                        if animationStep == .revealedPoppedUp {
                            dismissRevealedPlant()
                        }
                    }
                }
            }

            if (animationStep == .shuffling || animationStep == .revealing || animationStep == .revealedPoppedUp) && !currentPullQueue.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Button("Skip All") {
                            skipAllPullsAndShowResults()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(plantPink.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(radius: 3)
                        .padding()
                        Spacer()
                    }
                }
            }
        }
    }
    
    private func handleTapDuringAnimation() {
        if animationStep == .shuffling {
            skipShuffle()
        }
    }

    private func skipShuffle() {
        shuffleTimer?.invalidate()
        shuffleTimer = nil
        shuffleCount = 0
        plantForAnimation = truePlantForCurrentReveal
        revealNextPlant()
    }
    
    private func dismissRevealedPlant() {
        guard truePlantForCurrentReveal != nil else { return }
        
        withAnimation(.easeOut(duration: 0.3)) {
            animationStep = .idle
            plantForAnimation = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
             startNextReveal()
        }
    }

    private func skipAllPullsAndShowResults() {
        shuffleTimer?.invalidate()
        shuffleTimer = nil
        
        if let currentRevealing = truePlantForCurrentReveal, !revealedPlantsThisPull.contains(where: {$0.id == currentRevealing.id }) {
            revealedPlantsThisPull.append(currentRevealing)
        }
        revealedPlantsThisPull.append(contentsOf: currentPullQueue)
        currentPullQueue.removeAll()
        
        animationStep = .idle
        plantForAnimation = nil
        truePlantForCurrentReveal = nil
        
        if !finalResultMessage.isEmpty && !revealedPlantsThisPull.isEmpty {
            showingFinalResultMessageAlert = true
        }
    }

    @ViewBuilder
    private func pullButton(numPulls: Int, cost: Double, isGuaranteed: Bool = false) -> some View {
        Button(action: {
            initiatePullSequence(numberOfPulls: numPulls, totalCost: cost)
        }) {
            VStack(spacing: 5) {
                Text("Pull \(numPulls) Plant\(numPulls > 1 ? "s" : "")")
                    .fontWeight(.semibold)
                Text("Cost: \(Int(cost)) Points")
                    .font(.caption)
                if isGuaranteed {
                    Text("Guaranteed Rare or Better!")
                        .font(.caption2)
                        .foregroundColor(plantMediumGreen)
                        .fontWeight(.bold)
                }
            }
            .padding().frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: playerStats.totalPoints >= cost ? [themeAccentColor, themeAccentColor.opacity(0.7)] : [plantDustyBlue.opacity(0.6), plantDustyBlue.opacity(0.4)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .foregroundColor(.white).cornerRadius(10)
            .shadow(color: playerStats.totalPoints >= cost ? themeAccentColor.opacity(0.5) : plantDustyBlue.opacity(0.3), radius: 3, x: 0, y: 2)
        }
        .disabled(playerStats.totalPoints < cost || animationStep != .idle)
    }

    private func initiatePullSequence(numberOfPulls: Int, totalCost: Double) {
        guard let mutablePlayerStats = playerStatsList.first else {
            finalResultMessage = "Error: Player data not found."
            showingFinalResultMessageAlert = true
            return
        }
        
        let result = mutablePlayerStats.pullPlants(forTheme: theme, numberOfPulls: numberOfPulls, totalCost: totalCost)
        
        if result.success {
            currentPullQueue = result.pulledPlants
            revealedPlantsThisPull.removeAll()
            finalResultMessage = result.message
            if !currentPullQueue.isEmpty {
                startNextReveal()
            } else {
                showingFinalResultMessageAlert = true
            }
        } else {
            finalResultMessage = result.message
            showingFinalResultMessageAlert = true
        }
    }
    
    private func startNextReveal() {
        if currentPullQueue.isEmpty {
            animationStep = .idle
            plantForAnimation = nil
            truePlantForCurrentReveal = nil
            if !finalResultMessage.isEmpty && !revealedPlantsThisPull.isEmpty {
                showingFinalResultMessageAlert = true
            }
            return
        }
        
        let nextPlant = currentPullQueue.removeFirst()
        truePlantForCurrentReveal = nextPlant
        plantForAnimation = nextPlant
        animationStep = .shuffling
        shuffleCount = 0
        
        let themePlantsForShuffle = PlantLibrary.allPlantBlueprints.filter { $0.theme == theme }.shuffled()
        
        shuffleTimer?.invalidate()
        shuffleTimer = Timer.scheduledTimer(withTimeInterval: shuffleInterval, repeats: true) { [self] timer in
            if shuffleCount >= maxShuffleCycles {
                timer.invalidate()
                self.shuffleTimer = nil
                self.plantForAnimation = self.truePlantForCurrentReveal
                self.revealNextPlant()
            } else {
                if !themePlantsForShuffle.isEmpty {
                    self.plantForAnimation = themePlantsForShuffle[shuffleCount % themePlantsForShuffle.count]
                }
                self.shuffleCount += 1
            }
        }
    }

    private func revealNextPlant() {
        if let actualPlantToReveal = truePlantForCurrentReveal {
            plantForAnimation = actualPlantToReveal
            
            withAnimation(.interpolatingSpring(stiffness: 100, damping: 12)) {
                animationStep = .revealing
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                     animationStep = .revealedPoppedUp
                }
            }
            if !revealedPlantsThisPull.contains(where: {$0.id == actualPlantToReveal.id}) {
                 revealedPlantsThisPull.append(actualPlantToReveal)
            }
        } else {
            startNextReveal()
        }
    }
    
    private func rarityColor(_ rarity: Rarity) -> Color {
        switch rarity {
        case .common: return plantDustyBlue
        case .uncommon: return plantMediumGreen
        case .rare: return plantPastelBlue
        case .epic: return plantPink
        case .legendary: return plantPeach
        }
    }
}

struct BackButton: View {
    @Environment(\.dismiss) var dismiss
    var color: Color = .blue

    var body: some View {
        Button(action: {
            dismiss()
        }) {
            Image(systemName: "chevron.left")
                .foregroundColor(color)
                .imageScale(.large)
        }
    }
}

//
//  ShopView.swift
//  YourDay
//
//  Created by RachitVerma on 5/9/25.
//

import SwiftUI
import SwiftData

struct ShopView: View {
    @Environment(\.dismiss) var dismiss
    private let themes: [PlantTheme] = PlantTheme.allCases

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .center, spacing: 20) {
                    Text("Plant Gacha Shop")
                        .font(.largeTitle).fontWeight(.bold).padding(.top)
                    Text("Select a theme to pull plants!")
                        .font(.headline).foregroundColor(.secondary).padding(.bottom, 10)
                    ForEach(themes, id: \.self) { theme in
                        NavigationLink(destination: ThemePullView(theme: theme)) {
                            ThemeBannerView(theme: theme)
                        }
                    }
                }.padding()
            }
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
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

    var body: some View {
        VStack {
            Image(bannerImageName())
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 120)
                .cornerRadius(15)
                .overlay( VStack {
                    Text(theme.rawValue).font(.title).fontWeight(.bold).foregroundColor(.white)
                    Text("Tap to Pull!").font(.caption).foregroundColor(.white.opacity(0.8))
                })
                .shadow(radius: 5)
        }.padding(.vertical, 5)
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

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(themePageBannerImageName())
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 350, height: 180)
                                            .cornerRadius(10)
                                            .clipped()
                                            .overlay(
                                                Text("\(theme.rawValue) Theme")
                                                    .font(.system(size: 36, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .shadow(radius: 3)
                                            )
                                            .padding(.vertical)
                    Text("Current Points: \(Int(playerStats.totalPoints))").font(.headline)

                    VStack(spacing: 15) {
                        pullButton(numPulls: 2, cost: 100)
                        pullButton(numPulls: 10, cost: 500, isGuaranteed: true)
                    }.padding(.horizontal)

                    if !revealedPlantsThisPull.isEmpty {
                        Divider().padding(.vertical)
                        Text("Pulled This Session:").font(.title2).fontWeight(.semibold)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(revealedPlantsThisPull) { plantBlueprint in
                                    VStack {
                                        plantBlueprint.iconVisual
                                            .frame(width: 60, height: 60)
                                            .background(Color(UIColor.systemGray5)).cornerRadius(8)
                                        Text(plantBlueprint.name).font(.caption).lineLimit(1)
                                        Text(plantBlueprint.rarity.rawValue).font(.caption2).foregroundColor(rarityColor(plantBlueprint.rarity))
                                    }.frame(width: 70)
                                }
                            }.padding()
                        }.frame(height: 120)
                    }
                    Spacer()
                }.padding()
                 .blur(radius: animationStep != .idle ? 3 : 0)
            }
            .navigationTitle("\(theme.rawValue) Pulls")
            .alert(isPresented: $showingFinalResultMessageAlert) {
                Alert(title: Text("Pull Result"), message: Text(finalResultMessage), dismissButton: .default(Text("OK")))
            }
            .disabled(animationStep != .idle)

            if animationStep != .idle {
                gachaAnimationOverlay()
            }
        }
    }

    @ViewBuilder
    private func gachaAnimationOverlay() -> some View {
        // Main ZStack for the overlay. Default alignment is .center.
        ZStack {
            Color.black.opacity(0.6).edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // Tap on background to dismiss only when a plant is fully revealed and popped up
                    if animationStep == .revealedPoppedUp {
                        dismissRevealedPlant()
                    }
                }

            // Centered content (shuffling or revealed plant)
            VStack {
                if animationStep == .shuffling, let plant = plantForAnimation {
                    plant.iconVisual
                        .frame(width: 100, height: 100).scaleEffect(1.2)
                        .transition(.opacity.combined(with: .scale))
                        .id("shuffle_display_\(plant.id)_\(shuffleCount)")
                    Text("Shuffling...").foregroundColor(.white).padding(.top)
                } else if (animationStep == .revealing || animationStep == .revealedPoppedUp), let plant = plantForAnimation {
                    VStack {
                        Text("You got...").font(.title2).fontWeight(.bold).foregroundColor(.white)
                        plant.iconVisual
                            .frame(width: 150, height: 150)
                            .scaleEffect(animationStep == .revealing ? 0.5 : 1.8)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(animationStep == .revealing ? 0 : 0.1), value: animationStep)
                            .padding()
                        Text(plant.name).font(.title).fontWeight(.bold).foregroundColor(.white)
                        Text(plant.rarity.rawValue).font(.headline).foregroundColor(rarityColor(plant.rarity))
                        Text(plant.theme.rawValue).font(.subheadline).foregroundColor(.gray)
                        if animationStep == .revealedPoppedUp {
                            Text("Tap plant to continue").font(.caption).foregroundColor(.white.opacity(0.7)).padding(.top)
                        }
                    }
                    .padding(30).background(.ultraThinMaterial).cornerRadius(20)
                    .shadow(radius: 10)
                    .transition(.scale.combined(with: .opacity))
                    .onTapGesture {
                        if animationStep == .revealedPoppedUp {
                            dismissRevealedPlant()
                        }
                    }
                }
            } // End of Centered Content VStack

            // Skip All Button, positioned independently at the bottom left
            if (animationStep == .shuffling || animationStep == .revealing || animationStep == .revealedPoppedUp) && !currentPullQueue.isEmpty {
                VStack { // Use VStack and Spacer to push button to bottom
                    Spacer()
                    HStack {
                        Button("Skip All") {
                            skipAllPullsAndShowResults()
                        }
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding() // Padding for the button itself
                        Spacer() // Pushes button to the left
                    }
                }
            }
        } // End of main ZStack for overlay
    }
    
    private func handleTapDuringAnimation() {
        // This function is now primarily for skipping shuffle if background is tapped during shuffle
        if animationStep == .shuffling {
            skipShuffle()
        }
        // Tapping on the revealed plant itself is handled by its own .onTapGesture
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
            VStack {
                Text("Pull \(numPulls) Plant\(numPulls > 1 ? "s" : "") (\(Int(cost)) Points)")
                    .fontWeight(.semibold)
                if isGuaranteed {
                    Text("Guaranteed Rare or Better!")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            }
            .padding().frame(maxWidth: .infinity)
            .background(playerStats.totalPoints >= cost ? Color.accentColor : Color.gray)
            .foregroundColor(.white).cornerRadius(10)
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
            revealedPlantsThisPull.append(actualPlantToReveal)
        } else {
            startNextReveal()
        }
    }
    
    private func rarityColor(_ rarity: Rarity) -> Color {
        switch rarity {
        case .common: return .gray
        case .uncommon: return .green
        case .rare: return .blue
        case .epic: return .purple
        case .legendary: return .orange
        }
    }
}

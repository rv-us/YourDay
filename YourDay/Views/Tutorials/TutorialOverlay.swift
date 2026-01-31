//
//  TutorialOverlay.swift
//  YourDay
//
//  Created by Rachit Verma on 5/14/25.
//

import SwiftUI

struct TutorialOverlayView: View {
    @Binding var currentStep: TutorialStep // Defined in GardenView.swift
    @Binding var isActive: Bool // To dismiss the overlay
    
    let hasPlantsInInventory: Bool // To conditionally guide user
    @Binding var hasCompletedTutorialPreviously: Bool // Tracks if tutorial was finished

    var onNavigateToShop: () -> Void // Closure to trigger navigation to shop
    var onReturnToGarden: () -> Void // Placeholder
    var onAcknowledgeActionStep: (() -> Void)? = nil // NEW: Closure to hide overlay on action steps

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.75)
                .edgesIgnoringSafeArea(.all)

            // Main content box for the tutorial step
            VStack(spacing: 20) {
                // Title
                Text(currentStep.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // Message and optional icon
                VStack(spacing: 10) {
                    Text(currentStep.message)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if let iconName = currentStep.iconForMessage {
                        Image(systemName: iconName)
                            .font(.largeTitle)
                            .foregroundColor(.yellow)
                            .padding(.top, 5)
                    }
                }
                
                // Main action button
                Button(action: handleNextButton) {
                    Text(currentStep.nextButtonText)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(Color.yellow)
                        .cornerRadius(10)
                }
                .padding(.top)
                
                // "Skip Tutorial" button
                if currentStep != .welcome && currentStep != .explainShop && currentStep != .finished {
                     Button("Skip Tutorial") {
                        finishTutorial()
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 10)
                }
            }
            // Styling for the tutorial box
            .padding(20)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.9)
            .background(.thinMaterial)
            .cornerRadius(20)
            .shadow(radius: 10)
            .padding(.horizontal, 20)
            .padding(.vertical, 30)
        }
        .animation(.easeInOut, value: currentStep)
    }

    // Handles the action for the main button
    private func handleNextButton() {
        switch currentStep {
        case .explainShop:
            onNavigateToShop()
            
        case .finished:
            finishTutorial()
            
        // ----- MODIFIED CASE -----
        case .explainPlanting, .explainFertilizer, .explainSell, .explainWatering:
            print("User acknowledged tutorial step: \(currentStep). Hiding overlay for action.")
            onAcknowledgeActionStep?() // Call closure to hide overlay
            // GardenView will handle making the overlay inactive.
            // Tutorial advancement happens in GardenView after the action.
        // ----- END OF MODIFIED CASE -----
            
        default: // For .welcome, .explainPlotsValue, etc.
            advanceStep()
        }
    }

    // Advances to the next tutorial step (for non-action steps)
    private func advanceStep() {
        let nextRawValue = currentStep.rawValue + 1
        if let nextStep = TutorialStep(rawValue: nextRawValue) {
            currentStep = nextStep
        } else {
            finishTutorial()
        }
    }
    
    // Finishes the tutorial
    private func finishTutorial() {
        hasCompletedTutorialPreviously = true
        isActive = false // This binding change will be picked up by GardenView
    }
}

// Preview Provider (Optional)
/*
 #if DEBUG
 struct TutorialOverlayView_Previews: PreviewProvider {
    enum PreviewTutorialStep: Int, Identifiable, CaseIterable {
        case welcome = 0, explainShop, explainPlanting, explainFertilizer, explainSell, explainPlotsValue, explainWatering, finished
        var id: Int { rawValue }
        var title: String { "\(self)".capitalized.replacingOccurrences(of: "Explain", with: "Explain ") }
        var message: String { "Preview message for \(title.lowercased())." }
        var iconForMessage: String? { nil } // Add specific icons if needed for preview
        var nextButtonText: String {
            switch self {
            case .explainShop: return "Go to Shop"
            case .finished: return "Start Gardening!"
            case .explainPlanting, .explainFertilizer, .explainSell, .explainWatering: return "Okay, Got It!"
            default: return "Next Tip"
            }
        }
    }

    @State static varisPreviewIsActive = true
    @State static varisPreviewCurrentStep: TutorialStep = .welcome // Use your actual TutorialStep
    @State static varisPreviewHasCompleted = false

    static var previews: some View {
        TutorialOverlayView(
            currentStep: $isPreviewCurrentStep,
            isActive: $isPreviewIsActive,
            hasPlantsInInventory: true,
            hasCompletedTutorialPreviously: $isPreviewHasCompleted,
            onNavigateToShop: { print("Preview: Navigating to shop.") },
            onReturnToGarden: { print("Preview: Returning to garden.") },
            onAcknowledgeActionStep: {
                print("Preview: Action step acknowledged. Hiding overlay.")
                // In a real scenario, GardenView would set isPreviewIsActive to false.
                // For preview, you might simulate it or just print.
            }
        )
    }
 }
 #endif
 */

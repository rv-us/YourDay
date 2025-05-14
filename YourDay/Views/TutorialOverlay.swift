//
//  TutorialOverlay.swift
//  YourDay
//
//  Created by Rachit Verma on 5/14/25.
//

import SwiftUI

struct TutorialOverlayView: View {
    @Binding var currentStep: TutorialStep // Ensure TutorialStep is defined (likely in GardenView.swift)
    @Binding var isActive: Bool // To dismiss the overlay
    
    let hasPlantsInInventory: Bool
    @Binding var hasCompletedTutorialPreviously: Bool // To track if tutorial was finished before

    var onNavigateToShop: () -> Void
    var onReturnToGarden: () -> Void // Placeholder, not directly used in this version's logic but good for future

    var body: some View {
        ZStack {
            // Semi-transparent background covering the whole screen
            Color.black.opacity(0.75)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // Optional: Allow dismissing by tapping outside if not on a crucial step
                    // if currentStep != .welcome && currentStep != .explainShop {
                    //     isActive = false
                    // }
                }

            // Main content box for the tutorial step
            VStack(spacing: 20) {
                // Title of the current tutorial step
                Text(currentStep.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // Message and optional icon for the current tutorial step
                VStack(spacing: 10) {
                    Text(currentStep.message)
                        .font(.title3) // Using title3 for a slightly larger message font
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal) // Padding for message text within its VStack

                    if let iconName = currentStep.iconForMessage {
                        Image(systemName: iconName)
                            .font(.largeTitle) // Icon size
                            .foregroundColor(.yellow) // Icon color
                            .padding(.top, 5) // Space above the icon
                    }
                }
                
                // "Next" or "Action" button
                Button(action: handleNextButton) {
                    Text(currentStep.nextButtonText)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black) // Text color for the button
                        .padding(.horizontal, 30) // Horizontal padding inside the button
                        .padding(.vertical, 15)   // Vertical padding inside the button
                        .background(Color.yellow)   // Button background color
                        .cornerRadius(10)           // Rounded corners for the button
                }
                .padding(.top) // Space above the main action button
                
                // "Skip Tutorial" button, shown for most steps
                if currentStep != .welcome && currentStep != .explainShop && currentStep != .finished {
                     Button("Skip Tutorial") {
                        finishTutorial()
                    }
                    .font(.caption) // Smaller font for the skip button
                    .foregroundColor(.gray) // Less prominent color for skip
                    .padding(.top, 10) // Space above the skip button
                }
            }
            // ----- START OF MODIFIED LINES -----
            .padding(20) // Reduced inner padding around the content VStack
            .frame(maxWidth: UIScreen.main.bounds.width * 0.9) // Set max width to 90% of screen width
            .background(.thinMaterial) // Background for the tutorial box (iOS blur effect)
            .cornerRadius(20)          // Rounded corners for the tutorial box
            .shadow(radius: 10)        // Drop shadow for a bit of depth
            .padding(.horizontal, 20)  // Reduced horizontal padding outside the box (from screen edges)
            .padding(.vertical, 30)    // Vertical padding outside the box (from screen edges)
            // ----- END OF MODIFIED LINES -----
        }
        .animation(.easeInOut, value: currentStep) // Animate transitions between steps
    }

    // Handles the action for the main button (e.g., "Next Tip", "Go to Shop")
    private func handleNextButton() {
        if currentStep == .explainShop {
            // Special action for the "Go to Shop" step
            onNavigateToShop()
            // GardenView will manage isActive and wasShopVisitedForTutorial
        } else if currentStep == .finished {
            // Action for the final step's button ("Start Gardening!")
            finishTutorial()
        } else {
            // Default action: advance to the next tutorial step
            advanceStep()
        }
    }

    // Advances to the next tutorial step in sequence
    private func advanceStep() {
        // TutorialStep enum needs to be defined, typically with raw Int values
        // to allow advancing by incrementing the rawValue.
        if let nextRawValue = TutorialStep(rawValue: currentStep.rawValue + 1) {
            currentStep = nextRawValue
        } else {
            // If there's no next step (i.e., we're past the last defined step), finish the tutorial.
            finishTutorial()
        }
    }
    
    // Marks the tutorial as completed and dismisses the overlay
    private func finishTutorial() {
        hasCompletedTutorialPreviously = true // Update the @AppStorage variable via binding
        isActive = false // Dismiss the tutorial overlay
    }
}

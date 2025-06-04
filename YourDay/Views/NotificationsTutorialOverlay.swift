//
//  NotificationsTutorialOverlay.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 6/3/25.
//

import SwiftUI

struct NotificationsTutorialOverlay: View {
    @Binding var currentStep: NotificationsTutorialStep
    @Binding var isActive: Bool
    @Binding var hasCompletedTutorial: Bool

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                Text(currentStep.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(currentStep.message)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(action: handleNext) {
                    Text(currentStep.nextButtonText)
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }

                if currentStep != .welcome && currentStep != .finished {
                    Button(action: finishTutorial) {
                        Text("Skip Tutorial")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 4)
                    }
                }
            }
            .padding()
            .frame(maxWidth: UIScreen.main.bounds.width * 0.9)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(radius: 10)
            .padding(.bottom, 25)
            .contentShape(Rectangle()) // Ensure only the tutorial card captures touches
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false) // Let touches through by default
        .overlay(
            // Overlay card is interactive
            VStack {
                Spacer()
                tutorialCard
            }
            .allowsHitTesting(true)
        )
        .transition(.opacity)
        .animation(.easeInOut, value: currentStep)
    }

    private var tutorialCard: some View {
        VStack(spacing: 16) {
            Text(currentStep.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(currentStep.message)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: handleNext) {
                Text(currentStep.nextButtonText)
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                    .background(Color.yellow)
                    .cornerRadius(12)
            }

            if currentStep != .welcome && currentStep != .finished {
                Button(action: finishTutorial) {
                    Text("Skip Tutorial")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 4)
                }
            }
        }
        .padding()
        .frame(maxWidth: UIScreen.main.bounds.width * 0.9)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(.bottom, 25)
    }

    private func handleNext() {
        let nextRawValue = currentStep.rawValue + 1
        if let nextStep = NotificationsTutorialStep(rawValue: nextRawValue) {
            currentStep = nextStep
        } else {
            finishTutorial()
        }
    }

    private func finishTutorial() {
        isActive = false
        hasCompletedTutorial = true
    }
}

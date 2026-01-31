//
//  NotesTutorialOverlay.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 6/3/25.
//

import SwiftUI

struct NotesTutorialOverlay: View {
    @Binding var currentStep: NotesTutorialStep
    @Binding var isActive: Bool
    @Binding var hasCompletedTutorial: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()

            VStack(spacing: 16) {
                Text(currentStep.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(currentStep.message)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding()
                    .fixedSize(horizontal: false, vertical: true)

                if !currentStep.requiresUserAction {
                    Button(action: advance) {
                        Text(currentStep.nextButtonText)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.yellow)
                            .foregroundColor(.black)
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }
                }

                if currentStep != .welcome && currentStep != .finished {
                    Button("Skip Tutorial") {
                        finish()
                    }
                    .foregroundColor(.gray)
                    .padding(.top, 10)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding()
        }
        .transition(.opacity)
        .animation(.easeInOut, value: currentStep)
    }

    private func advance() {
        if let nextStep = NotesTutorialStep(rawValue: currentStep.rawValue + 1) {
            currentStep = nextStep
        } else {
            finish()
        }
    }

    private func finish() {
        hasCompletedTutorial = true
        isActive = false
    }
}

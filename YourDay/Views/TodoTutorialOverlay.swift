//
//  TodoTutorialOverlay.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 6/3/25.
//

import SwiftUI

struct TodoTutorialOverlay: View {
    @Binding var currentStep: TodoTutorialStep
    @Binding var isActive: Bool
    @Binding var hasCompletedTutorialPreviously: Bool
    @Binding var highlightAdd: Bool
    @Binding var highlightStar: Bool
    var onDismiss: () -> Void
    

    var onAcknowledgeActionStep: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                Text(currentStep.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Text(currentStep.message)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .fixedSize(horizontal: false, vertical: true)

                    if let icon = currentStep.icon {
                        Image(systemName: icon)
                            .font(.largeTitle)
                            .foregroundColor(.yellow)
                            .padding(.top, 5)
                    }
                }

                if !currentStep.requiresUserAction {
                    Button(action: handleNext) {
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
                }

                if currentStep != .welcome && currentStep != .finished {
                    Button("Skip Tutorial") {
                        finishTutorial()
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 10)
                }
            }
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

    private func handleNext() {
        let nextRawValue = currentStep.rawValue + 1
        if let nextStep = TodoTutorialStep(rawValue: nextRawValue) {
            currentStep = nextStep
        } else {
            finishTutorial()
        }
    }

    private func finishTutorial() {
        hasCompletedTutorialPreviously = true
        isActive = false
        highlightAdd = false
        highlightStar = false
        currentStep = .finished
        onDismiss()
    }
}

// Enum for tutorial steps
enum TodoTutorialStep: Int, CaseIterable {
    case welcome, explainAdd, explainSummary, finished

    var title: String {
        switch self {
        case .welcome: return "Welcome to YourDay"
        case .explainAdd: return "Add a New Task"
        case .explainSummary: return "Open Daily Summary"
        case .finished: return "You're Ready!"
        }
    }

    var message: String {
        switch self {
        case .welcome: return "This is your personal to-do list to stay organized."
        case .explainAdd: return "Tap the '+' button to add a new item."
        case .explainSummary: return "Tap the star icon to view your daily summary and rewards. Remember you will earn points at the start of everyday based on the tasks you completed the previous day. The points from tasks are determined by your garden value"
        case .finished: return "You're all set to start using YourDay!"
        }
    }

    var nextButtonText: String {
        switch self {
        case .finished: return "Get Started"
        default: return "Next"
        }
    }

    var icon: String? {
        switch self {
        case .explainAdd: return "plus.circle"
        case .explainSummary: return "star"
        default: return nil
        }
    }

    var requiresUserAction: Bool {
        switch self {
        case .explainAdd:
            return true
        case .explainSummary:
            return true
        default:
            return false
        }
    }
}

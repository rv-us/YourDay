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
    @Binding var highlightFilter: Bool
    var onDismiss: () -> Void
    

    var onAcknowledgeActionStep: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Semi-transparent overlay that allows interaction with highlighted elements
            Color.black.opacity(currentStep.requiresUserAction ? 0.3 : 0.75)
                .edgesIgnoringSafeArea(.all)
                .allowsHitTesting(!currentStep.requiresUserAction)

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
                } else {
                    // For steps requiring user action, show a hint
                    Text("Try interacting with the highlighted element above")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 10)
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
        highlightFilter = false
        currentStep = .finished
        onDismiss()
    }
}

// Enum for tutorial steps
enum TodoTutorialStep: Int, CaseIterable {
    case welcome, explainFilter, explainAdd, explainSummary, explainMigration, finished

    var title: String {
        switch self {
        case .welcome: return "Welcome to YourDay"
        case .explainFilter: return "Today vs Master List"
        case .explainAdd: return "Add a New Task"
        case .explainSummary: return "Daily Summary & Rewards"
        case .explainMigration: return "Moving Tasks Between Lists"
        case .finished: return "You're Ready!"
        }
    }

    var message: String {
        switch self {
        case .welcome: return "This is your personal to-do list to stay organized and productive."
        case .explainFilter: return "Switch between 'Today' for daily tasks and 'Master List' for ongoing projects."
        case .explainAdd: return "Tap the '+' button to create a new task. The list selection will be pre-set based on which tab you're currently viewing."
        case .explainSummary: return "Tap the star icon to view your daily summary and track your progress. You'll earn points each morning based on completed tasks from the previous day."
        case .explainMigration: return "To move tasks between lists, tap on any task to edit it and change the 'Add To' setting. This helps you organize tasks as your priorities change."
        case .finished: return "You're all set to start using YourDay! Create tasks, track progress, and watch your garden grow with your productivity."
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
        case .explainFilter: return "list.bullet"
        case .explainAdd: return "plus.circle"
        case .explainSummary: return "star"
        case .explainMigration: return "arrow.left.arrow.right"
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

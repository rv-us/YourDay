//
//  SchedulingComponents.swift
//  YourDay
//
//  Shared UI components for scheduling views
//

import SwiftUI

// MARK: - Duration Stepper Component

struct DurationStepper: View {
    @Binding var duration: Int
    let minDuration: Int
    let maxDuration: Int
    let step: Int

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                if duration > minDuration {
                    duration = max(minDuration, duration - step)
                }
            }) {
                Image(systemName: "minus")
                    .font(.headline)
                    .foregroundColor(duration <= minDuration ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                    .frame(width: 36, height: 36)
                    .background(dynamicBackgroundColor)
            }
            .disabled(duration <= minDuration)

            Divider()
                .frame(height: 24)

            Button(action: {
                if duration < maxDuration {
                    duration = min(maxDuration, duration + step)
                }
            }) {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundColor(duration >= maxDuration ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                    .frame(width: 36, height: 36)
                    .background(dynamicBackgroundColor)
            }
            .disabled(duration >= maxDuration)
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(dynamicSecondaryTextColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Quick Reason Chip

struct QuickReasonChip: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.caption)
                .foregroundColor(dynamicPrimaryColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(dynamicPrimaryColor.opacity(0.15))
                .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Animated Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dynamicSecondaryTextColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                    .opacity(animationPhase == index ? 1.0 : 0.4)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    animationPhase = (animationPhase + 1) % 3
                }
            }
        }
    }
}




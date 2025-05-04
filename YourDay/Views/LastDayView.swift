//
//  LastDayView.swift
//  YourDay
//

import SwiftUI

func formattedYesterday() -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    return formatter.string(from: yesterday)
}

struct LastDayView: View {
    let totalPoints: Double
    let taskBreakdown: [TaskPointResult]
    var isModal: Bool = false

    @State private var animatedPoints: Double = 0
    @State private var showContinue = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("🎯 Level Complete (\(formattedYesterday()))")
                .font(.largeTitle)
                .bold()
                .transition(.move(edge: .top).combined(with: .opacity))

            Text("+\(Int(animatedPoints)) Points")
                .font(.system(size: 40, weight: .heavy))
                .foregroundColor(.green)
                .onAppear {
                    withAnimation(.easeOut(duration: 1.5)) {
                        animatedPoints = totalPoints
                    }
                    withAnimation(.spring().delay(1.2)) {
                        showContinue = true
                    }
                }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(taskBreakdown) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text(task.title)
                                .font(.headline)
                        }

                        if !task.subtaskPoints.isEmpty {
                            ForEach(task.subtaskPoints.filter { $0.earned > 0 }, id: \.title) { sub in
                                HStack {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text(sub.title)
                                        .font(.subheadline)
                                }
                                .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)

            Spacer()

            CircleProgressView(
                completed: totalCompletedCount(),
                total: totalTaskCount()
            )
            .frame(width: 120, height: 120)
            .padding(.bottom)

            if showContinue && isModal {
                Button(action: {
                    withAnimation {
                        dismiss()
                    }
                }) {
                    Text("Continue")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .scaleEffect(showContinue ? 1 : 0.6)
                        .animation(.spring(), value: showContinue)
                }
            }
        }
        .padding()
    }

    func totalTaskCount() -> Int {
        taskBreakdown.reduce(0) { count, task in
            count + 1 + task.subtaskPoints.count
        }
    }

    func totalCompletedCount() -> Int {
        taskBreakdown.reduce(0) { count, task in
            let completedSubs = task.subtaskPoints.filter { $0.earned > 0 }.count
            return count + 1 + completedSubs
        }
    }
}

struct CircleProgressView: View {
    let completed: Int
    let total: Int

    var progress: Double {
        total == 0 ? 0 : Double(completed) / Double(total)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 12)

            Circle()
                .trim(from: 0.0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.0), value: progress)

            VStack {
                Text("\(Int(progress * 100))%")
                    .font(.title2)
                    .bold()
                Text("Complete")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
}

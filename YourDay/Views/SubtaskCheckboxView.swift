////
////  SubtaskCheckboxView.swift
////  YourDay
////
////  Created by Rachit Verma on 4/21/25.
////
//
//import SwiftUI
//
//struct SubtaskCheckboxView: View {
//    @Binding var subtask: Subtask
//
//    var body: some View {
//        HStack(spacing: 10) {
//            Button(action: {
//                subtask.isDone.toggle()
//                subtask.completedAt = subtask.isDone ? Date() : nil
//                print("Subtask '\(subtask.title)' toggled to \(subtask.isDone), completedAt: \(String(describing: subtask.completedAt))")
//            }) {
//                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
//                    .foregroundColor(subtask.isDone ? .blue : .gray)
//                    .frame(width: 24, height: 24)
//                    .padding(4)
//                    .background(Color(.systemGray5))
//                    .clipShape(Circle())
//            }
//            .buttonStyle(PlainButtonStyle())
//
//            Text(subtask.title)
//                .font(.subheadline)
//                .lineLimit(1)
//
//            Spacer()
//        }
//    }
//}

//  SubtaskCheckboxView.swift
//  YourDay
//
//  Created by Rachit Verma on 4/21/25.
//

import SwiftUI

struct SubtaskCheckboxView: View {
    @Binding var subtask: Subtask

    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                subtask.isDone.toggle()
                subtask.completedAt = subtask.isDone ? Date() : nil
                print("Subtask '\(subtask.title)' toggled to \(subtask.isDone), completedAt: \(String(describing: subtask.completedAt))")
            }) {
                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                    // Themed colors for checkbox icon
                    .foregroundColor(subtask.isDone ? plantDarkGreen : plantDustyBlue)
                    .frame(width: 24, height: 24)
                    .padding(4)
                    // Themed background for checkbox circle
                    .background(subtask.isDone ? plantLightMintGreen.opacity(0.6) : plantPastelGreen.opacity(0.3))
                    .clipShape(Circle())
                    .overlay( // Add a subtle border to checkbox
                        Circle()
                            .stroke(subtask.isDone ? plantDarkGreen : plantDustyBlue, lineWidth: 1.5)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Text(subtask.title)
                .font(.subheadline)
                .lineLimit(1)
                // Themed colors for subtask title text
                .foregroundColor(subtask.isDone ? plantDustyBlue.opacity(0.7) : plantMediumGreen)
                .strikethrough(subtask.isDone, color: plantDustyBlue.opacity(0.7)) // Themed strikethrough color

            Spacer()
        }
    }
}


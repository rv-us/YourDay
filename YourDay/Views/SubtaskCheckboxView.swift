//
//  SubtaskCheckboxView.swift
//  YourDay
//
//  Created by Rachit Verma on 4/21/25.
//

import SwiftUI

struct SubtaskCheckboxView: View {
    var title: String
    @Binding var isDone: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                isDone.toggle()
                print("Subtask '\(title)' toggled to \(isDone)")
            }) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isDone ? .blue : .gray)
                    .frame(width: 24, height: 24)
                    .padding(4)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())

            Text(title)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()
        }
    }
}



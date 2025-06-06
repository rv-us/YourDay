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
                    .foregroundColor(subtask.isDone ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                    .frame(width: 24, height: 24)
                    .padding(4)
                    .background(subtask.isDone ? dynamicPrimaryColor.opacity(0.2) : dynamicSecondaryBackgroundColor)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(subtask.isDone ? dynamicPrimaryColor : dynamicSecondaryTextColor, lineWidth: 1.5)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Text(subtask.title)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundColor(subtask.isDone ? dynamicSecondaryTextColor : dynamicTextColor)
                .strikethrough(subtask.isDone, color: dynamicSecondaryTextColor)

            Spacer()
        }
    }
}

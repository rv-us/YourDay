import SwiftUI
import SwiftData

struct NoteDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State var note: NoteItem
    @State private var editedText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $editedText)
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(dynamicSecondaryTextColor.opacity(0.5), lineWidth: 1)
                )
                .frame(minHeight: 250, idealHeight: 400, maxHeight: .infinity)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .foregroundColor(dynamicTextColor)
                .textInputAutocapitalization(.sentences)
                .scrollContentBackground(.hidden)
        }
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .onAppear {
            editedText = note.content
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Edit Note")
                    .fontWeight(.bold)
                    .foregroundColor(dynamicTextColor)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    note.content = editedText
                    try? context.save()
                    dismiss()
                }
                .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .foregroundColor(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? dynamicSecondaryTextColor.opacity(0.5) : dynamicPrimaryColor)
            }
        }
    }
}

import SwiftUI
import SwiftData

struct NewNoteView: View {
    @Environment(\.modelContext) private var context
    @Binding var isPresented: Bool
    @State private var noteText: String = ""
    var onNoteCreated: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                TextEditor(text: $noteText)
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(dynamicPrimaryColor)
                }
                ToolbarItem(placement: .principal) {
                    Text("New Note")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let newNote = NoteItem(content: noteText)
                        context.insert(newNote)
                        onNoteCreated?()
                        isPresented = false
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundColor(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? dynamicSecondaryTextColor.opacity(0.5) : dynamicPrimaryColor)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

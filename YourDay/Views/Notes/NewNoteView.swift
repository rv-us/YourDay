import SwiftUI
import SwiftData
import FirebaseAuth

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
                        
                        // Sync new note to Firebase
                        if let userId = FirebaseAuth.Auth.auth().currentUser?.uid {
                            let codableNote = NoteItemCodable(from: newNote, userId: userId)
                            FirebaseManager.shared.saveNoteItem(codableNote) { error in
                                if let error = error {
                                    print("NewNoteView: Failed to sync new note to Firebase: \(error.localizedDescription)")
                                } else {
                                    print("NewNoteView: Successfully synced new note to Firebase")
                                }
                            }
                        }
                        
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

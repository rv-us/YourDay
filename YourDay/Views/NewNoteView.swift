//
//  NewNoteView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/27/25.
//

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
                // Replaced Form with a direct VStack containing TextEditor
                TextEditor(text: $noteText)
                    .padding() // Padding inside the editor
                    .background(plantPastelGreen.opacity(0.3)) // Softer background for text editor content
                    .cornerRadius(12) // Slightly larger corner radius for a softer look
                    .overlay( // Add a subtle border
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(plantMediumGreen.opacity(0.5), lineWidth: 1)
                    )
                    .frame(minHeight: 250, idealHeight: 400, maxHeight: .infinity) // Flexible height
                    .padding(.horizontal) // Padding around the text editor block
                    .padding(.vertical, 10) // Vertical padding for separation
                    .foregroundColor(plantDarkGreen) // Text color
                    .textInputAutocapitalization(.sentences) // Good default for notes
                    .scrollContentBackground(.hidden) // Hide default scroll background if needed
            }
            .background(plantBeige.edgesIgnoringSafeArea(.all)) // Apply background to the entire view
            .navigationTitle("") // Hide default title
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(plantLightMintGreen, for: .navigationBar) // Custom toolbar background
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(plantDarkGreen) // Apply color
                }
                ToolbarItem(placement: .principal) { // Custom title
                    Text("New Note")
                        .fontWeight(.bold)
                        .foregroundColor(plantDarkGreen)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let newNote = NoteItem(content: noteText)
                        context.insert(newNote)
                        onNoteCreated?()
                        isPresented = false
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundColor(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? plantDustyBlue.opacity(0.5) : plantDarkGreen) // Dynamic color
                }
            }
        }
        .navigationViewStyle(.stack) // Consistent navigation style
    }
}

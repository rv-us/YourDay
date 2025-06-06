//
//  NoteDetailView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/27/25.
//

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
        .onAppear {
            editedText = note.content
        }
        .navigationTitle("") // Hide default title
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(plantLightMintGreen, for: .navigationBar) // Custom toolbar background
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) { // Custom title
                Text("Edit Note")
                    .fontWeight(.bold)
                    .foregroundColor(plantDarkGreen)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    note.content = editedText
                    try? context.save()
                    dismiss()
                }
                .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .foregroundColor(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? plantDustyBlue.opacity(0.5) : plantDarkGreen) // Dynamic color
            }
        }
    }
}

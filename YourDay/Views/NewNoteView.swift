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

    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $noteText)
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding()

                Spacer()
            }
            .navigationTitle("New Note")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let newNote = NoteItem(content: noteText)
                        context.insert(newNote)
                        isPresented = false
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}


//#Preview {
//    NewNoteView()
//}

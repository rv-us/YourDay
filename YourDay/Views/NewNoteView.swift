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
                Form {
                    Section(header: Text("New Note").font(.title2).bold()) {
                        TextEditor(text: $noteText)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(10)
                            .frame(minHeight: 400)
                    }
                    .edgesIgnoringSafeArea(.bottom)
                }
                .scrollContentBackground(.hidden)
                .background(Color(UIColor.systemBackground))
            }
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
                        onNoteCreated?()
                        isPresented = false
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

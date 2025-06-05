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
            Form {
                Section(header: Text("Edit Note").font(.headline)) {
                    TextEditor(text: $editedText)
                        .frame(minHeight: 400, maxHeight: .infinity)
                        .padding(8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                }
            }
        }
        .onAppear {
            editedText = note.content
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    note.content = editedText
                    try? context.save()
                    dismiss()
                }
            }
        }
    }
}

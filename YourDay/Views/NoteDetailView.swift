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
        VStack {
            TextEditor(text: $editedText)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                .padding()

            Spacer()
        }
        .onAppear {
            editedText = note.content
        }
        .navigationTitle("Edit Note")
        .toolbar {
            Button("Save") {
                note.content = editedText
                try? context.save()
                dismiss()
            }
        }
    }
}


//#Preview {
//    NoteDetailView()
//}

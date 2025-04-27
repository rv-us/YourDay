//
//  AddNotesView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/27/25.
//

import SwiftUI
import SwiftData

struct AddNotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\NoteItem.createdAt, order: .reverse)]) private var notes: [NoteItem]
    @State private var showingNewNoteView = false

    var body: some View {
        NavigationView {
            List {
                ForEach(notes) { note in
                    NavigationLink(destination: NoteDetailView(note: note)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.content.isEmpty ? "New Note" : note.content)
                                .lineLimit(1)
                                .font(.body)
                            Text(note.createdAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        context.delete(notes[index])
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Notes")
            .toolbar {
                Button {
                    showingNewNoteView = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
            .sheet(isPresented: $showingNewNoteView) {
                NewNoteView(isPresented: $showingNewNoteView)
            }
        }
    }
}


#Preview {
    AddNotesView()
}

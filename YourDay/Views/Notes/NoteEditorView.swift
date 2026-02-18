import SwiftUI
import SwiftData
import FirebaseAuth

/// Single view for both creating and editing notes. Pass `note: nil` for new, or an existing `NoteItem` for edit.
/// When `isPresented` is set, the view is shown as a sheet (own NavigationView, Cancel/Done). Otherwise it's pushed (Done only).
struct NoteEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Existing note to edit, or nil for a new note.
    var note: NoteItem?
    /// When non-nil, view is presented as a sheet (dismiss via this binding, show Cancel).
    var isPresented: Binding<Bool>? = nil
    /// Called when a new note is first created (e.g. to refresh list).
    var onNoteCreated: (() -> Void)? = nil

    @State private var text: String = ""
    @State private var createdNote: NoteItem? = nil
    @State private var saveTask: Task<Void, Never>?

    private var isNewNote: Bool { note == nil }
    private var isSheet: Bool { isPresented != nil }

    var body: some View {
        Group {
            if isSheet {
                NavigationView {
                    editorContent
                }
                .navigationViewStyle(.stack)
            } else {
                editorContent
            }
        }
    }

    private var editorContent: some View {
        TextEditor(text: $text)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundColor(dynamicTextColor)
            .scrollContentBackground(.hidden)
            .textInputAutocapitalization(.sentences)
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .onAppear {
            if let note = note {
                text = note.content
            }
        }
        .onChange(of: text) { _, _ in
            saveTask?.cancel()
            if isNewNote {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                saveTask = Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { performAutoSave() }
                }
            } else {
                saveTask = Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { performAutoSave() }
                }
            }
        }
        .onDisappear {
            saveTask?.cancel()
            if isNewNote {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    performAutoSave()
                }
            } else if let note = note, note.content != text {
                note.content = text
                try? context.save()
                syncNoteToFirebase(note)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(isNewNote ? "New Note" : "Edit Note")
                    .fontWeight(.bold)
                    .foregroundColor(dynamicTextColor)
            }
            if isSheet {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented?.wrappedValue = false
                    }
                    .foregroundColor(dynamicPrimaryColor)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    if isNewNote, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        performAutoSave()
                    } else if !isNewNote {
                        performAutoSave()
                    }
                    onNoteCreated?()
                    if isSheet {
                        isPresented?.wrappedValue = false
                    } else {
                        dismiss()
                    }
                }
                .foregroundColor(dynamicPrimaryColor)
            }
        }
    }

    private func performAutoSave() {
        if let existing = note {
            existing.content = text
            try? context.save()
            syncNoteToFirebase(existing)
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let created = createdNote {
                created.content = text
                try? context.save()
                syncNoteToFirebase(created)
            } else if !trimmed.isEmpty {
                let newNote = NoteItem(content: text)
                context.insert(newNote)
                try? context.save()
                createdNote = newNote
                syncNoteToFirebase(newNote)
                onNoteCreated?()
            }
        }
    }

    private func syncNoteToFirebase(_ note: NoteItem) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let codableNote = NoteItemCodable(from: note, userId: userId)
        FirebaseManager.shared.saveNoteItem(codableNote) { error in
            if let error = error {
                print("NoteEditorView: Failed to sync note to Firebase: \(error.localizedDescription)")
            } else {
                print("NoteEditorView: Successfully synced note to Firebase")
            }
        }
    }
}

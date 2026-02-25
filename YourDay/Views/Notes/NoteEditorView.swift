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
    /// Font size for new note before first save (persisted to note after).
    @State private var pendingFontSize: Double? = nil

    private static let fontSizes: [Double] = [14, 17, 20, 24]
    private var currentFontSize: Double {
        note?.fontSize ?? createdNote?.fontSize ?? pendingFontSize ?? 17
    }
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
            .font(.system(size: currentFontSize))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundColor(dynamicTextColor)
            .scrollContentBackground(.hidden)
            .textInputAutocapitalization(.sentences)
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                noteFormatToolbar
            }
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

    private var noteFormatToolbar: some View {
        HStack(spacing: 24) {
            Button {
                insertBullet()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20))
                    .foregroundColor(dynamicTextColor)
            }
            Button {
                insertChecklist()
            } label: {
                Image(systemName: "checklist")
                    .font(.system(size: 20))
                    .foregroundColor(dynamicTextColor)
            }
            Button {
                cycleFontSize()
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 20))
                    .foregroundColor(dynamicTextColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(dynamicSecondaryBackgroundColor)
    }

    private func insertBullet() {
        if text.isEmpty {
            text = "• "
        } else {
            text += "\n• "
        }
    }

    private func insertChecklist() {
        if text.isEmpty {
            text = "☐ "
        } else {
            text += "\n☐ "
        }
    }

    private func cycleFontSize() {
        let current = currentFontSize
        let idx = Self.fontSizes.firstIndex(of: current) ?? 1
        let next = Self.fontSizes[(idx + 1) % Self.fontSizes.count]
        if let note = note {
            note.fontSize = next
            try? context.save()
            syncNoteToFirebase(note)
        } else if let created = createdNote {
            created.fontSize = next
            try? context.save()
            syncNoteToFirebase(created)
        } else {
            pendingFontSize = next
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
                let newNote = NoteItem(content: text, fontSize: pendingFontSize)
                context.insert(newNote)
                try? context.save()
                createdNote = newNote
                pendingFontSize = nil
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

import SwiftUI
import SwiftData
import UIKit
import FirebaseAuth

struct NoteEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var note: NoteItem?
    var isPresented: Binding<Bool>? = nil
    var onNoteCreated: (() -> Void)? = nil

    @State private var attributed: NSAttributedString = NSAttributedString(string: "")
    @State private var createdNote: NoteItem? = nil
    @State private var saveTask: Task<Void, Never>?
    @State private var pendingFontSize: Double? = nil
    @State private var textView: RichNoteUITextView?
    @State private var didLoadInitial = false

    private static let fontSizes: [Double] = [14, 17, 20, 24]

    private var activeNote: NoteItem? { note ?? createdNote }
    private var currentFontSize: Double { activeNote?.fontSize ?? pendingFontSize ?? 17 }
    private var isNewNote: Bool { note == nil }
    private var isSheet: Bool { isPresented != nil }

    var body: some View {
        Group {
            if isSheet {
                NavigationView { editorContent }.navigationViewStyle(.stack)
            } else {
                editorContent
            }
        }
    }

    private var editorContent: some View {
        RichNoteTextView(
            attributedText: $attributed,
            fontSize: CGFloat(currentFontSize),
            textColor: UIColor(dynamicTextColor),
            tintColor: UIColor(dynamicPrimaryColor),
            onChange: { scheduleSave() },
            onViewMade: { tv in
                DispatchQueue.main.async { textView = tv }
            }
        )
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .safeAreaInset(edge: .bottom, spacing: 0) { noteFormatToolbar }
        .onAppear { loadInitialAttributed() }
        .onDisappear { finalSave() }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { toolbarItems }
    }

    // MARK: - Load / migrate

    private func loadInitialAttributed() {
        guard !didLoadInitial else { return }
        didLoadInitial = true
        if let note {
            attributed = note.loadAttributedString(defaultFontSize: CGFloat(currentFontSize))
        } else {
            attributed = NSAttributedString(
                string: "",
                attributes: [
                    .font: UIFont.systemFont(ofSize: CGFloat(currentFontSize)),
                    .foregroundColor: UIColor(dynamicTextColor),
                ]
            )
        }
    }

    // MARK: - Save

    private func scheduleSave() {
        saveTask?.cancel()
        guard !isAttributedEmpty() else { return }
        let delay: UInt64 = isNewNote ? 1_500_000_000 : 1_200_000_000
        saveTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run { performSave() }
        }
    }

    private func isAttributedEmpty() -> Bool {
        attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !containsChecklistAttachment()
    }

    private func containsChecklistAttachment() -> Bool {
        var found = false
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            if value is ChecklistAttachment {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private func finalSave() {
        saveTask?.cancel()
        if isNewNote {
            guard !isAttributedEmpty() else { return }
            performSave()
        } else if let note = note {
            note.saveAttributedString(attributed)
            try? context.save()
            syncNoteToFirebase(note)
        }
    }

    private func performSave() {
        if let existing = note {
            existing.saveAttributedString(attributed)
            try? context.save()
            syncNoteToFirebase(existing)
        } else if let created = createdNote {
            created.saveAttributedString(attributed)
            try? context.save()
            syncNoteToFirebase(created)
        } else {
            let newNote = NoteItem(content: "", fontSize: pendingFontSize)
            newNote.saveAttributedString(attributed)
            context.insert(newNote)
            try? context.save()
            createdNote = newNote
            pendingFontSize = nil
            syncNoteToFirebase(newNote)
            onNoteCreated?()
        }
    }

    private func syncNoteToFirebase(_ note: NoteItem) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let codableNote = NoteItemCodable(from: note, userId: userId)
        FirebaseManager.shared.saveNoteItem(codableNote) { error in
            if let error = error {
                print("NoteEditorView: Failed to sync note to Firebase: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Toolbar

    private var noteFormatToolbar: some View {
        HStack(spacing: 24) {
            Button {
                textView?.applyList(.bullet)
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20))
                    .foregroundColor(dynamicTextColor)
            }
            Button {
                textView?.applyList(.checklist)
            } label: {
                Image(systemName: "checklist")
                    .font(.system(size: 20))
                    .foregroundColor(dynamicTextColor)
            }
            Button {
                textView?.applyList(.none)
            } label: {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 20))
                    .foregroundColor(dynamicTextColor)
            }
            Button { cycleFontSize() } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 20))
                    .foregroundColor(dynamicTextColor)
            }
            Spacer()
            Button {
                textView?.resignFirstResponder()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 20))
                    .foregroundColor(dynamicSecondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(dynamicSecondaryBackgroundColor)
    }

    private func cycleFontSize() {
        let current = currentFontSize
        let idx = Self.fontSizes.firstIndex(of: current) ?? 1
        let next = Self.fontSizes[(idx + 1) % Self.fontSizes.count]
        if let note = activeNote {
            note.fontSize = next
            try? context.save()
            syncNoteToFirebase(note)
        } else {
            pendingFontSize = next
        }
        textView?.applyFontSize(CGFloat(next))
        // Reflect back into the binding so the representable doesn't overwrite it
        if let tv = textView {
            attributed = tv.attributedText
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
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
                if !isAttributedEmpty() { performSave() }
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

import Foundation

// MARK: - Legacy block model
//
// These types exist purely to support migration from the old block-based
// note storage format to the new rich-text (attributed-string) format.
// New notes are no longer stored as NoteBlock arrays.

enum NoteBlockKind: String, Codable {
    case body
    case bullet
    case checklist
}

struct NoteBlock: Codable, Identifiable, Equatable {
    var id: String
    var kind: NoteBlockKind
    var text: String
    var isChecked: Bool

    init(id: String = UUID().uuidString,
         kind: NoteBlockKind,
         text: String = "",
         isChecked: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.isChecked = isChecked
    }
}

import Foundation
import UIKit

// MARK: - Storage format
//
// NoteItem.content is a String. We use a prefix marker to distinguish formats:
//
//   "richv1:<base64>"  → archived NSAttributedString (current format, supports
//                        bullets and checklists)
//   "[...]"            → legacy JSON array of NoteBlock (migrated on load)
//   anything else       → legacy plain text (migrated on load)

private let kRichPrefix = "richv1:"
private let kBulletCharacter = "\u{2022}"
private let kAttachmentCharacter: Character = "\u{FFFC}"
private let kObjectReplacementScalar = "\u{FFFC}"

extension NoteItem {

    // MARK: - Load

    /// Decodes the note's content into an NSAttributedString, migrating legacy
    /// storage formats on the fly. Does NOT mutate `content`; call
    /// `saveAttributedString(_:)` to persist changes.
    func loadAttributedString(defaultFontSize: CGFloat = 17) -> NSAttributedString {
        let size = CGFloat(fontSize ?? Double(defaultFontSize))

        // 1. Modern archived format
        if content.hasPrefix(kRichPrefix) {
            let b64 = String(content.dropFirst(kRichPrefix.count))
            if let data = Data(base64Encoded: b64),
               let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) {
                unarchiver.requiresSecureCoding = false
                if let attr = unarchiver.decodeObject(
                    of: [NSAttributedString.self,
                         NSMutableAttributedString.self,
                         ChecklistAttachment.self,
                         NSTextAttachment.self,
                         NSParagraphStyle.self,
                         NSMutableParagraphStyle.self,
                         UIColor.self,
                         UIFont.self],
                    forKey: NSKeyedArchiveRootObjectKey
                ) as? NSAttributedString {
                    return Self.repairTextChecklistMarkers(in: attr, fontSize: size)
                }
            }
            return NSAttributedString(string: "", attributes: plainAttributes(fontSize: size))
        }

        // 2. Legacy NoteBlock JSON
        if content.hasPrefix("["),
           let data = content.data(using: .utf8),
           let blocks = try? JSONDecoder().decode([NoteBlock].self, from: data) {
            return Self.attributedString(fromBlocks: blocks, fontSize: size)
        }

        // 3. Legacy plain text
        return Self.attributedString(fromPlainText: content, fontSize: size)
    }

    // MARK: - Save

    /// Archives the given NSAttributedString and writes it to `content` using
    /// the modern rich-text format marker.
    func saveAttributedString(_ attr: NSAttributedString) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: attr,
            requiringSecureCoding: false
        ) else { return }
        content = kRichPrefix + data.base64EncodedString()
    }

    // MARK: - Preview / plain-text (used by list views, AI task generation)

    /// First non-empty line, prefixed with a visual marker for bullet/checklist.
    var previewText: String {
        let attr = loadAttributedString()
        let raw = attr.string
        let ns = raw as NSString
        var idx = 0
        while idx < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            let line = ns.substring(with: para)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                // Determine prefix by looking at the paragraph's first character
                if let first = line.first {
                    if String(first) == kBulletCharacter {
                        let rest = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                        return "• " + rest
                    }
                    if first == kAttachmentCharacter {
                        let rest = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                        let isChecked = isCheckedParagraph(attr, paraRange: para)
                        return (isChecked ? "☑ " : "☐ ") + rest
                    }
                }
                return line
            }
            let next = para.location + para.length
            if next <= idx { break }
            idx = next
        }
        return ""
    }

    /// Readable plain-text rendering of the whole note. Used for AI task
    /// generation and other text-only surfaces.
    var plainText: String {
        let attr = loadAttributedString()
        let raw = attr.string
        let ns = raw as NSString
        var out: [String] = []
        var idx = 0
        while idx < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            let line = ns.substring(with: para)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                if let first = line.first {
                    if String(first) == kBulletCharacter {
                        let rest = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                        out.append("• " + rest)
                    } else if first == kAttachmentCharacter {
                        let rest = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                        let isChecked = isCheckedParagraph(attr, paraRange: para)
                        out.append((isChecked ? "[x] " : "[ ] ") + rest)
                    } else {
                        out.append(line)
                    }
                }
            }
            let next = para.location + para.length
            if next <= idx { break }
            idx = next
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Internal helpers

    private func isCheckedParagraph(_ attr: NSAttributedString, paraRange: NSRange) -> Bool {
        guard paraRange.length > 0, paraRange.location < attr.length else { return false }
        let attrs = attr.attributes(at: paraRange.location, effectiveRange: nil)
        if let att = attrs[.attachment] as? ChecklistAttachment {
            return att.isChecked
        }
        return false
    }

    private func plainAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.label,
        ]
    }

    // MARK: - Migration builders

    static func attributedString(fromPlainText text: String, fontSize: CGFloat) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.label,
        ]
        let listPara = NSMutableParagraphStyle()
        listPara.headIndent = fontSize * 1.6
        listPara.firstLineHeadIndent = 0
        listPara.tabStops = [NSTextTab(textAlignment: .left, location: fontSize * 1.6, options: [:])]
        let listAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.label,
            .paragraphStyle: listPara,
        ]

        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: attrs))
            }

            if let checklist = parsePlainChecklistLine(line) {
                appendChecklistLine(
                    text: checklist.text,
                    isChecked: checklist.isChecked,
                    to: result,
                    fontSize: fontSize,
                    listAttributes: listAttrs
                )
            } else if let bulletText = parsePlainBulletLine(line) {
                result.append(NSAttributedString(string: "\u{2022}\t", attributes: listAttrs))
                result.append(NSAttributedString(string: bulletText, attributes: listAttrs))
            } else {
                result.append(NSAttributedString(string: line, attributes: attrs))
            }
        }
        return result
    }

    static func attributedString(fromBlocks blocks: [NoteBlock], fontSize: CGFloat) -> NSAttributedString {
        let plain: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.label,
        ]
        let listPara = NSMutableParagraphStyle()
        listPara.headIndent = fontSize * 1.6
        listPara.firstLineHeadIndent = 0
        listPara.tabStops = [NSTextTab(textAlignment: .left, location: fontSize * 1.6, options: [:])]
        let listAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.label,
            .paragraphStyle: listPara,
        ]

        let result = NSMutableAttributedString()
        for (i, block) in blocks.enumerated() {
            if i > 0 {
                result.append(NSAttributedString(string: "\n", attributes: plain))
            }
            switch block.kind {
            case .body:
                // Legacy body blocks might themselves contain newlines.
                result.append(NSAttributedString(string: block.text, attributes: plain))
            case .bullet:
                result.append(NSAttributedString(string: "\u{2022}\t", attributes: listAttrs))
                result.append(NSAttributedString(string: block.text, attributes: listAttrs))
            case .checklist:
                let att = ChecklistAttachment()
                att.renderFontSize = fontSize
                att.isChecked = block.isChecked
                let attStr = NSMutableAttributedString(attachment: att)
                attStr.addAttributes(listAttrs, range: NSRange(location: 0, length: attStr.length))
                result.append(attStr)
                result.append(NSAttributedString(string: "\t", attributes: listAttrs))
                var textAttrs = listAttrs
                if block.isChecked {
                    textAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    textAttrs[.foregroundColor] = UIColor.secondaryLabel
                }
                result.append(NSAttributedString(string: block.text, attributes: textAttrs))
            }
        }
        return result
    }

    private static func repairTextChecklistMarkers(in attr: NSAttributedString, fontSize: CGFloat) -> NSAttributedString {
        var needsRepair = false
        let raw = attr.string as NSString
        var idx = 0
        while idx < raw.length {
            let para = raw.paragraphRange(for: NSRange(location: idx, length: 0))
            if para.length > 0 {
                let line = raw.substring(with: para).trimmingCharacters(in: .newlines)
                let attrs = attr.attributes(at: para.location, effectiveRange: nil)
                if attrs[.attachment] == nil, parsePlainChecklistLine(line) != nil {
                    needsRepair = true
                    break
                }
            }
            let next = para.location + para.length
            if next <= idx { break }
            idx = next
        }

        guard needsRepair else { return attr }
        return attributedString(fromPlainText: attr.string, fontSize: fontSize)
    }

    private static func parsePlainChecklistLine(_ line: String) -> (isChecked: Bool, text: String)? {
        let trimmedLeading = line.drop { $0 == " " || $0 == "\t" }
        let markerOptions: [(marker: String, isChecked: Bool)] = [
            ("[ ]", false),
            ("[]", false),
            ("[x]", true),
            ("[X]", true),
            ("☐", false),
            ("☑", true),
            ("☒", true),
            (kObjectReplacementScalar, false),
        ]

        for option in markerOptions where trimmedLeading.hasPrefix(option.marker) {
            let remainder = trimmedLeading.dropFirst(option.marker.count)
                .drop { $0 == " " || $0 == "\t" }
            return (option.isChecked, String(remainder))
        }
        return nil
    }

    private static func parsePlainBulletLine(_ line: String) -> String? {
        let trimmedLeading = line.drop { $0 == " " || $0 == "\t" }
        guard trimmedLeading.hasPrefix(kBulletCharacter) else { return nil }
        let remainder = trimmedLeading.dropFirst(kBulletCharacter.count)
            .drop { $0 == " " || $0 == "\t" }
        return String(remainder)
    }

    private static func appendChecklistLine(text: String,
                                            isChecked: Bool,
                                            to result: NSMutableAttributedString,
                                            fontSize: CGFloat,
                                            listAttributes: [NSAttributedString.Key: Any]) {
        let att = ChecklistAttachment()
        att.renderFontSize = fontSize
        att.isChecked = isChecked
        let attStr = NSMutableAttributedString(attachment: att)
        attStr.addAttributes(listAttributes, range: NSRange(location: 0, length: attStr.length))
        result.append(attStr)
        result.append(NSAttributedString(string: "\t", attributes: listAttributes))

        var textAttrs = listAttributes
        if isChecked {
            textAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            textAttrs[.foregroundColor] = UIColor.secondaryLabel
        }
        result.append(NSAttributedString(string: text, attributes: textAttrs))
    }
}

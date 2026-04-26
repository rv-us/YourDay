import SwiftUI
import UIKit

// MARK: - List type

enum NoteListType {
    case none
    case bullet
    case checklist
}

// MARK: - SwiftUI bridge

struct RichNoteTextView: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    let fontSize: CGFloat
    let textColor: UIColor
    let tintColor: UIColor

    let onChange: () -> Void
    /// Called with the underlying UITextView so parent can call `applyList(_:)` etc.
    let onViewMade: (RichNoteUITextView) -> Void

    func makeUIView(context: Context) -> RichNoteUITextView {
        let tv = RichNoteUITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 20, bottom: 80, right: 20)
        tv.textContainer.lineFragmentPadding = 0
        tv.keyboardDismissMode = .interactive
        tv.alwaysBounceVertical = true
        tv.autocapitalizationType = .sentences
        tv.autocorrectionType = .default
        tv.smartDashesType = .default
        tv.smartQuotesType = .default
        tv.tintColor = tintColor
        tv.typingFontSize = fontSize
        tv.typingTextColor = textColor
        tv.typingTintColor = tintColor
        tv.refreshTypingAttributes()
        tv.onChangeExternal = {
            context.coordinator.syncBack()
        }
        context.coordinator.textView = tv
        onViewMade(tv)
        return tv
    }

    func updateUIView(_ tv: RichNoteUITextView, context: Context) {
        tv.typingFontSize = fontSize
        tv.typingTextColor = textColor
        tv.typingTintColor = tintColor
        tv.tintColor = tintColor
        tv.refreshTypingAttributes()

        if tv.attributedText != attributedText {
            let sel = tv.selectedRange
            tv.attributedText = attributedText
            let clamped = NSRange(
                location: min(sel.location, tv.attributedText.length),
                length: 0
            )
            tv.selectedRange = clamped
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichNoteTextView
        weak var textView: RichNoteUITextView?
        private var isSyncing = false

        init(parent: RichNoteTextView) { self.parent = parent }

        func syncBack() {
            guard let tv = textView else { return }
            isSyncing = true
            parent.attributedText = tv.attributedText
            isSyncing = false
            parent.onChange()
        }

        func textViewDidChange(_ textView: UITextView) { syncBack() }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard let tv = textView as? RichNoteUITextView else { return true }
            if text == "\n" { return tv.handleReturn(at: range) }
            if text.contains("\n") { return tv.handleMultiLinePaste(text: text, range: range) }
            return true
        }
    }
}

// MARK: - UITextView subclass

final class RichNoteUITextView: UITextView, UIGestureRecognizerDelegate {
    /// Set by the representable each update.
    var typingFontSize: CGFloat = 17
    var typingTextColor: UIColor = .label
    var typingTintColor: UIColor = .tintColor
    /// Called when the text storage is mutated imperatively (e.g., toggle, apply list).
    var onChangeExternal: (() -> Void)?

    // MARK: Init with explicit TextKit 1 layout manager (needed for attachment control)

    init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = self
        addGestureRecognizer(tapRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    // MARK: - Tap handling for checkboxes

    @objc private func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        _ = handleAttachmentTap(at: recognizer.location(in: self))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @discardableResult
    private func handleAttachmentTap(at point: CGPoint) -> Int? {
        var loc = point
        loc.x -= textContainerInset.left
        loc.y -= textContainerInset.top
        guard loc.x >= 0, loc.y >= 0 else { return nil }

        let glyphIdx = layoutManager.glyphIndex(for: loc, in: textContainer)
        let charIdx = layoutManager.characterIndexForGlyph(at: glyphIdx)
        guard charIdx < textStorage.length else { return nil }

        let attrs = textStorage.attributes(at: charIdx, effectiveRange: nil)
        guard let attachment = attrs[.attachment] as? ChecklistAttachment else { return nil }

        // Require tap roughly within the attachment's glyph rect
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: charIdx, length: 1),
            actualCharacterRange: nil
        )
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard rect.insetBy(dx: -8, dy: -6).contains(loc) else { return nil }

        attachment.isChecked.toggle()
        attachment.tintColorResolved = typingTintColor
        applyStrikethroughForChecklistParagraph(at: charIdx)
        // Force re-layout of this attachment and following strikethrough
        let ns = text as NSString
        let para = ns.paragraphRange(for: NSRange(location: charIdx, length: 0))
        layoutManager.invalidateDisplay(forCharacterRange: para)
        onChangeExternal?()
        return charIdx
    }

    // MARK: - Paragraph list detection

    /// Returns (type, prefixLength in characters) for the paragraph at `paraRange`.
    func listType(in paraRange: NSRange) -> (NoteListType, Int) {
        guard paraRange.length >= 1 else { return (.none, 0) }
        let attrs = textStorage.attributes(at: paraRange.location, effectiveRange: nil)
        if attrs[.attachment] is ChecklistAttachment {
            // attachment character + tab
            let len = paraRange.length >= 2 ? 2 : 1
            return (.checklist, len)
        }
        let ns = textStorage.string as NSString
        let first = ns.substring(with: NSRange(location: paraRange.location, length: 1))
        if first == "\u{2022}" {
            let len = paraRange.length >= 2 ? 2 : 1
            return (.bullet, len)
        }
        return (.none, 0)
    }

    private func baseTextAttributes() -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.headIndent = typingFontSize * 1.6
        para.firstLineHeadIndent = 0
        para.tabStops = [NSTextTab(textAlignment: .left, location: typingFontSize * 1.6, options: [:])]
        return [
            .font: UIFont.systemFont(ofSize: typingFontSize),
            .foregroundColor: typingTextColor,
            .paragraphStyle: para,
        ]
    }

    private func plainTextAttributes() -> [NSAttributedString.Key: Any] {
        // For non-list paragraphs: no tab-stop indent.
        [
            .font: UIFont.systemFont(ofSize: typingFontSize),
            .foregroundColor: typingTextColor,
        ]
    }

    /// Builds "•\t" or attachment+"\t" attributed string.
    func makePrefix(for type: NoteListType) -> NSAttributedString {
        switch type {
        case .none:
            return NSAttributedString(string: "")
        case .bullet:
            return NSAttributedString(string: "\u{2022}\t", attributes: baseTextAttributes())
        case .checklist:
            let att = ChecklistAttachment()
            att.renderFontSize = typingFontSize
            att.tintColorResolved = typingTintColor
            let attr = NSMutableAttributedString(attachment: att)
            attr.addAttributes(baseTextAttributes(), range: NSRange(location: 0, length: attr.length))
            attr.append(NSAttributedString(string: "\t", attributes: baseTextAttributes()))
            return attr
        }
    }

    func refreshTypingAttributes() {
        textColor = typingTextColor
        typingAttributes = plainTextAttributes()
    }

    // MARK: - Return handling

    fileprivate func handleReturn(at range: NSRange) -> Bool {
        let ns = text as NSString
        let paraRange = ns.paragraphRange(for: NSRange(location: range.location, length: 0))
        let (type, prefixLen) = listType(in: paraRange)
        guard type != .none else { return true }

        let paraText = ns.substring(with: paraRange)
        let contentPart = (paraText as NSString)
            .substring(from: min(prefixLen, paraText.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if contentPart.isEmpty {
            // Empty list line + Return → exit list
            textStorage.beginEditing()
            let deleteLen = min(prefixLen, paraRange.length)
            textStorage.deleteCharacters(in: NSRange(location: paraRange.location, length: deleteLen))
            // Reset attributes on the (now empty) paragraph
            let newLoc = paraRange.location
            if newLoc < textStorage.length {
                let afterRange = NSRange(location: newLoc, length: 0)
                let _ = afterRange // placeholder; typing attributes apply going forward
            }
            textStorage.endEditing()
            typingAttributes = plainTextAttributes()
            selectedRange = NSRange(location: paraRange.location, length: 0)
            onChangeExternal?()
            return false
        }

        // Continue list
        let insertion = NSMutableAttributedString(string: "\n", attributes: baseTextAttributes())
        insertion.append(makePrefix(for: type))
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: insertion)
        textStorage.endEditing()
        typingAttributes = baseTextAttributes()
        selectedRange = NSRange(location: range.location + insertion.length, length: 0)
        onChangeExternal?()
        return false
    }

    // MARK: - Multi-line paste

    fileprivate func handleMultiLinePaste(text input: String, range: NSRange) -> Bool {
        let ns = text as NSString
        let paraRange = ns.paragraphRange(for: NSRange(location: range.location, length: 0))
        let (type, _) = listType(in: paraRange)

        let lines = input.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        let attrs = type == .none ? plainTextAttributes() : baseTextAttributes()
        for (i, line) in lines.enumerated() {
            if i > 0 {
                result.append(NSAttributedString(string: "\n", attributes: attrs))
                result.append(makePrefix(for: type))
            }
            result.append(NSAttributedString(string: line, attributes: attrs))
        }

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: result)
        textStorage.endEditing()
        typingAttributes = attrs
        selectedRange = NSRange(location: range.location + result.length, length: 0)
        onChangeExternal?()
        return false
    }

    // MARK: - Apply list to selected paragraphs (toolbar actions)

    func applyList(_ newType: NoteListType) {
        let sel = selectedRange
        let ns = text as NSString
        if ns.length == 0 {
            // Insert one empty line of that type
            if newType != .none {
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: makePrefix(for: newType))
                textStorage.endEditing()
                typingAttributes = baseTextAttributes()
                selectedRange = NSRange(location: textStorage.length, length: 0)
                onChangeExternal?()
            }
            return
        }

        // Collect paragraph starts covered by the selection.
        var paraRanges: [NSRange] = []
        var loc = max(0, min(sel.location, ns.length - 1))
        let end = min(ns.length, sel.location + sel.length)
        // Walk paragraphs forward from `loc` until we pass `end`.
        while loc < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            paraRanges.append(para)
            let next = para.location + para.length
            if next >= ns.length || next > end { break }
            loc = next
        }
        // Handle case where selection length is 0 (single paragraph at cursor)
        if paraRanges.isEmpty {
            paraRanges.append(ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: 0)))
        }

        textStorage.beginEditing()
        // Process in reverse so earlier indices stay valid.
        for paraRange in paraRanges.reversed() {
            let (currentType, prefixLen) = listType(in: paraRange)
            var workingLoc = paraRange.location

            if currentType != .none {
                let del = min(prefixLen, paraRange.length)
                textStorage.deleteCharacters(in: NSRange(location: workingLoc, length: del))
            }

            if newType != .none {
                let prefix = makePrefix(for: newType)
                textStorage.insert(prefix, at: workingLoc)
            } else {
                // Reset paragraph style to plain for the (possibly-shortened) paragraph
                let newLen = max(0, paraRange.length - (currentType == .none ? 0 : prefixLen))
                if newLen > 0 {
                    let plainAttrs = plainTextAttributes()
                    let fixRange = NSRange(location: workingLoc, length: newLen)
                    textStorage.setAttributes(plainAttrs, range: fixRange)
                }
            }
        }
        textStorage.endEditing()

        // Apply / remove strikethrough based on each paragraph's current checklist state.
        refreshChecklistStrikethroughs()

        typingAttributes = newType == .none ? plainTextAttributes() : baseTextAttributes()
        onChangeExternal?()
    }

    // MARK: - Strikethrough helpers

    private func applyStrikethroughForChecklistParagraph(at location: Int) {
        let ns = text as NSString
        let para = ns.paragraphRange(for: NSRange(location: location, length: 0))
        let (type, prefixLen) = listType(in: para)
        guard type == .checklist, para.length > prefixLen else { return }
        let attrs = textStorage.attributes(at: para.location, effectiveRange: nil)
        let isChecked = (attrs[.attachment] as? ChecklistAttachment)?.isChecked ?? false

        let contentRange = NSRange(location: para.location + prefixLen,
                                   length: para.length - prefixLen)
        textStorage.beginEditing()
        if isChecked {
            textStorage.addAttribute(.strikethroughStyle,
                                     value: NSUnderlineStyle.single.rawValue,
                                     range: contentRange)
            textStorage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: contentRange)
        } else {
            textStorage.removeAttribute(.strikethroughStyle, range: contentRange)
            textStorage.addAttribute(.foregroundColor, value: typingTextColor, range: contentRange)
        }
        textStorage.endEditing()
    }

    // MARK: - Font size

    /// Re-applies the given font size across the entire attributed string,
    /// including attachment render size and paragraph indent/tab stops.
    func applyFontSize(_ size: CGFloat) {
        typingFontSize = size
        guard textStorage.length > 0 else {
            typingAttributes = [
                .font: UIFont.systemFont(ofSize: size),
                .foregroundColor: typingTextColor,
            ]
            return
        }

        let listPara = NSMutableParagraphStyle()
        listPara.headIndent = size * 1.6
        listPara.firstLineHeadIndent = 0
        listPara.tabStops = [NSTextTab(textAlignment: .left, location: size * 1.6, options: [:])]

        textStorage.beginEditing()
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttribute(.font, value: UIFont.systemFont(ofSize: size), range: full)

        // Update each paragraph's style + attachment size if this is a list line.
        let ns = textStorage.string as NSString
        var idx = 0
        while idx < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            let (type, _) = listType(in: para)
            if type != .none {
                textStorage.addAttribute(.paragraphStyle, value: listPara, range: para)
            }
            if type == .checklist, para.length > 0 {
                let attrs = textStorage.attributes(at: para.location, effectiveRange: nil)
                if let att = attrs[.attachment] as? ChecklistAttachment {
                    att.renderFontSize = size
                }
            }
            let next = para.location + para.length
            if next <= idx { break }
            idx = next
        }
        textStorage.endEditing()
        layoutManager.invalidateDisplay(forCharacterRange: full)
    }

    func refreshChecklistStrikethroughs() {
        let ns = text as NSString
        var idx = 0
        while idx < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            applyStrikethroughForChecklistParagraph(at: para.location)
            let next = para.location + para.length
            if next <= idx { break }
            idx = next
        }
    }
}

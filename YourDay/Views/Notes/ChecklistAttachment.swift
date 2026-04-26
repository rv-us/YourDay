import UIKit

/// NSTextAttachment that renders a checkbox (unchecked / checked) and encodes its state.
/// Tapping is handled by `RichNoteUITextView`.
final class ChecklistAttachment: NSTextAttachment {
    var isChecked: Bool = false
    var renderFontSize: CGFloat = 17
    var tintColorResolved: UIColor = .tintColor

    override init(data contentData: Data? = nil, ofType uti: String? = nil) {
        super.init(data: contentData, ofType: uti)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.isChecked = coder.decodeBool(forKey: "yd_isChecked")
        let size = coder.decodeDouble(forKey: "yd_fontSize")
        self.renderFontSize = size > 0 ? CGFloat(size) : 17
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(isChecked, forKey: "yd_isChecked")
        coder.encode(Double(renderFontSize), forKey: "yd_fontSize")
    }

    override func image(forBounds imageBounds: CGRect,
                        textContainer: NSTextContainer?,
                        characterIndex charIndex: Int) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: renderFontSize, weight: .regular)
        let name = isChecked ? "checkmark.circle.fill" : "circle"
        let image = UIImage(systemName: name, withConfiguration: config)
        let color: UIColor = isChecked ? tintColorResolved : .secondaryLabel
        return image?.withTintColor(color, renderingMode: .alwaysOriginal)
    }

    override func attachmentBounds(for textContainer: NSTextContainer?,
                                   proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint,
                                   characterIndex charIndex: Int) -> CGRect {
        let size = renderFontSize * 1.05
        let yOffset: CGFloat = -3
        return CGRect(x: 0, y: yOffset, width: size, height: size)
    }
}

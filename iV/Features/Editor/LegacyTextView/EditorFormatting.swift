import AppKit

enum EditorFormatting {
    enum Style: String {
        case bold, italic, underline
        case heading1, heading2, body
    }

    static func toggleBold(in textView: NSTextView) {
        toggleFontTrait(.boldFontMask, in: textView)
    }

    static func toggleItalic(in textView: NSTextView) {
        toggleFontTrait(.italicFontMask, in: textView)
    }

    static func toggleUnderline(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        storage.beginEditing()
        if storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) != nil {
            storage.removeAttribute(.underlineStyle, range: range)
        } else {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        storage.endEditing()
    }

    static func applyHeading(_ level: Int, in textView: NSTextView) {
        let base = IVTheme.manuscriptPointSize
        let sizes: [CGFloat] = [base + 8, base + 4, base]
        let size = sizes[min(max(level - 1, 0), sizes.count - 1)]
        guard let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        let body = IVTheme.manuscriptFont
        let font = NSFontManager.shared.convert(
            body,
            toHaveTrait: level <= 2 ? .boldFontMask : []
        )
        let sized = NSFontManager.shared.convert(font, toSize: size)
        storage.addAttribute(.font, value: sized, range: range)
    }

    private static func toggleFontTrait(_ trait: NSFontTraitMask, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
            let current = (value as? NSFont) ?? IVTheme.manuscriptFont
            let family = current.familyName ?? IVTheme.manuscriptFont.familyName!
            let size = current.pointSize
            var traits = NSFontManager.shared.traits(of: current)
            if traits.contains(trait) {
                traits.remove(trait)
            } else {
                traits.insert(trait)
            }
            let newFont = NSFontManager.shared.font(
                withFamily: family,
                traits: traits,
                weight: 5,
                size: size
            ) ?? current
            storage.addAttribute(.font, value: newFont, range: subRange)
        }
        storage.endEditing()
    }
}

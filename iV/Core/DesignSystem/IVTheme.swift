import AppKit
import SwiftUI

/// Central brand color tokens — see `docs/BRAND_BOOK.md`.
enum IVColor {
    // MARK: Forest (chrome)
    static let forestBlack = Color(hex: 0x0F1A14)
    static let forestDeep = Color(hex: 0x0F1F18)
    static let forestSurface = Color(hex: 0x152418)
    static let forestElevated = Color(hex: 0x1E2E25)
    static let forestHover = Color(hex: 0x274037)

    // MARK: Ivy (accent — restrained; UI uses muted variants)
    static let ivyPrimary = Color(hex: 0x2E7D5B)
    static let ivyBright = Color(hex: 0x3FA370)
    static let ivySoft = Color(hex: 0x64C080)
    static let ivyGlow = Color(hex: 0xA7E0C1)
    /// Desaturated ivy for toolbar accents, logo, active UI (round 2).
    static let ivyUI = Color(hex: 0x3A6B58)
    static let ivyUILight = Color(hex: 0x4D7F6A)

    // MARK: Document (manuscript only)
    static let documentSurface = Color(hex: 0xF6F7F8)
    static let documentSecondary = Color(hex: 0xE5E7E8)
    static let documentText = Color(hex: 0x111827)
    static let documentMuted = Color(hex: 0x687280)

    // MARK: Diagnostics (muted editorial)
    static let diagnosticInfo = Color(hex: 0x5B7C99)
    static let diagnosticWarning = Color(hex: 0xB8860B)
    static let diagnosticError = Color(hex: 0xC45C4A)
    static let diagnosticBlocking = Color(hex: 0x9B4D6A)
    static let diagnosticSuccess = Color(hex: 0x2E7D5B)

    // MARK: Firefly (warm micro-accent — hover/focus edge; not ivy green)
    static let fireflyCore = Color(hex: 0xFFF7D6)
    static let fireflyWarm = Color(hex: 0xFFD66B)
    static let fireflyAmber = Color(hex: 0xF5A524)
    static let fireflySoftShadow = Color(hex: 0xFFD66B).opacity(0.28)

    static var forestBlackNS: NSColor { nsColor(0x0F1A14) }
    static var forestSurfaceNS: NSColor { nsColor(0x152418) }
    static var documentSurfaceNS: NSColor { nsColor(0xF6F7F8) }
    static var documentTextNS: NSColor { nsColor(0x111827) }
    static var documentMutedNS: NSColor { nsColor(0x687280) }
}

/// Typography tokens — see `docs/BRAND_BOOK.md` §4 and `.cursor/rules/56-typography-system.mdc`.
enum IVTheme {
    // MARK: Manuscript (editor body)

    /// Default manuscript size — 17–19pt range; 18pt target.
    static let manuscriptPointSize: CGFloat = 18

    /// Primary manuscript family per brand book.
    static let primaryManuscriptFamily = "New York"

    /// Single-family fallback chain (first match wins).
    static let manuscriptFallbackFamilies = [
        "New York",
        "Charter",
        "Literata",
        "Source Serif Pro",
        "Crimson Pro",
        "Times New Roman"
    ]

    static var manuscriptFont: NSFont {
        resolveManuscriptFont(size: manuscriptPointSize)
    }

    /// Editorial line/paragraph rhythm for long-form prose.
    static var manuscriptParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = 10
        style.paragraphSpacingBefore = 0
        style.lineBreakMode = .byWordWrapping
        return style
    }

    static var manuscriptDefaultTypingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: manuscriptFont,
            .foregroundColor: IVColor.documentTextNS,
            .paragraphStyle: manuscriptParagraphStyle
        ]
    }

    static func resolveManuscriptFont(size: CGFloat = manuscriptPointSize) -> NSFont {
        for family in manuscriptFallbackFamilies {
            if let font = NSFont(name: family, size: size) { return font }
            if let font = NSFont(name: "\(family)-Regular", size: size) { return font }
            if let font = NSFont(name: "\(family) Regular", size: size) { return font }
        }
        return NSFont.systemFont(ofSize: size)
    }

    // MARK: UI (SF Pro via system fonts)

    static let uiHeaderSize: CGFloat = 17
    static let uiBodySize: CGFloat = 13
    static let uiCaptionSize: CGFloat = 11
    static let uiSmallCaptionSize: CGFloat = 10

    static var uiHeaderFont: NSFont {
        NSFont.systemFont(ofSize: uiHeaderSize, weight: .semibold)
    }

    static var uiBodyFont: NSFont {
        NSFont.systemFont(ofSize: uiBodySize, weight: .regular)
    }

    static var uiCaptionFont: NSFont {
        NSFont.systemFont(ofSize: uiCaptionSize, weight: .regular)
    }

    static var uiSmallCaptionFont: NSFont {
        NSFont.systemFont(ofSize: uiSmallCaptionSize, weight: .regular)
    }

    // MARK: Monospace

    static let monoSize: CGFloat = 12

    static var monoFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: monoSize, weight: .regular)
    }

    /// Comfortable prose column for manuscript surface wrapper.
    static let manuscriptColumnWidth: CGFloat = 720
}

// MARK: - SwiftUI font helpers

extension Font {
    static var ivManuscript: Font { Font(IVTheme.manuscriptFont) }
    static var ivUIHeader: Font { Font(IVTheme.uiHeaderFont) }
    static var ivUIBody: Font { Font(IVTheme.uiBodyFont) }
    static var ivUICaption: Font { Font(IVTheme.uiCaptionFont) }
    static var ivMono: Font { Font(IVTheme.monoFont) }
}

extension View {
    func ivUIHeader() -> some View {
        font(.ivUIHeader).foregroundStyle(IVColor.chromePrimary)
    }

    func ivUIBody() -> some View {
        font(.ivUIBody).foregroundStyle(IVColor.chromePrimary)
    }

    func ivUICaption() -> some View {
        font(.ivUICaption).foregroundStyle(IVColor.chromeSecondary)
    }

    func ivManuscriptText() -> some View {
        font(.ivManuscript).foregroundStyle(IVColor.documentText)
    }
}

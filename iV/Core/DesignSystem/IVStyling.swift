import AppKit
import SwiftUI

// MARK: - Semantic text

extension IVColor {
    /// Primary UI on forest chrome — clearly readable, not disabled-looking.
    static let chromePrimary = Color(hex: 0xE8EDEA)
    /// Muted labels, descriptions — readable secondary.
    static let chromeSecondary = Color(hex: 0xB8C4BE)
    /// Tertiary metadata — still legible.
    static let chromeTertiary = Color(hex: 0x8A9A92)
    /// Real disabled controls only.
    static let chromeDisabled = Color(hex: 0x5C6B64)

    static var diagnosticInfoNS: NSColor { nsColor(0x5B7C99) }
    static var diagnosticWarningNS: NSColor { nsColor(0xB8860B) }
    static var diagnosticErrorNS: NSColor { nsColor(0xC45C4A) }
    static var diagnosticBlockingNS: NSColor { nsColor(0x9B4D6A) }
    static var ivyPrimaryNS: NSColor { nsColor(0x2E7D5B) }
    static var forestElevatedNS: NSColor { nsColor(0x1E2E25) }
    static var forestHoverNS: NSColor { nsColor(0x274037) }
    static var documentSecondaryNS: NSColor { nsColor(0xE5E7E8) }
    static var ivyGlowNS: NSColor { nsColor(0xA7E0C1) }
    static var ivySoftNS: NSColor { nsColor(0x64C080) }

    static func nsColor(_ hex: UInt32) -> NSColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }
}

extension RuleSeverity {
    var ivColor: Color {
        switch self {
        case .info: IVColor.diagnosticInfo
        case .warning: IVColor.diagnosticWarning
        case .error: IVColor.diagnosticError
        case .blocking: IVColor.diagnosticBlocking
        }
    }

    var ivNSColor: NSColor {
        switch self {
        case .info: IVColor.diagnosticInfoNS
        case .warning: IVColor.diagnosticWarningNS
        case .error: IVColor.diagnosticErrorNS
        case .blocking: IVColor.diagnosticBlockingNS
        }
    }
}

enum IVDiffColors {
    static let insertBackground = Color(hex: 0xA7E0C1).opacity(0.35)
    static let deleteBackground = Color(hex: 0xC45C4A).opacity(0.22)
    static let lightOriginal = Color(hex: 0xE5E7E8).opacity(0.9)
    static let lightProposed = Color(hex: 0xA7E0C1).opacity(0.28)
}

// MARK: - View modifiers

private struct IVAppChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(IVColor.forestBlack)
            .foregroundStyle(IVColor.chromePrimary)
            .tint(IVColor.ivyUI)
            .preferredColorScheme(.dark)
    }
}

private struct IVForestPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(IVColor.forestSurface)
    }
}

private struct IVForestElevatedBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(IVColor.forestElevated)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(IVColor.forestHover.opacity(IVLayout.chromeDividerOpacity))
                    .frame(height: 1)
            }
    }
}

private struct IVSheetChromeModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .padding(.vertical, IVLayout.chromeEdgeGap)
            .background(IVColor.forestElevated)
            .foregroundStyle(IVColor.chromePrimary)
            .tint(IVColor.ivyUI)
            .preferredColorScheme(.dark)
            .ivEscapeToDismiss { dismiss() }
    }
}

private struct IVLibraryCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(IVLayout.stackM)
    }
}

private struct IVInspectorListModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
    }
}

extension View {
    func ivAppChrome() -> some View {
        modifier(IVAppChromeModifier())
    }

    func ivForestPanel() -> some View {
        modifier(IVForestPanelModifier())
    }

    func ivForestElevatedBar() -> some View {
        modifier(IVForestElevatedBarModifier())
    }

    func ivSheetChrome() -> some View {
        modifier(IVSheetChromeModifier())
    }

    func ivLibraryCard() -> some View {
        modifier(IVLibraryCardModifier())
    }

    func ivInspectorList() -> some View {
        modifier(IVInspectorListModifier())
    }

    func ivMutedCaption() -> some View {
        font(.caption).foregroundStyle(IVColor.chromeSecondary)
    }

    func ivSecondaryLabel() -> some View {
        foregroundStyle(IVColor.chromeSecondary)
    }
}

// MARK: - Manuscript surface

struct IVManuscriptSurface<Content: View>: View {
    var maxContentWidth: CGFloat = IVTheme.manuscriptColumnWidth
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            IVColor.documentSurface
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content()
                    .frame(maxWidth: maxContentWidth)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Buttons

/// Toolbar / chrome text control — hover luminosity, native density.
struct IVToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IVFireflyButtonLabel(pressed: configuration.isPressed, ghost: true) {
            configuration.label
                .font(.ivUIBody)
                .foregroundStyle(IVColor.chromePrimary)
        }
    }
}

/// Subtle bordered emphasis for one primary chrome action.
struct IVToolbarAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IVFireflyButtonLabel(pressed: configuration.isPressed, prominent: true) {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(IVColor.chromePrimary)
        }
    }
}

struct IVPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IVFireflyButtonLabel(pressed: configuration.isPressed, prominent: true) {
            configuration.label
                .font(.ivUIBody)
                .foregroundStyle(IVColor.chromePrimary)
        }
    }
}

struct IVSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IVFireflyButtonLabel(pressed: configuration.isPressed) {
            configuration.label
                .font(.ivUIBody)
                .foregroundStyle(IVColor.chromePrimary)
        }
    }
}

struct IVGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IVFireflyButtonLabel(pressed: configuration.isPressed, ghost: true) {
            configuration.label
                .font(.ivUIBody)
                .foregroundStyle(IVColor.chromePrimary)
        }
    }
}

/// Empty-state / inline action — text link with hover whisper.
struct IVQuietActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IVFireflyButtonLabel(pressed: configuration.isPressed, quiet: true) {
            configuration.label
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(IVColor.chromePrimary)
        }
    }
}

/// Icon / formatting toolbar control.
struct IVIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IVFireflyButtonLabel(pressed: configuration.isPressed, ghost: true, paddingH: 6, paddingV: 4) {
            configuration.label
                .foregroundStyle(IVColor.chromePrimary)
        }
    }
}

extension ButtonStyle where Self == IVToolbarButtonStyle {
    static var ivToolbar: IVToolbarButtonStyle { IVToolbarButtonStyle() }
}

extension ButtonStyle where Self == IVToolbarAccentButtonStyle {
    static var ivToolbarAccent: IVToolbarAccentButtonStyle { IVToolbarAccentButtonStyle() }
}

extension ButtonStyle where Self == IVPrimaryButtonStyle {
    static var ivPrimary: IVPrimaryButtonStyle { IVPrimaryButtonStyle() }
}

extension ButtonStyle where Self == IVSecondaryButtonStyle {
    static var ivSecondary: IVSecondaryButtonStyle { IVSecondaryButtonStyle() }
}

extension ButtonStyle where Self == IVGhostButtonStyle {
    static var ivGhost: IVGhostButtonStyle { IVGhostButtonStyle() }
}

extension ButtonStyle where Self == IVQuietActionButtonStyle {
    static var ivQuietAction: IVQuietActionButtonStyle { IVQuietActionButtonStyle() }
}

extension ButtonStyle where Self == IVIconButtonStyle {
    static var ivIcon: IVIconButtonStyle { IVIconButtonStyle() }
}

// MARK: - Shared diff helpers

enum IVDiffAttributed {
    static func build(from chunks: [TextDiffChunk]) -> AttributedString {
        var result = AttributedString()
        for chunk in chunks {
            var part = AttributedString(chunk.text)
            switch chunk.kind {
            case .unchanged:
                break
            case .inserted:
                part.backgroundColor = IVDiffColors.insertBackground
            case .deleted:
                part.backgroundColor = IVDiffColors.deleteBackground
                part.strikethroughStyle = .single
            }
            result.append(part)
        }
        return result
    }
}

// MARK: - Hex Color (shared)

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

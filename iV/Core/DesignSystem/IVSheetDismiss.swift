import SwiftUI

// MARK: - Sheet dismiss controls

/// Visible close control for sheets, drawers, and floating panels.
struct IVSheetDismissButton: View {
    var title: String = "Close"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                Text(title)
                    .font(.ivUICaption)
            }
            .foregroundStyle(IVColor.chromeSecondary)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Title row with a trailing dismiss button (sheets and modal panels).
struct IVSheetHeaderBar: View {
    let title: String
    var subtitle: String?
    var dismissTitle: String = "Close"
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: IVLayout.stackS) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ivUIHeader)
                    .foregroundStyle(IVColor.chromePrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.ivUICaption)
                        .foregroundStyle(IVColor.chromeSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: IVLayout.stackM)
            IVSheetDismissButton(title: dismissTitle, action: onDismiss)
        }
    }
}

extension View {
    /// Dismiss on Escape (macOS sheets and overlays).
    func ivEscapeToDismiss(_ action: @escaping () -> Void) -> some View {
        onKeyPress(.escape) {
            action()
            return .handled
        }
    }

    /// Standard sheet header + Escape; use inside `.sheet` content.
    func ivSheetScaffold(
        title: String,
        subtitle: String? = nil,
        dismissTitle: String = "Close",
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: IVLayout.stackM) {
            IVSheetHeaderBar(title: title, subtitle: subtitle, dismissTitle: dismissTitle, onDismiss: onDismiss)
            content()
        }
        .ivEscapeToDismiss(onDismiss)
    }
}

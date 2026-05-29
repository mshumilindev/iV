import SwiftUI

// MARK: - Workspace environmental framing

/// Subtle working-field tone — structure without dashboard widgets.
struct IVWorkspaceCanvas: View {
    var body: some View {
        ZStack {
            IVColor.forestBlack
            Rectangle()
                .fill(IVColor.forestDeep.opacity(IVLayout.workspaceFieldOpacity))
                .padding(.horizontal, IVLayout.workspaceInsetH)
                .padding(.vertical, 1)
        }
        .ignoresSafeArea(edges: [.horizontal, .bottom])
    }
}

// MARK: - Integrated top chrome (replaces floating toolbar pills)

struct IVTopChromeBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            leading()
            Spacer(minLength: IVLayout.stackXL)
            HStack(spacing: IVLayout.toolbarActionSpacing) {
                trailing()
            }
        }
        .padding(.horizontal, IVLayout.windowHPadding)
        .padding(.vertical, IVLayout.toolbarVPadding)
        .frame(minHeight: IVLayout.toolbarHeight)
        .background(IVColor.forestElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(IVColor.forestHover.opacity(IVLayout.chromeDividerOpacity))
                .frame(height: 1)
        }
    }
}

// MARK: - Empty workspace (inactive editorial environment)

struct IVEmptyWorkspaceState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: proxy.size.width * IVLayout.emptyStateLeadingFraction)
                VStack(alignment: .leading, spacing: IVLayout.stackS) {
                    IVLogoView(size: IVLayout.emptyStateLogoSize)
                    Text(title)
                        .font(.ivUIHeader)
                        .foregroundStyle(IVColor.chromePrimary)
                    Text(message)
                        .font(.ivUICaption)
                        .foregroundStyle(IVColor.chromeSecondary)
                        .lineSpacing(3)
                        .frame(maxWidth: IVLayout.emptyStateBlockMaxWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.ivQuietAction)
                            .padding(.top, IVLayout.stackXS)
                    }
                }
                .padding(IVLayout.stackL)
                .background(
                    RoundedRectangle(cornerRadius: IVLayout.panelCornerRadius, style: .continuous)
                        .fill(IVColor.forestElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: IVLayout.panelCornerRadius, style: .continuous)
                        .stroke(IVColor.forestHover.opacity(IVLayout.borderOpacity), lineWidth: IVLayout.borderWidth)
                )
                Spacer(minLength: IVLayout.stackXL)
            }
            .frame(width: proxy.size.width, alignment: .topLeading)
            .padding(.top, proxy.size.height * IVLayout.emptyStateTopFraction)
        }
    }
}

// MARK: - Sidebar section header

struct IVSidebarHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: IVLayout.stackXS) {
            Text(title)
                .font(.ivUIHeader)
                .foregroundStyle(IVColor.chromePrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.ivUICaption)
                    .foregroundStyle(IVColor.chromeTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status bar

struct IVStatusSeparator: View {
    var body: some View {
        Rectangle()
            .fill(IVColor.forestHover.opacity(IVLayout.statusBarSeparatorOpacity))
            .frame(width: 1, height: 10)
    }
}

struct IVStatusItem: View {
    let text: String
    var emphasis: Bool = false
    var warning: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: emphasis ? .medium : .regular))
            .foregroundStyle(foreground)
            .lineLimit(1)
    }

    private var foreground: Color {
        if warning { return IVColor.diagnosticWarning }
        if emphasis { return IVColor.chromePrimary }
        return IVColor.chromeSecondary
    }
}

struct IVStatusBarChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, IVLayout.windowHPadding)
            .frame(height: IVLayout.statusBarHeight)
            .background(IVColor.forestElevated)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(IVColor.forestHover.opacity(IVLayout.chromeDividerOpacity))
                    .frame(height: 1)
            }
    }
}

// MARK: - Window chrome helpers

struct IVWindowToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarBackground(IVColor.forestBlack, for: .windowToolbar)
            .toolbarColorScheme(.dark, for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
    }
}

extension View {
    func ivWindowToolbar() -> some View {
        modifier(IVWindowToolbarModifier())
    }

    /// Top integrated bar — leaves modest gap before main content.
    func ivIntegratedChrome<Leading: View, Trailing: View>(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        ivWindowToolbar()
            .safeAreaInset(edge: .top, spacing: IVLayout.chromeEdgeGap) {
                IVTopChromeBar(leading: leading, trailing: trailing)
            }
    }

    /// Bottom status strip — modest gap above scrollable content.
    func ivChromeFooter<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        safeAreaInset(edge: .bottom, spacing: IVLayout.chromeEdgeGap, content: content)
    }

    /// Scroll areas under header/footer chrome — small tail padding only.
    func ivChromeScrollContent() -> some View {
        padding(.bottom, IVLayout.chromeScrollBottomPad)
    }
}

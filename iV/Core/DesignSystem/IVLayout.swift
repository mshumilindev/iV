import SwiftUI

/// Spacing and sizing grid — workstation density, native macOS rhythm.
enum IVLayout {
    // MARK: Window / chrome
    static let windowHPadding: CGFloat = 20
    static let windowVPadding: CGFloat = 10
    static let toolbarHeight: CGFloat = 40
    static let toolbarVPadding: CGFloat = 8
    static let toolbarActionSpacing: CGFloat = 18
    static let statusBarHeight: CGFloat = 24
    static let statusBarItemSpacing: CGFloat = 10
    static let statusBarSeparatorOpacity: Double = 0.18

    /// Gap between integrated chrome (header/footer) and main content — modest, not drastic.
    static let chromeEdgeGap: CGFloat = 6
    /// Extra scroll tail so last lines clear bottom status chrome.
    static let chromeScrollBottomPad: CGFloat = 8

    // MARK: Workspace framing
    static let workspaceInsetH: CGFloat = 20
    static let workspaceFieldOpacity: Double = 0.18

    // MARK: Panels
    static let panelCornerRadius: CGFloat = 5
    static let cardCornerRadius: CGFloat = 6
    static let sidebarIdealWidth: CGFloat = 300
    static let sidebarMinWidth: CGFloat = 260
    static let inspectorMinWidth: CGFloat = 280

    // MARK: Stacks
    static let stackXS: CGFloat = 4
    static let stackS: CGFloat = 8
    static let stackM: CGFloat = 12
    static let stackL: CGFloat = 16
    static let stackXL: CGFloat = 20

    // MARK: Controls
    static let buttonCornerRadius: CGFloat = 3
    static let buttonHPadding: CGFloat = 9
    static let buttonVPadding: CGFloat = 3
    static let controlHeight: CGFloat = 24

    // MARK: Empty state (optical anchor — not mathematical center)
    static let emptyStateTopFraction: CGFloat = 0.24
    static let emptyStateLeadingFraction: CGFloat = 0.14
    static let emptyStateBlockMaxWidth: CGFloat = 360
    static let emptyStateLogoSize: CGFloat = 44
    static let emptyStatePanelOpacity: Double = 1.0

    // MARK: Interaction
    static let disabledOpacity: Double = 0.42

    // MARK: Borders
    static let borderOpacity: Double = 0.35
    static let borderWidth: CGFloat = 1
    static let chromeDividerOpacity: Double = 0.22
}

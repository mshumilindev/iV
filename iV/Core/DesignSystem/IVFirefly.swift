import SwiftUI

// MARK: - Warm micro-accent (hover/focus edge — separate from ivy brand green)

enum IVFirefly {
  static let duration: Double = 0.15
  static let animation = Animation.easeOut(duration: duration)
  static let breatheDuration: Double = 2.6

  static let borderWidth: CGFloat = 1
  static let borderWidthPressed: CGFloat = 1
  static let shadowRadius: CGFloat = 2.5

  // MARK: Buttons — crisp warm edge, forest fill (no ember clusters)

  static func buttonFill(prominent: Bool, ghost: Bool, quiet: Bool, hovered: Bool, pressed: Bool) -> Color {
    if ghost || quiet {
      return hovered ? IVColor.forestHover.opacity(0.18) : .clear
    }
    if prominent {
      return IVColor.forestHover.opacity(pressed ? 0.48 : (hovered ? 0.36 : 0.26))
    }
    return hovered || pressed
      ? IVColor.forestHover.opacity(0.24)
      : IVColor.forestHover.opacity(0.14)
  }

  static func buttonBorderWidth(hovered: Bool, pressed: Bool, enabled: Bool) -> CGFloat {
    guard enabled, hovered || pressed else { return 0.5 }
    return borderWidth
  }

  static func buttonBorderColor(hovered: Bool, pressed: Bool, enabled: Bool) -> Color {
    guard enabled else { return IVColor.forestHover.opacity(0.25) }
    if hovered || pressed {
      return IVColor.fireflyWarm.opacity(pressed ? 0.95 : 0.88)
    }
    return IVColor.forestHover.opacity(0.45)
  }

  static func buttonShadowColor(hovered: Bool, pressed: Bool, enabled: Bool) -> Color {
    guard enabled, hovered || pressed else { return .clear }
    return IVColor.fireflySoftShadow
  }

  // MARK: Rows / cards — warm outline on hover/selection only

  static func rowFill(selected: Bool, hovered: Bool) -> Color {
    if selected { return IVColor.ivyPrimary.opacity(0.1) }
    if hovered { return IVColor.forestHover.opacity(0.22) }
    return .clear
  }

  static func rowBorderColor(hovered: Bool, selected: Bool) -> Color {
    if selected { return IVColor.fireflyWarm.opacity(0.75) }
    if hovered { return IVColor.fireflyWarm.opacity(0.55) }
    return .clear
  }

  static func rowBorderWidth(hovered: Bool, selected: Bool) -> CGFloat {
    hovered || selected ? borderWidth : 0
  }

  static func cardBorderColor(hovered: Bool) -> Color {
    hovered
      ? IVColor.fireflyWarm.opacity(0.6)
      : IVColor.forestHover.opacity(IVLayout.borderOpacity)
  }

  static func cardShadowColor(hovered: Bool) -> Color {
    hovered ? IVColor.fireflySoftShadow : .clear
  }
}

// MARK: - Hover-aware button label

struct IVFireflyButtonLabel<Content: View>: View {
  let pressed: Bool
  var prominent: Bool = false
  var ghost: Bool = false
  var quiet: Bool = false
  var paddingH: CGFloat = IVLayout.buttonHPadding
  var paddingV: CGFloat = IVLayout.buttonVPadding
  @ViewBuilder var content: () -> Content

  @State private var hovered = false
  @Environment(\.isEnabled) private var isEnabled

  private var fireflyActive: Bool {
    isEnabled && (hovered || pressed)
  }

  var body: some View {
    content()
      .padding(.horizontal, ghost || quiet ? 4 : paddingH)
      .padding(.vertical, ghost || quiet ? 3 : paddingV)
      .background(background)
      .overlay(edgeOverlay)
      .shadow(
        color: IVFirefly.buttonShadowColor(hovered: hovered, pressed: pressed, enabled: isEnabled),
        radius: fireflyActive ? IVFirefly.shadowRadius : 0,
        y: 0
      )
      .opacity(pressed ? 0.92 : (isEnabled ? 1 : IVLayout.disabledOpacity))
      .onHover { hovered = $0 }
      .animation(IVFirefly.animation, value: hovered)
      .animation(IVFirefly.animation, value: pressed)
  }

  @ViewBuilder
  private var background: some View {
    RoundedRectangle(cornerRadius: IVLayout.buttonCornerRadius, style: .continuous)
      .fill(
        IVFirefly.buttonFill(
          prominent: prominent,
          ghost: ghost,
          quiet: quiet,
          hovered: hovered && isEnabled,
          pressed: pressed && isEnabled
        )
      )
  }

  @ViewBuilder
  private var edgeOverlay: some View {
    RoundedRectangle(cornerRadius: IVLayout.buttonCornerRadius, style: .continuous)
      .stroke(
        IVFirefly.buttonBorderColor(hovered: hovered, pressed: pressed, enabled: isEnabled),
        lineWidth: IVFirefly.buttonBorderWidth(hovered: hovered, pressed: pressed, enabled: isEnabled)
      )
  }
}

// MARK: - Modifiers

private struct IVFireflyRowModifier: ViewModifier {
  @State private var hovered = false
  var selected: Bool

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: IVLayout.buttonCornerRadius, style: .continuous)
          .fill(IVFirefly.rowFill(selected: selected, hovered: hovered))
      )
      .overlay(
        RoundedRectangle(cornerRadius: IVLayout.buttonCornerRadius, style: .continuous)
          .stroke(
            IVFirefly.rowBorderColor(hovered: hovered, selected: selected),
            lineWidth: IVFirefly.rowBorderWidth(hovered: hovered, selected: selected)
          )
      )
      .onHover { hovered = $0 }
      .animation(IVFirefly.animation, value: hovered)
      .animation(IVFirefly.animation, value: selected)
  }
}

private struct IVFireflyCardModifier: ViewModifier {
  @State private var hovered = false

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: IVLayout.cardCornerRadius, style: .continuous)
          .fill(IVColor.forestElevated)
      )
      .overlay(
        RoundedRectangle(cornerRadius: IVLayout.cardCornerRadius, style: .continuous)
          .stroke(
            IVFirefly.cardBorderColor(hovered: hovered),
            lineWidth: hovered ? IVFirefly.borderWidth : IVLayout.borderWidth
          )
      )
      .shadow(
        color: IVFirefly.cardShadowColor(hovered: hovered),
        radius: hovered ? IVFirefly.shadowRadius : 0,
        y: 0
      )
      .onHover { hovered = $0 }
      .animation(IVFirefly.animation, value: hovered)
  }
}

/// Warm breathing dots — pipeline / LLM / indexing activity only (not ordinary hover).
private struct IVFireflyBreathingModifier: ViewModifier {
  let active: Bool
  @State private var breathe = false

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .leading) {
        if active {
          HStack(spacing: 3) {
            breathingDot(scale: 1.0)
            breathingDot(scale: 0.7).opacity(0.55)
          }
          .offset(x: -8)
          .allowsHitTesting(false)
        }
      }
      .onAppear {
        guard active else { return }
        withAnimation(.easeInOut(duration: IVFirefly.breatheDuration).repeatForever(autoreverses: true)) {
          breathe = true
        }
      }
      .onChange(of: active) { _, on in
        if !on { breathe = false }
      }
  }

  private func breathingDot(scale: CGFloat) -> some View {
    Circle()
      .fill(IVColor.fireflyWarm.opacity(breathe ? 0.85 : 0.35))
      .frame(width: 4 * scale, height: 4 * scale)
  }
}

/// Subtle 1px warm edge on editor chrome bar only — does not tint the manuscript surface.
struct IVEditorChromeFocusEdge: View {
  var active: Bool

  var body: some View {
    if active {
      Rectangle()
        .fill(IVColor.fireflyAmber.opacity(0.45))
        .frame(height: 1)
    }
  }
}

extension View {
  func ivFireflyRow(selected: Bool = false) -> some View {
    modifier(IVFireflyRowModifier(selected: selected))
  }

  func ivFireflyCard() -> some View {
    modifier(IVFireflyCardModifier())
  }

  func ivFireflyBreathing(active: Bool) -> some View {
    modifier(IVFireflyBreathingModifier(active: active))
  }
}

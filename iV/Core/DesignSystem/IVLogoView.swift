import SwiftUI

/// Brand mark — leaves with vines (bundled `iVLogo` asset, muted ivy tint).
struct IVLogoView: View {
    var size: CGFloat = 28

    var body: some View {
        Image("iVLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(IVColor.ivySoft)
            .accessibilityHidden(true)
    }
}

/// Toolbar lockup — integrated into chrome bar, not a floating badge.
struct IVBrandHeader: View {
    var logoSize: CGFloat = 22
    var showWordmark: Bool = true

    var body: some View {
        HStack(spacing: 9) {
            IVLogoView(size: logoSize)
            if showWordmark {
                Text("iV")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(IVColor.chromePrimary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("iV")
    }
}

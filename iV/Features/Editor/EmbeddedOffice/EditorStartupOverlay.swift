import SwiftUI

/// Full-window startup progress while the embedded manuscript editor prepares.
struct EditorStartupOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            IVColor.forestBlack.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: IVLayout.stackM) {
                ProgressView()
                    .controlSize(.large)
                    .tint(IVColor.ivyUI)

                Text(message)
                    .font(.ivUIHeader)
                    .foregroundStyle(IVColor.chromePrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                Text("Your projects stay on this Mac. This only prepares the editor.")
                    .font(.ivUICaption)
                    .foregroundStyle(IVColor.chromeTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(IVLayout.stackXL)
        }
        .accessibilityIdentifier("app.editorStartup.overlay")
    }
}

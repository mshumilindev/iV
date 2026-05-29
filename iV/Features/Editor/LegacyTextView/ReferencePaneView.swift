import SwiftUI

/// Read-only reference pane for split writing (import snapshot or secondary text).
struct ReferencePaneView: View {
    let title: String
    let text: String
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IVColor.documentMuted)
                Spacer()
                Text("\(TextUtilities.wordCount(text)) words")
                    .font(.caption2)
                    .foregroundStyle(IVColor.documentMuted)
                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Close")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(IVColor.documentMuted)
                .help("Close reference pane")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(IVColor.documentSecondary)
            ScrollView {
                Text(text)
                    .font(Font(IVTheme.manuscriptFont))
                    .foregroundStyle(IVColor.documentText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(IVColor.documentSurface)
    }
}

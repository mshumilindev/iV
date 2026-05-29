import SwiftUI

struct CanonSuggestionsView: View {
    @Environment(AppState.self) private var appState

    var pending: [CanonUpdateSuggestion] {
        appState.canonSuggestions.filter { $0.status == .pending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pending canon updates").font(.headline)
            if pending.isEmpty {
                Text("No pending suggestions. LLM pipeline passes may propose canon facts for your approval.")
                    .ivMutedCaption()
            } else {
                ForEach(pending) { suggestion in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(suggestion.name).font(.subheadline.weight(.semibold))
                            Text(suggestion.entityType.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(IVColor.forestHover.opacity(0.5))
                                .foregroundStyle(IVColor.chromeSecondary)
                                .clipShape(Capsule())
                        }
                        Text(suggestion.fact).font(.caption)
                        Text(suggestion.reason).font(.caption2).foregroundStyle(IVColor.chromeTertiary)
                        HStack {
                            Button("Accept") { appState.acceptCanonSuggestion(suggestion) }
                                .buttonStyle(.ivPrimary)
                            Button("Reject") { appState.rejectCanonSuggestion(suggestion) }
                                .buttonStyle(.ivGhost)
                        }
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(IVColor.forestHover.opacity(0.7), lineWidth: 1)
                    )
                }
            }
        }
    }
}

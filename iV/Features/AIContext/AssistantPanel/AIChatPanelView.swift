import SwiftUI

struct AIChatPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var draft = ""
    @State private var instructionMode: AiChatInstructionMode = .rewrite

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            contextIndicator
            messageList
            Divider().overlay(IVColor.forestHover.opacity(IVLayout.chromeDividerOpacity))
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IVColor.forestElevated)
        .accessibilityIdentifier("workspace.aiChat")
    }

    @ViewBuilder
    private var contextIndicator: some View {
        VStack(alignment: .leading, spacing: 4) {
            if appState.documentEditorBridge.selection.hasSelection {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                    Text("Using selected text")
                        .font(.ivUICaption)
                }
                .foregroundStyle(IVColor.ivyUI)
                Text(appState.documentEditorBridge.selection.selectionPreview)
                    .font(.caption2)
                    .foregroundStyle(IVColor.chromeTertiary)
                    .lineLimit(2)
                Button("Clear selection context") {
                    appState.clearEditorSelectionContext()
                }
                .buttonStyle(.ivGhost)
                .font(.caption2)
            } else if appState.activeDocument != nil {
                Text("No selection — using cursor / document context")
                    .font(.ivUICaption)
                    .foregroundStyle(IVColor.chromeSecondary)
            } else {
                Text("Open a manuscript to use the assistant")
                    .font(.ivUICaption)
                    .foregroundStyle(IVColor.chromeTertiary)
            }
            if case .unavailable(let reason) = appState.documentEditorBridge.connectionState,
               appState.documentEditorBridge.editorKind == .embeddedOffice {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(IVColor.diagnosticWarning)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, IVLayout.stackS)
        .padding(.vertical, IVLayout.stackS)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: IVLayout.stackS) {
                    ForEach(appState.aiChatMessages) { message in
                        chatBubble(message)
                            .id(message.id)
                    }
                    if appState.aiChatIsLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…")
                                .font(.ivUICaption)
                                .foregroundStyle(IVColor.chromeSecondary)
                        }
                        .padding(.horizontal, IVLayout.stackS)
                    }
                }
                .padding(IVLayout.stackS)
            }
            .onChange(of: appState.aiChatMessages.count) { _, _ in
                if let last = appState.aiChatMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func chatBubble(_ message: AiChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.role == .user ? "You" : "Assistant")
                .font(.caption2)
                .foregroundStyle(IVColor.chromeTertiary)
            Text(message.text)
                .font(.ivUICaption)
                .foregroundStyle(IVColor.chromePrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if message.role == .assistant, !message.proposedActions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.proposedActions) { action in
                        Button(action.title) {
                            appState.applyAIChatAction(action, assistantText: message.text)
                        }
                        .buttonStyle(.ivSecondary)
                        .font(.caption2)
                        .disabled(appState.aiChatIsLoading)
                    }
                }
            }
        }
        .padding(IVLayout.stackS)
        .background(
            RoundedRectangle(cornerRadius: IVLayout.panelCornerRadius, style: .continuous)
                .fill(message.role == .user ? IVColor.forestHover.opacity(0.35) : IVColor.forestBlack.opacity(0.5))
        )
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: IVLayout.stackS) {
            Picker("Mode", selection: $instructionMode) {
                ForEach(AiChatInstructionMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)

            TextField("Ask about the manuscript…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
                .onSubmit { send() }

            HStack {
                if appState.isOllamaUnavailable {
                    Text("Ollama unavailable")
                        .font(.caption2)
                        .foregroundStyle(IVColor.diagnosticWarning)
                }
                Spacer()
                Button("Send") { send() }
                    .buttonStyle(.ivPrimary)
                    .disabled(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || appState.aiChatIsLoading
                            || appState.activeDocument == nil
                    )
            }
        }
        .padding(IVLayout.stackS)
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await appState.sendAIChat(userMessage: text, mode: instructionMode) }
    }
}

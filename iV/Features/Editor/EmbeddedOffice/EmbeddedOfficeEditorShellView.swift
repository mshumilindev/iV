import SwiftUI

/// Production shell for embedded office editing — honest loading/unavailable/bridge-pending states.
struct EmbeddedOfficeEditorShellView: View {
    @Environment(AppState.self) private var appState
    let coordinator: EmbeddedOfficeEditorCoordinator
    var onOpenSettings: () -> Void
    var onSwitchToLegacy: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EditorManuscriptStatusStrip(coordinator: coordinator)
                .ivForestElevatedBar()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(IVColor.forestBlack)
        .accessibilityIdentifier("workspace.manuscript.office.shell")
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.lifecycle {
        case .idle, .noDocument:
            emptyDocumentState
        case .checkingServer, .preparingDocument, .loadingDocument, .startingDocumentServer:
            loadingState
        case .serverUnavailable(let reason, let detail):
            unavailableState(
                title: "Document Server unavailable",
                message: reason,
                detail: detail,
                reassurance: manuscriptSafeCopy
            )
        case .failed(let message, let detail):
            unavailableState(
                title: "Manuscript unavailable",
                message: message,
                detail: detail,
                reassurance: manuscriptSafeCopy
            )
        case .bridgePending(let title, let path):
            bridgePendingState(documentTitle: title, docxPath: path)
        case .ready(let title, let path):
            if coordinator.isEditingBridgeConnected {
                readyState(documentTitle: title, docxPath: path)
            } else {
                bridgePendingState(documentTitle: title, docxPath: path)
            }
        }
    }

    private var manuscriptSafeCopy: String {
        "Your manuscript files remain on this Mac. iV does not delete or overwrite imported originals when the editor is unavailable."
    }

    private var emptyDocumentState: some View {
        IVEmptyWorkspaceState(
            title: "No manuscript open",
            message: "Choose a document in the sidebar, or create or import one from Overview.",
            actionTitle: "Overview",
            action: {
                if let id = appState.currentProject?.id {
                    appState.navigation = .projectOverview(id)
                }
            }
        )
        .background(IVColor.documentSurface)
    }

    private var loadingState: some View {
        EmbeddedOfficeStatePanel(
            title: coordinator.lifecycle.userFacingTitle,
            message: loadingMessage,
            showsProgress: true
        ) {
            EmptyView()
        }
    }

    private var loadingMessage: String {
        switch coordinator.lifecycle {
        case .preparingDocument:
            "Ensuring the local DOCX manuscript file exists…"
        case .loadingDocument:
            "Opening “\(coordinator.documentTitle)”…"
        case .checkingServer:
            "Contacting Document Server at \(DocumentServerConfiguration.normalizedURL(coordinator.serverURL))…"
        default:
            "Please wait…"
        }
    }

    private func unavailableState(
        title: String,
        message: String,
        detail: String?,
        reassurance: String
    ) -> some View {
        EmbeddedOfficeStatePanel(
            title: title,
            message: message,
            secondaryMessage: reassurance,
            technicalDetail: detail,
            showTechnicalDetail: coordinator.showTechnicalDetail,
            onToggleTechnicalDetail: { coordinator.showTechnicalDetail.toggle() }
        ) {
            unavailableActions
        }
    }

    private var unavailableActions: some View {
        VStack(alignment: .leading, spacing: IVLayout.stackS) {
            HStack(spacing: IVLayout.stackS) {
                Button("Start local Document Server") {
                    appState.startLocalDocumentServer()
                }
                .buttonStyle(.ivPrimary)
                .disabled(appState.editorStartup.isLoading)
                .accessibilityIdentifier("workspace.office.startServer")

                Button("Retry connection") {
                    appState.retryEmbeddedOfficeEditor()
                }
                .buttonStyle(.ivSecondary)
                .accessibilityIdentifier("workspace.office.retry")

                Button("Editor settings…") {
                    onOpenSettings()
                }
                .buttonStyle(.ivSecondary)

                Button("Use legacy fallback") {
                    onSwitchToLegacy()
                }
                .buttonStyle(.ivGhost)
                .accessibilityIdentifier("workspace.office.legacyFallback")
            }

            if DockerDesktopLauncher.isInstalled {
                Button("Open Docker Desktop") {
                    DockerDesktopLauncher.openIfInstalled()
                }
                .buttonStyle(.ivSecondary)
                .accessibilityIdentifier("workspace.office.openDockerDesktop")
            }
        }
    }

    @ViewBuilder
    private func bridgePendingState(documentTitle: String, docxPath: String?) -> some View {
        let defaultMessage = """
        ONLYOFFICE responded, but the editing session is not ready yet. \
        “\(documentTitle)” is prepared locally; inline DOCX editing appears when the local document server and DocsAPI bridge are connected.
        """
        let technicalLines = [
            docxPath.map { "Manuscript file:\n\($0)" },
            coordinator.bridgePendingTechnicalDetail,
            coordinator.activeSession.map { "Local serving:\n\($0.localServingDetail)" },
        ].compactMap { $0 }.joined(separator: "\n\n")

        EmbeddedOfficeStatePanel(
            title: "Document Server reachable",
            message: coordinator.bridgePendingMessage ?? defaultMessage,
            secondaryMessage: manuscriptSafeCopy,
            technicalDetail: technicalLines.isEmpty ? docxPath.map { "Manuscript file:\n\($0)" } : technicalLines,
            showTechnicalDetail: coordinator.showTechnicalDetail,
            onToggleTechnicalDetail: { coordinator.showTechnicalDetail.toggle() }
        ) {
            HStack(spacing: IVLayout.stackS) {
                Button("Retry connection") {
                    appState.retryEmbeddedOfficeEditor()
                }
                .buttonStyle(.ivSecondary)
                Button("Editor settings…") {
                    onOpenSettings()
                }
                .buttonStyle(.ivGhost)
                Button("Use legacy fallback") {
                    onSwitchToLegacy()
                }
                .buttonStyle(.ivGhost)
            }
        }
    }

    @ViewBuilder
    private func readyState(documentTitle: String, docxPath: String?) -> some View {
        ONLYOFFICEEditorHost(
            session: coordinator.activeSession,
            onConnectionChange: { state in
                coordinator.updateHostConnectionState(state)
                appState.documentEditorBridge.connectionState = coordinator.connectionState
            }
        )
        .accessibilityIdentifier("workspace.manuscript.active")
        .background(IVColor.documentSurface)
    }
}

// MARK: - State panel

private struct EmbeddedOfficeStatePanel<Actions: View>: View {
    let title: String
    let message: String
    var secondaryMessage: String?
    var technicalDetail: String?
    var showTechnicalDetail = false
    var onToggleTechnicalDetail: (() -> Void)?
    var showsProgress = false
    private let actions: () -> Actions

    init(
        title: String,
        message: String,
        secondaryMessage: String? = nil,
        technicalDetail: String? = nil,
        showTechnicalDetail: Bool = false,
        onToggleTechnicalDetail: (() -> Void)? = nil,
        showsProgress: Bool = false,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.message = message
        self.secondaryMessage = secondaryMessage
        self.technicalDetail = technicalDetail
        self.showTechnicalDetail = showTechnicalDetail
        self.onToggleTechnicalDetail = onToggleTechnicalDetail
        self.showsProgress = showsProgress
        self.actions = actions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IVLayout.stackM) {
                if showsProgress {
                    HStack(spacing: IVLayout.stackS) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(IVColor.ivyUI)
                        Text(title)
                            .font(.ivUIHeader)
                            .foregroundStyle(IVColor.chromePrimary)
                    }
                } else {
                    Text(title)
                        .font(.ivUIHeader)
                        .foregroundStyle(IVColor.chromePrimary)
                }

                Text(message)
                    .font(.ivUIBody)
                    .foregroundStyle(IVColor.chromeSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let secondaryMessage {
                    Text(secondaryMessage)
                        .font(.ivUICaption)
                        .foregroundStyle(IVColor.chromeTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let technicalDetail, onToggleTechnicalDetail != nil {
                    Button(showTechnicalDetail ? "Hide technical details" : "Show technical details") {
                        onToggleTechnicalDetail?()
                    }
                    .buttonStyle(.ivQuietAction)
                    if showTechnicalDetail {
                        Text(technicalDetail)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(IVColor.chromeTertiary)
                            .textSelection(.enabled)
                            .padding(IVLayout.stackS)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(IVColor.forestElevated)
                            .clipShape(RoundedRectangle(cornerRadius: IVLayout.panelCornerRadius, style: .continuous))
                    }
                }

                actions()
            }
            .padding(IVLayout.stackL)
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.top, IVLayout.stackXL)
            .padding(.horizontal, IVLayout.workspaceInsetH)
            .ivChromeScrollContent()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IVColor.documentSurface)
    }
}

// MARK: - Manuscript status strip

struct EditorManuscriptStatusStrip: View {
    @Environment(AppState.self) private var appState
    let coordinator: EmbeddedOfficeEditorCoordinator

    private var integrationStatus: DocumentEditorIntegrationStatus {
        appState.documentEditorIntegrationStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: IVLayout.statusBarItemSpacing) {
                if let doc = appState.activeDocument {
                    IVStatusItem(text: doc.title, emphasis: true)
                    IVStatusSeparator()
                }
                saveStateItem
                IVStatusSeparator()
                IVStatusItem(text: appState.documentEditorBridge.editorKind.statusLabel)
                IVStatusSeparator()
                serverStateItem
                if appState.openDiagnosticCount > 0 {
                    IVStatusSeparator()
                    IVStatusItem(text: "\(appState.openDiagnosticCount) issues", warning: true)
                }
                if appState.isPipelineRunning {
                    IVStatusSeparator()
                    ProgressView()
                        .controlSize(.small)
                        .tint(IVColor.ivyUI)
                }
                Spacer(minLength: IVLayout.stackM)
                if let path = coordinator.docxFileURL?.lastPathComponent {
                    Text(path)
                        .font(.ivUICaption)
                        .foregroundStyle(IVColor.chromeTertiary)
                        .lineLimit(1)
                }
            }
            IVStatusItem(
                text: integrationStatus.statusLine,
                warning: integrationStatus.isWarning
            )
            .accessibilityIdentifier("workspace.editor.integrationStatus")
        }
        .padding(.horizontal, IVLayout.windowHPadding)
        .padding(.vertical, 6)
        .accessibilityIdentifier("workspace.editor.statusStrip")
    }

    @ViewBuilder
    private var saveStateItem: some View {
        switch appState.documentSaveState {
        case .saved:
            IVStatusItem(text: "Saved")
        case .unsaved:
            IVStatusItem(text: "Unsaved", warning: true)
        case .saving:
            IVStatusItem(text: "Saving…")
        case .saveError:
            IVStatusItem(text: "Save error", warning: true)
        }
    }

    @ViewBuilder
    private var serverStateItem: some View {
        switch coordinator.lifecycle {
        case .checkingServer, .preparingDocument, .loadingDocument:
            IVStatusItem(text: "Document Server…")
        case .bridgePending:
            IVStatusItem(text: "Bridge pending", warning: true)
        case .ready where coordinator.isEditorHostReady:
            IVStatusItem(text: "Document Server up", emphasis: true)
        case .ready where coordinator.isEditingBridgeConnected:
            IVStatusItem(text: "Loading editor…")
        case .serverUnavailable, .failed:
            IVStatusItem(text: "Document Server off", warning: true)
        default:
            IVStatusItem(text: "Document Server")
        }
    }
}

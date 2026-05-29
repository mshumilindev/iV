import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var modelName = ""
    @State private var utilityModelName = ""
    @State private var endpoint = ""
    @State private var llmEnabled = true
    @State private var embeddingsEnabled = false
    @State private var embeddingModelName = ""
    @State private var allowUtility = false
    @State private var maxConcurrentLLM = 1
    @State private var maxLoadedModels = 1
    @State private var keepAlivePolicy: KeepAlivePolicy = .balanced
    @State private var availableModels: [String] = []
    @State private var primaryRoles: Set<ModelRole> = [.generalReasoning, .proseAnalysis]
    @State private var confirmDisableLLM = false
    @State private var previousLLMEnabled = true
    @State private var documentServerURL = DocumentEditorSettings.defaultServerURL
    @State private var documentEditorKind: DocumentEditorKind = .embeddedOffice
    @State private var dockerCLIPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IVSheetHeaderBar(title: "Settings", onDismiss: { dismiss() })
                .padding(.horizontal, IVLayout.windowHPadding)
                .padding(.top, IVLayout.stackS)
            Form {
            Section("Document editor") {
                Picker("Engine", selection: $documentEditorKind) {
                    ForEach(DocumentEditorKind.allCases, id: \.self) { kind in
                        Text(kind.settingsLabel).tag(kind)
                    }
                }
                TextField("Document Server URL (localhost)", text: $documentServerURL)
                TextField("Docker CLI path (optional)", text: $dockerCLIPath, prompt: Text("/opt/homebrew/bin/docker"))
                Text("Embedded office is the default manuscript editor. Set Docker CLI path if iV cannot find Homebrew docker automatically.")
                    .font(.caption)
                    .ivMutedCaption()
                if documentEditorKind == .legacyPrototype {
                    Text("Legacy prototype is active. Switch back to embedded office when Document Server is configured.")
                        .font(.caption)
                        .foregroundStyle(IVColor.diagnosticWarning)
                }
                Button("Save document editor settings") {
                    appState.saveDocumentEditorSettings(
                        serverURL: documentServerURL,
                        kind: documentEditorKind,
                        dockerCLIPath: dockerCLIPath
                    )
                }
                .buttonStyle(.ivSecondary)
            }

            Section("Performance") {
                Picker("Mode", selection: Bindable(appState).performanceMode) {
                    ForEach(PerformanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .onChange(of: appState.performanceMode) { _, mode in
                    appState.savePerformanceMode(mode)
                }
                LabeledContent("Power", value: powerLabel)
                Toggle("Active Watch", isOn: Bindable(appState).activeWatchEnabled)
            }

            Section("Model routing") {
                Text(appState.localAIStatusLine).ivMutedCaption()
                Text(appState.ollamaStatusText).font(.caption)
                Stepper("Max concurrent LLM tasks: \(maxConcurrentLLM)", value: $maxConcurrentLLM, in: 1...3)
                Stepper("Max loaded LLM models: \(maxLoadedModels)", value: $maxLoadedModels, in: 1...2)
                Picker("Keep-alive policy", selection: $keepAlivePolicy) {
                    ForEach(KeepAlivePolicy.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
            }

            Section("Ollama") {
                TextField("Endpoint", text: $endpoint)
                TextField("Primary model", text: $modelName)
                Toggle("Enable LLM passes", isOn: $llmEnabled)
                    .onChange(of: llmEnabled) { old, new in
                        if old && !new { confirmDisableLLM = true }
                    }
                Toggle("Allow utility model", isOn: $allowUtility)
                TextField("Utility model (optional)", text: $utilityModelName)
                    .disabled(!allowUtility)
                Toggle("Enable embedding index", isOn: $embeddingsEnabled)
                TextField("Embedding model", text: $embeddingModelName)
                Text("Index: \(appState.semanticIndexModeLabel)")
                    .font(.caption)
                    .ivMutedCaption()
                if !availableModels.isEmpty {
                    Picker("Installed models", selection: $modelName) {
                        ForEach(availableModels, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                }
                HStack {
                    Button("Check connection") {
                        Task {
                            await appState.refreshOllamaStatus()
                            await loadModels()
                        }
                    }
                    .buttonStyle(.ivSecondary)
                    Button("Save") { saveOllamaSettings() }
                        .buttonStyle(.ivPrimary)
                }
            }

            Section("Primary model roles") {
                Text("Suggestions for routing — assign what this model is good at.")
                    .font(.caption)
                    .ivMutedCaption()
                ForEach(ModelRole.allCases, id: \.self) { role in
                    Toggle(role.rawValue, isOn: Binding(
                        get: { primaryRoles.contains(role) },
                        set: { on in
                            if on { primaryRoles.insert(role) } else { primaryRoles.remove(role) }
                        }
                    ))
                }
            }

            Section("Local AI backends") {
                ForEach(LocalAIBackend.allCases, id: \.self) { backend in
                    HStack {
                        Text(backend.rawValue)
                        Spacer()
                        Text(backend == .ollama ? "Active" : "Unavailable")
                            .font(.caption)
                            .foregroundStyle(backend == .ollama ? IVColor.ivyUI : IVColor.chromeSecondary)
                    }
                }
            }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.ivGhost)
            }
            .padding(.horizontal, IVLayout.windowHPadding)
            .padding(.bottom, IVLayout.stackM)
        }
        .frame(width: 520, height: 560)
        .ivChromeScrollContent()
        .onAppear { loadFromProject() }
        .confirmationDialog("Disable LLM analysis?", isPresented: $confirmDisableLLM, titleVisibility: .visible) {
            Button("Disable LLM", role: .destructive) { llmEnabled = false }
            Button("Keep enabled", role: .cancel) { llmEnabled = true }
        } message: {
            Text("Deterministic checks still run. Background LLM watch and pipeline LLM passes will stop until re-enabled.")
        }
    }

    private func loadFromProject() {
        documentServerURL = DocumentEditorSettings.loadServerURL()
        documentEditorKind = DocumentEditorSettings.loadEditorKind()
        dockerCLIPath = DocumentEditorSettings.loadDockerCLIPath() ?? ""
        let settings = appState.currentProject?.ollamaSettings ?? .default
        let ms = settings.resolvedModelSettings
        endpoint = settings.endpoint
        modelName = settings.effectivePrimaryModel
        llmEnabled = settings.llmPassesEnabled
        embeddingsEnabled = settings.embeddingsEnabled
        embeddingModelName = settings.embeddingModelName
        utilityModelName = ms.utilityModelName ?? ""
        allowUtility = ms.allowUtilityModel
        maxConcurrentLLM = ms.maxConcurrentLLMTasks
        maxLoadedModels = ms.maxLoadedLLMModels
        keepAlivePolicy = ms.keepAlivePolicy
        primaryRoles = Set(ms.primaryModelRoles)
        previousLLMEnabled = llmEnabled
        Task { await loadModels() }
    }

    private func loadModels() async {
        if case .available(let models) = appState.ollamaHealth {
            availableModels = models
            if modelName.isEmpty { modelName = models.first ?? "" }
        }
    }

    private func saveOllamaSettings() {
        var ms = appState.currentProject?.ollamaSettings.resolvedModelSettings ?? .default
        ms.primaryModelName = modelName
        ms.utilityModelName = utilityModelName.isEmpty ? nil : utilityModelName
        ms.allowUtilityModel = allowUtility
        ms.allowEmbeddings = embeddingsEnabled
        ms.embeddingModelName = embeddingModelName
        ms.maxConcurrentLLMTasks = maxConcurrentLLM
        ms.maxLoadedLLMModels = maxLoadedModels
        ms.keepAlivePolicy = keepAlivePolicy
        ms.primaryModelRoles = Array(primaryRoles)
        if !modelName.isEmpty {
            ms.roleAssignments[modelName] = Array(primaryRoles)
        }
        appState.updateOllamaSettings(
            endpoint: endpoint,
            modelName: modelName,
            llmPassesEnabled: llmEnabled,
            embeddingsEnabled: embeddingsEnabled,
            embeddingModelName: embeddingModelName,
            modelSettings: ms,
            hadLLMEnabled: previousLLMEnabled
        )
        previousLLMEnabled = llmEnabled
    }

    private var powerLabel: String {
        switch PerformancePolicyService.currentPowerState() {
        case .onBattery: "Battery"
        case .pluggedIn: "Plugged in"
        case .unknown: "Unknown"
        }
    }
}

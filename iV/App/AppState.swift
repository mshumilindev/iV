import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    var navigation: AppNavigation = .library
    var projects: [ProjectRegistryEntry] = []
    var currentProject: Project?
    var currentFolder: URL?
    var documents: [Document] = []
    var activeDocument: Document?
    var documentIndex: DocumentIndex?
    var structure: DocumentStructure = DocumentStructure(chapters: [], scenes: [])
    var diagnostics: [Diagnostic] = []
    var proposals: [ChangeProposal] = []
    var canonEntities: [CanonEntity] = []
    var narrativeMemory: [NarrativeMemory] = []
    var ruleFiles: [EditRuleFile] = []
    var pipelinePassResults: [PipelinePassResult] = []
    var analysisRuns: [AnalysisRun] = []
    var manualReview: ManualReviewStatus = ManualReviewStatus(
        isReady: false, blockingIssues: 0, errors: 0, warnings: 0, styleRisks: 0, canonRisks: 0,
        logicRisks: 0, aiPatternRisks: 0, pendingProposals: 0, readinessNote: nil
    )
    var ollamaHealth: OllamaHealth = .unavailable("Not checked")
    var ollamaStatusText: String = "Ollama: not checked"
    var activeWatchEnabled = false
    var performanceMode: PerformanceMode = .balanced
    var selectedParagraphID: UUID?
    var selectionLocation: Int = 0
    var selectionLength: Int = 0
    var scrollToRange: NSRange?
    var contextPacket: ContextPacket?
    var diffDisplayMode: DiffDisplayMode = .fullDiff
    var selectedProposal: ChangeProposal?
    var statusMessage: String = ""
    var documentSaveState: DocumentSaveState = .saved
    var isPipelineRunning = false
    var dirtyStates: [ParagraphDirtyState] = []
    var chapterSplitSuggestions: [ChapterSplitSuggestion] = []
    var errorMessage: String?
    private(set) var registryLoadFailed = false
    var focusMode = false
    var findController = FindReplaceController()
    var semanticSearchQuery = ""
    var semanticSearchResults: [UUID] = []
    var semanticIndexModeLabel = "lexical"
    var revisionReviewActive = false
    var showSettings = false
    var selectedDiagnostic: Diagnostic?
    var splitEditorReference: SplitEditorReference = .none
    var isSceneExpansionRunning = false
    var showCommandPalette = false
    var canonSuggestions: [CanonUpdateSuggestion] = []
    var analysisQueuePaused = false
    var analysisQueuePauseReason: String?
    var useActiveWatchPanel = false
    var workspaceSidebarTab: WorkspaceSidebarSection?
    var workspaceInspectorTab: WorkspaceInspectorSection?

    var openDiagnosticCount: Int {
        diagnostics.filter { $0.status == .open && !$0.isStale }.count
    }

    var isOllamaUnavailable: Bool {
        if case .available = ollamaHealth { return false }
        return true
    }
    var showManuscriptSnapshots = false
    var showAIChatPanel = false
    var documentEditorBridge = DocumentEditorBridge()
    var embeddedOfficeCoordinator: EmbeddedOfficeEditorCoordinator!
    var aiChatMessages: [AiChatMessage] = []
    var aiChatIsLoading = false
    var editorContentEpoch = 0
    var editorStartup: EditorStartupState = .idle
    private(set) var isTyping = false
    var queueStatus: AnalysisQueueStatus { analysisQueue.status }
    var localAIStatusLine: String { llmCoordinator.statusDetail }

    /// Scene expansion requires Ollama and enabled LLM passes — no offline placeholder proposals.
    var isSceneExpansionAvailable: Bool {
        guard let project = currentProject, project.ollamaSettings.llmPassesEnabled else { return false }
        if case .available = ollamaHealth { return true }
        return false
    }

    let registry = ProjectRegistryService.shared
    let projectStore = ProjectStore()
    let documentStore = DocumentStore()
    private let diagnosticsStore = DiagnosticsStore()
    private let canonStore = CanonStore()
    private let canonSuggestionStore = CanonSuggestionStore()
    private let paragraphIndexer = ParagraphIndexer()
    private let deterministic = DeterministicRuleEngine.default
    private let safeFix = SafeAutoFixEngine()
    private let pipelineEngine = PipelineEngine()
    private let analysisQueue = AnalysisQueue()
    private let analysisCoordinator = AnalysisCoordinator()
    private let llmCoordinator = LocalLLMCoordinator()
    private var semanticIndex: OllamaSemanticIndexService!
    private let documentServerRuntime: DocumentServerRuntimeManaging = LiveDocumentServerRuntimeService()
    private var managedDocumentServerThisSession = false
    private var editorStartupTask: Task<Void, Never>?

    init() {
        semanticIndex = OllamaSemanticIndexService(provider: llmCoordinator.provider)
        embeddedOfficeCoordinator = EmbeddedOfficeEditorCoordinator(
            preparationService: EmbeddedDocumentPreparationService(documentStore: documentStore),
            sessionManager: ONLYOFFICEDocumentSessionManager()
        )
        configureONLYOFFICESaveHandler()
    }
    private var autosaveTask: Task<Void, Never>?
    private var watchMechanicalTask: Task<Void, Never>?
    private var watchLLMTask: Task<Void, Never>?
    private var structureRebuildTask: Task<Void, Never>?
    private var lastStructureParagraphCount = 0
    var isRerunSceneDetection = false

    func bootstrap() {
        registryLoadFailed = false
        do {
            try registry.load()
            _ = try? registry.pruneMissingProjectFolders()
            projects = registry.entries
        } catch {
            registryLoadFailed = true
            errorMessage = error.localizedDescription
            statusMessage = "Project library could not be loaded"
            projects = []
        }
        ruleFiles = EditRuleLoader.loadAll()
        DocumentEditorSettings.clearTestPollutedLegacyDefaultIfNeeded()
        documentEditorBridge.documentServerURL = DocumentEditorSettings.loadServerURL()
        documentEditorBridge.editorKind = DocumentEditorSettings.resolvedEditorKind()
        applyUITestInMemoryEditorOverrideIfNeeded()
        configureDocumentEditorBridge()
        configureONLYOFFICESaveHandler()
        Task { await refreshOllamaStatus() }
    }

    /// Called once from app launch — not from library refresh or unit tests.
    func beginEmbeddedOfficeStartupIfNeeded() {
        guard !UITestSupport.isRunningUnitTests else { return }
        editorStartupTask?.cancel()
        editorStartupTask = Task { [weak self] in
            await self?.prepareEmbeddedOfficeAtLaunch()
        }
    }

    private var shouldAutoPrepareEmbeddedOffice: Bool {
        guard documentEditorBridge.editorKind == .embeddedOffice else { return false }
        guard !UITestSupport.isActive else { return false }
        return true
    }

    func prepareEmbeddedOfficeAtLaunch() async {
        guard shouldAutoPrepareEmbeddedOffice else {
            editorStartup = .idle
            return
        }
        editorStartup = .loading(message: EditorStartupMessage.preparing)
        editorStartup = .loading(message: EditorStartupMessage.preparingManuscriptBridge)
        do {
            try LocalManuscriptDocumentServer.shared.ensureRunning()
        } catch {
            editorStartup = .unavailable(message: EditorStartupMessage.unavailable)
            return
        }
        let result = await ensureDocumentServerRunning(updateStartup: true)
        switch result {
        case .alreadyRunning, .startedManagedContainer:
            editorStartup = .ready
        case .failure:
            editorStartup = .unavailable(message: EditorStartupMessage.unavailable)
        }
    }

    @discardableResult
    func ensureDocumentServerRunning(updateStartup: Bool = false) async -> DocumentServerLaunchResult {
        let progress: (@Sendable (String) -> Void)?
        if updateStartup {
            progress = { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.editorStartup = .loading(message: message)
                }
            }
        } else {
            progress = nil
        }

        let result = await documentServerRuntime.startLocalDocumentServer(
            serverURL: documentEditorBridge.documentServerURL,
            healthChecker: LiveDocumentServerHealthChecker(),
            onProgress: progress
        )
        if case .startedManagedContainer = result {
            managedDocumentServerThisSession = true
        }
        return result
    }

    func shutdownEmbeddedOfficeIfNeeded() async {
        guard managedDocumentServerThisSession else { return }
        await documentServerRuntime.stopManagedDocumentServer()
        managedDocumentServerThisSession = false
    }

    private func configureONLYOFFICESaveHandler() {
        LocalManuscriptDocumentServer.shared.setSaveCompletionHandler { [weak self] documentID, result in
            await self?.handleONLYOFFICESaveBack(documentID: documentID, result: result)
        }
    }

    var activeDocumentDocxURL: URL? {
        guard let folder = currentFolder, let doc = activeDocument else { return nil }
        if let name = doc.docxFileName {
            return ProjectPaths.manuscriptFolder(in: folder).appendingPathComponent(name)
        }
        return ProjectPaths.documentDocxURL(folder: folder, documentID: doc.id)
    }

    var selectedTextInActiveDocument: String {
        guard let doc = activeDocument else { return "" }
        let text = doc.plainText
        guard selectionLength > 0, selectionLocation >= 0 else { return "" }
        let start = min(selectionLocation, text.count)
        let end = min(start + selectionLength, text.count)
        let startIdx = text.index(text.startIndex, offsetBy: start)
        let endIdx = text.index(text.startIndex, offsetBy: end)
        return String(text[startIdx..<endIdx])
    }

    func configureDocumentEditorBridge() {
        documentEditorBridge.configureLegacyProviders(
            plainText: { [weak self] in self?.activeDocument?.plainText },
            selection: { [weak self] in
                guard let self else { return nil }
                let selected = self.selectedTextInActiveDocument
                guard !selected.isEmpty else { return nil }
                return (selected, self.selectionLocation, self.selectionLength)
            }
        )
    }

    /// Pre-creates a project and opens the editor when launched with `-UITestSeedProject`.
    func seedProjectForUITest() {
        guard UITestSupport.isActive else { return }
        applyUITestInMemoryEditorOverrideIfNeeded()
        resetUITestLibraryIfNeeded()
        let name = "UITest-\(UUID().uuidString.prefix(8))"
        createProject(name: name, subtitle: "Automated UI test", coverURL: nil)
        guard currentProject != nil else {
            statusMessage = "UITest seed failed"
            return
        }
        if var doc = activeDocument, let folder = currentFolder {
            doc.plainText = "UITest manuscript paragraph.\n\nSecond paragraph for indexing."
            activeDocument = doc
            try? documentStore.save(doc, folder: folder)
            reindexDocument()
        }
        openEditor()
    }

    private func applyUITestInMemoryEditorOverrideIfNeeded() {
        guard UITestSupport.isActive else {
            DocumentEditorSettings.setInMemoryEditorKindOverride(nil)
            return
        }
        guard UITestSupport.prefersInMemoryLegacyEditor else {
            DocumentEditorSettings.setInMemoryEditorKindOverride(nil)
            documentEditorBridge.editorKind = DocumentEditorSettings.resolvedEditorKind()
            return
        }
        DocumentEditorSettings.setInMemoryEditorKindOverride(.legacyPrototype)
        documentEditorBridge.editorKind = .legacyPrototype
    }

    var documentEditorIntegrationStatus: DocumentEditorIntegrationStatus {
        DocumentEditorIntegrationStatus.resolve(
            editorKind: documentEditorBridge.editorKind,
            lifecycle: embeddedOfficeCoordinator.lifecycle,
            bridgeConnected: embeddedOfficeCoordinator.isEditingBridgeConnected,
            editorHostReady: embeddedOfficeCoordinator.isEditorHostReady
        )
    }

    private func resetUITestLibraryIfNeeded() {
        let root = UITestSupport.projectsRoot
        let registryURL = ProjectPaths.globalRegistryURL()
        if FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.removeItem(at: root)
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: registryURL.path) {
            try? FileManager.default.removeItem(at: registryURL)
        }
        registry.replaceEntriesForTesting([])
        projects = []
        currentProject = nil
        currentFolder = nil
        activeDocument = nil
        navigation = .library
    }

    func reloadProjectEditRules() {
        ruleFiles = EditRuleLoader.loadAll(projectFolder: currentFolder)
        if let folder = currentFolder {
            let copied = EditRuleLoader.copyBundledRulesToProject(folder: folder)
            if copied > 0 {
                ruleFiles = EditRuleLoader.loadAll(projectFolder: folder)
                statusMessage = "Copied \(copied) default rule files to project"
            } else {
                statusMessage = ruleFiles.isEmpty ? "No rule files loaded" : "\(ruleFiles.count) rule files loaded"
            }
        }
    }

    var referencePaneText: String? {
        guard let document = activeDocument else { return nil }
        switch splitEditorReference {
        case .none:
            return nil
        case .importSnapshot:
            return document.originalSnapshot
        case .acceptedBaseline:
            return document.acceptedPlainText
        case .selectedParagraph:
            guard let id = selectedParagraphID,
                  let indexed = documentIndex?.paragraphs.first(where: { $0.paragraph.id == id }) else {
                return nil
            }
            return indexed.paragraph.text
        }
    }

    var selectedText: String {
        guard let document = activeDocument, selectionLength > 0 else { return "" }
        let text = document.plainText
        let start = min(selectionLocation, text.count)
        let end = min(selectionLocation + selectionLength, text.count)
        guard start < end else { return "" }
        let s = text.index(text.startIndex, offsetBy: start)
        let e = text.index(text.startIndex, offsetBy: end)
        return String(text[s..<e])
    }

    var referencePaneTitle: String {
        switch splitEditorReference {
        case .none: ""
        case .importSnapshot: "Import snapshot"
        case .acceptedBaseline: "Accepted baseline"
        case .selectedParagraph: "Current paragraph"
        }
    }

    func refreshOllamaStatus() async {
        let settings = currentProject?.ollamaSettings ?? .default
        ollamaHealth = await llmCoordinator.provider.checkAvailability(settings: settings)
        llmCoordinator.configure(project: currentProject, performanceMode: performanceMode, health: ollamaHealth)
        analysisQueue.maxConcurrentLLM = settings.resolvedModelSettings.maxConcurrentLLMTasks
        switch ollamaHealth {
        case .unavailable(let reason):
            ollamaStatusText = "Ollama: unavailable"
            llmCoordinator.statusDetail = reason
        case .available(let models):
            let model = settings.effectivePrimaryModel.isEmpty ? (models.first ?? "ready") : settings.effectivePrimaryModel
            ollamaStatusText = "Ollama: \(model)"
        case .running:
            ollamaStatusText = "Ollama: running"
        }
        if analysisQueuePaused {
            ollamaStatusText += " · LLM paused"
        }
    }

    func createProject(name: String, subtitle: String, coverURL: URL?) {
        do {
            let parent = ProjectPaths.defaultProjectsRoot()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let (project, folder) = try projectStore.createProject(name: name, subtitle: subtitle, parentFolder: parent, coverSourceURL: coverURL)
            var manuscript = try documentStore.createManuscript(projectID: project.id, folder: folder)
            var updated = project
            updated.activeDocumentID = manuscript.id
            try projectStore.saveProject(updated, folder: folder)
            manuscript = try documentStore.load(documentID: manuscript.id, folder: folder)
            openProject(entry: ProjectRegistryEntry(
                id: project.id, name: project.name, subtitle: project.subtitle, folderURL: folder,
                coverImagePath: project.coverImagePath, lastOpened: Date(), lastEdited: Date(),
                wordCount: 0, diagnosticsSummary: .empty, lastAnalysisStatus: nil
            ))
            statusMessage = "Created project \(name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openProject(entry: ProjectRegistryEntry) {
        do {
            let project = try projectStore.openProject(folder: entry.folderURL)
            currentProject = project
            currentFolder = entry.folderURL
            documents = documentStore.listDocuments(folder: entry.folderURL)
            loadProjectSidecarData(folder: entry.folderURL)
            performanceMode = project.settings.performanceMode
            if let docID = project.activeDocumentID, let doc = documents.first(where: { $0.id == docID }) {
                loadDocument(doc)
            } else if let first = documents.first {
                loadDocument(first)
            }
            var entry = entry
            entry.lastOpened = Date()
            syncRegistryEntry(entry)
            navigation = .projectOverview(project.id)
            reloadProjectEditRules()
            applyEnabledRulesFromProject()
            Task { await refreshOllamaStatus() }
            statusMessage = "Opened \(project.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openEditor() {
        guard let project = currentProject else { return }
        navigation = .workspace(project.id)
    }

    func openCanonVault() {
        openEditor()
        workspaceSidebarTab = .canon
    }

    func createAdditionalManuscript() {
        guard let project = currentProject, let folder = currentFolder else { return }
        do {
            let doc = try documentStore.createManuscript(projectID: project.id, folder: folder, title: "Manuscript \(documents.count + 1)")
            documents.append(doc)
            loadDocument(doc)
            statusMessage = "Created \(doc.title)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDocument(_ document: Document) {
        guard let folder = currentFolder else { return }
        var doc = document
        let acceptedURL = ProjectPaths.acceptedManuscriptURL(folder: folder, documentID: document.id)
        if doc.acceptedPlainText == nil, FileManager.default.fileExists(atPath: acceptedURL.path) {
            do {
                let data = try Data(contentsOf: acceptedURL)
                doc.acceptedPlainText = String(data: data, encoding: .utf8)
            } catch {
                reportPersistenceFailure("Accepted baseline", error)
            }
        }
        do {
            try documentStore.ensurePrimaryDocxFile(document: &doc, folder: folder)
            try documentStore.save(doc, folder: folder)
        } catch {
            reportPersistenceFailure("DOCX manuscript file", error)
        }
        activeDocument = doc
        documentSaveState = .saved
        configureDocumentEditorBridge()
        documentEditorBridge.refreshSelection()
        do {
            structure = try documentStore.loadStructure(documentID: document.id, folder: folder)
        } catch {
            reportPersistenceFailure("Structure", error)
            structure = DocumentStructure(chapters: [], scenes: [])
        }
        do {
            documentIndex = try documentStore.loadIndex(documentID: document.id, folder: folder)
        } catch {
            reportPersistenceFailure("Paragraph index", error)
            documentIndex = nil
        }
        do {
            diagnostics = try diagnosticsStore.load(documentID: document.id, folder: folder)
        } catch {
            reportPersistenceFailure("Diagnostics", error)
            diagnostics = []
        }
        do {
            proposals = try diagnosticsStore.loadProposals(documentID: document.id, folder: folder)
        } catch {
            reportPersistenceFailure("Proposals", error)
            proposals = []
        }
        if let folder = currentFolder {
            do {
                if let persisted = try EmbeddingIndexStore.load(documentID: doc.id, folder: folder) {
                    semanticIndex.loadPersisted(index: persisted)
                }
            } catch {
                reportPersistenceFailure("Semantic index", error)
            }
        }
        bumpEditorContentEpoch()
        reindexDocument()
        manualReview = ManualReviewCalculator.status(diagnostics: diagnostics, proposals: proposals)
        syncEmbeddedOfficeEditor()
    }

    func reindexDocument() {
        guard activeDocument != nil else { return }
        let (index, dirty, deletedParagraphIDs) = paragraphIndexer.rebuildIndex(
            documentID: activeDocument!.id,
            text: activeDocument!.plainText,
            existing: documentIndex
        )
        var storedIndex = index
        storedIndex.dirtyParagraphStates = dirty
        documentIndex = storedIndex
        dirtyStates = dirty
        if let folder = currentFolder {
            persistIndexBestEffort(storedIndex, folder: folder)
        }
        let dirtyIDs = Set(dirty.map(\.paragraphID))
        if !dirtyIDs.isEmpty, !isRerunSceneDetection {
            SceneIndexService.markStaleNearEdits(structure: &structure, dirtyParagraphIDs: dirtyIDs)
        }
        let hashes = Dictionary(uniqueKeysWithValues: index.paragraphs.map { ($0.paragraph.id, $0.paragraph.hash) })
        ParagraphIndexService.markDiagnosticsStale(
            diagnostics: &diagnostics,
            dirtyParagraphIDs: dirtyIDs,
            deletedParagraphIDs: deletedParagraphIDs,
            paragraphHashes: hashes
        )
        if !dirtyIDs.isEmpty || !deletedParagraphIDs.isEmpty {
            persistDiagnostics()
            manualReview = ManualReviewCalculator.status(
                diagnostics: diagnostics,
                proposals: proposals,
                llmPassesEnabled: currentProject?.ollamaSettings.llmPassesEnabled ?? true
            )
        }
        markNarrativeMemoryStale(dirtyParagraphIDs: dirtyIDs, index: index)
        let (paused, reason) = PerformancePolicyService.shouldPauseLLM(mode: performanceMode)
        analysisQueue.setPaused(paused, reason: reason)
        analysisQueuePaused = paused
        analysisQueuePauseReason = reason
        if let folder = currentFolder {
            persistIndexBestEffort(index, folder: folder)
        }
        updateWordCount()
        scheduleStructureRebuild(paragraphCount: index.paragraphs.count)
        rebuildSemanticIndex()
    }

    private func scheduleStructureRebuild(paragraphCount: Int) {
        structureRebuildTask?.cancel()
        let shouldRebuildImmediately = abs(paragraphCount - lastStructureParagraphCount) > 2
        lastStructureParagraphCount = paragraphCount
        if shouldRebuildImmediately {
            rebuildStructureNow(preserveManual: false)
            return
        }
        structureRebuildTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            rebuildStructureNow(preserveManual: false)
        }
    }

    func onEditorTextChange(_ text: String) {
        guard var document = activeDocument, let folder = currentFolder else { return }
        document.plainText = text
        activeDocument = document
        isTyping = true
        documentSaveState = .unsaved
        analysisQueue.markTyping(true)
        scheduleAutosave(document: document, folder: folder)
        reindexDocument()
        if activeWatchEnabled, performanceMode != .manualOnly {
            scheduleActiveWatch()
        }
    }

    func onTypingEnded() {
        isTyping = false
        analysisQueue.markTyping(false)
    }

    func saveActiveDocumentNow() {
        guard let document = activeDocument, let folder = currentFolder else { return }
        autosaveTask?.cancel()
        persistDocument(document, folder: folder)
    }

    func flushPendingSave() {
        guard documentSaveState == .unsaved, let document = activeDocument, let folder = currentFolder else { return }
        autosaveTask?.cancel()
        persistDocument(document, folder: folder)
    }

    private func scheduleAutosave(document: Document, folder: URL) {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let doc = activeDocument else { return }
                persistDocument(doc, folder: folder)
            }
        }
    }

    private func persistDocument(_ document: Document, folder: URL) {
        documentSaveState = .saving
        do {
            try documentStore.save(document, folder: folder)
            if var project = currentProject {
                project.wordCount = TextUtilities.wordCount(document.plainText)
                currentProject = project
                try projectStore.saveProject(project, folder: folder)
            }
            documentSaveState = .saved
            if let project = currentProject {
                ManuscriptSnapshotService.writeCheckpointIfDue(document: document, projectID: project.id, folder: folder)
            }
        } catch {
            documentSaveState = .saveError
            errorMessage = error.localizedDescription
            statusMessage = "Save failed"
        }
    }

    private func scheduleActiveWatch() {
        watchMechanicalTask?.cancel()
        watchLLMTask?.cancel()
        let mechDelay = PerformancePolicyService.mechanicalDebounce(mode: performanceMode)
        watchMechanicalTask = Task {
            try? await Task.sleep(for: mechDelay)
            guard !Task.isCancelled else { return }
            onTypingEnded()
            guard let project = currentProject else { return }
            analysisQueue.enqueue(AnalysisJob(
                id: UUID(),
                priority: .paragraphMechanical,
                scopeKey: "paragraph-\(selectedParagraphID?.uuidString ?? "current")",
                isLLM: false,
                label: "Paragraph mechanical"
            ) { [weak self] in
                await MainActor.run { self?.runParagraphDiagnostics() }
            })
            if dirtyStates.count > 2 {
                analysisQueue.enqueue(AnalysisJob(
                    id: UUID(),
                    priority: .sceneMechanical,
                    scopeKey: "scene-mechanical",
                    isLLM: false,
                    label: "Scene mechanical"
                ) { [weak self] in
                    await MainActor.run { self?.runSceneAnalysis() }
                })
            }
            scheduleActiveWatchLLM(project: project)
        }
    }

    private func scheduleActiveWatchLLM(project: Project) {
        guard PerformancePolicyService.allowsLLMWatch(mode: performanceMode, ollamaEnabled: project.ollamaSettings.llmPassesEnabled) else { return }
        let (paused, _) = PerformancePolicyService.shouldPauseLLM(mode: performanceMode)
        guard !paused else { return }
        watchLLMTask?.cancel()
        let llmDelay = PerformancePolicyService.llmDebounce(mode: performanceMode)
        watchLLMTask = Task {
            try? await Task.sleep(for: llmDelay)
            guard !Task.isCancelled, !isTyping else { return }
            analysisQueue.enqueue(AnalysisJob(
                id: UUID(),
                priority: .selectedLLM,
                scopeKey: "paragraph-llm-\(selectedParagraphID?.uuidString ?? "current")",
                isLLM: true,
                label: "Paragraph LLM"
            ) { [weak self] in
                await self?.runWatchLLMAnalysis()
            })
        }
    }

    private func runWatchLLMAnalysis() async {
        guard let project = currentProject, let document = activeDocument, let index = documentIndex else { return }
        guard case .available = ollamaHealth, project.ollamaSettings.llmPassesEnabled else { return }
        let packet = ContextBuilder().build(
            task: "Active watch paragraph analysis",
            scope: .paragraph,
            document: document,
            index: index,
            paragraphID: selectedParagraphID,
            structure: structure,
            memory: narrativeMemory,
            canon: canonEntities,
            ruleFiles: enabledRuleFiles,
            categories: [.minimumGate, .coreProse],
            diagnostics: diagnostics
        )
        let prompt = """
        Analyze the paragraph JSON only. Return strict JSON matching LLMAnalysisResponse schema.
        Context: \(packet.currentText.prefix(2000))
        """
        do {
            let response = try await llmCoordinator.runJSONTask(
                task: .paragraphLLM,
                prompt: prompt,
                settings: project.ollamaSettings,
                performanceMode: performanceMode,
                as: LLMAnalysisResponse.self
            )
            await MainActor.run {
                mergeLLMWatchResults(response, projectID: project.id, documentID: document.id)
            }
        } catch let error as LocalLLMError {
            if case .skipped(let reason) = error {
                await MainActor.run { statusMessage = reason }
            }
        } catch {
            await MainActor.run {
                let fail = DiagnosticEvidence.llmPassFailure(
                    projectID: project.id,
                    documentID: document.id,
                    passName: "Active Watch",
                    error: error.localizedDescription,
                    paragraphID: selectedParagraphID
                )
                diagnostics.append(fail)
                persistDiagnostics()
                manualReview = ManualReviewCalculator.status(diagnostics: diagnostics, proposals: proposals)
                statusMessage = "Watch LLM failed: \(error.localizedDescription)"
            }
        }
    }

    private func mergeLLMWatchResults(_ response: LLMAnalysisResponse, projectID: UUID, documentID: UUID) {
        let paragraphText = selectedParagraphID.flatMap { pid in
            documentIndex?.paragraphs.first { $0.paragraph.id == pid }?.paragraph.text
        }
        for llm in response.diagnostics {
            diagnostics.append(Diagnostic(
                id: UUID(),
                projectID: projectID,
                documentID: documentID,
                chapterID: nil,
                sceneID: nil,
                paragraphID: selectedParagraphID,
                ruleID: nil,
                source: .llm,
                severity: RuleSeverity(rawValue: llm.severity) ?? .warning,
                scope: RuleScope(rawValue: llm.scope) ?? .paragraph,
                title: llm.title,
                message: llm.message,
                evidence: DiagnosticEvidence.clamp(llm.evidence, paragraphText: paragraphText),
                startOffset: nil,
                endOffset: nil,
                suggestedFix: llm.suggestedFix,
                fixLevel: FixLevel(rawValue: llm.fixLevel) ?? .humanOnly,
                status: .open,
                textHashAtCreation: documentIndex?.paragraphs.first { $0.paragraph.id == selectedParagraphID }?.paragraph.hash,
                scopeHashAtCreation: nil,
                isStale: false,
                staleReason: nil,
                createdAt: Date()
            ))
        }
        persistDiagnostics()
        manualReview = ManualReviewCalculator.status(diagnostics: diagnostics, proposals: proposals)
        statusMessage = "Active watch: \(response.diagnostics.count) LLM notes"
    }

    var enabledRuleFiles: [EditRuleFile] {
        ruleFiles.filter(\.enabled)
    }

    func applyEnabledRulesFromProject() {
        guard let project = currentProject else { return }
        let enabled = Set(project.enabledRuleFileIDs)
        for i in ruleFiles.indices {
            ruleFiles[i].enabled = enabled.isEmpty ? true : enabled.contains(ruleFiles[i].id)
        }
    }

    func setRuleFileEnabled(_ fileID: UUID, enabled: Bool) {
        guard let idx = ruleFiles.firstIndex(where: { $0.id == fileID }),
              var project = currentProject, let folder = currentFolder else { return }
        ruleFiles[idx].enabled = enabled
        if enabled {
            if !project.enabledRuleFileIDs.contains(fileID) {
                project.enabledRuleFileIDs.append(fileID)
            }
        } else {
            project.enabledRuleFileIDs.removeAll { $0 == fileID }
        }
        currentProject = project
        persistProject(project, folder: folder)
    }

    private func markNarrativeMemoryStale(dirtyParagraphIDs: Set<UUID>, index: DocumentIndex) {
        guard !dirtyParagraphIDs.isEmpty else { return }
        for i in narrativeMemory.indices {
            switch narrativeMemory[i].scope {
            case .scene:
                if let scene = structure.scenes.first(where: { $0.id == narrativeMemory[i].scopeID }),
                   let start = scene.startParagraphID, dirtyParagraphIDs.contains(start) {
                    narrativeMemory[i].sourceHash = nil
                }
            case .chapter:
                if let ch = structure.chapters.first(where: { $0.id == narrativeMemory[i].scopeID }),
                   let start = ch.startParagraphID, dirtyParagraphIDs.contains(start) {
                    narrativeMemory[i].sourceHash = nil
                }
            case .document:
                if dirtyParagraphIDs.count > 0 {
                    narrativeMemory[i].sourceHash = nil
                }
            default:
                break
            }
        }
        _ = index
    }

    func isMemoryStale(_ memory: NarrativeMemory) -> Bool {
        memory.sourceHash == nil
    }

    func openExistingProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select an .ivproject folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard folder.pathExtension == ProjectPaths.projectExtension || FileManager.default.fileExists(atPath: ProjectPaths.projectJSON(in: folder).path) else {
            errorMessage = "Not a valid iV project folder"
            return
        }
        do {
            let project = try projectStore.openProject(folder: folder)
            let entry = ProjectRegistryEntry(
                id: project.id, name: project.name, subtitle: project.subtitle, folderURL: folder,
                coverImagePath: project.coverImagePath, lastOpened: Date(), lastEdited: project.updatedAt,
                wordCount: project.wordCount ?? 0, diagnosticsSummary: project.diagnosticsSummary,
                lastAnalysisStatus: project.lastPipelineStatus
            )
            syncRegistryEntry(entry)
            openProject(entry: entry)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runSelectionAnalysis() {
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Select text to analyze"
            return
        }
        runScopedDiagnostics(maxScope: .selection, includeSelection: true)
    }

    func runParagraphDiagnostics() {
        runScopedDiagnostics(maxScope: .paragraphWindow)
    }

    func runSceneAnalysis() {
        runScopedDiagnostics(maxScope: .scene)
    }

    func runChapterAnalysis() {
        runScopedDiagnostics(maxScope: .chapter)
    }

    private func runScopedDiagnostics(maxScope: RuleScope, includeSelection: Bool = false) {
        guard let project = currentProject, let document = activeDocument, let index = documentIndex else { return }
        let paragraphID = selectedParagraphID ?? index.paragraphs.first?.paragraph.id
        let result = analysisCoordinator.runExpandedAnalysis(
            project: project,
            document: document,
            index: index,
            structure: structure,
            canon: canonEntities,
            ruleFiles: enabledRuleFiles,
            paragraphID: paragraphID,
            selectionText: includeSelection ? selectedText : nil,
            maxScope: maxScope
        )
        let affectedParagraph = paragraphID
        for i in diagnostics.indices {
            guard diagnostics[i].source == .deterministic, !diagnostics[i].isStale else { continue }
            if affectedParagraph == nil || diagnostics[i].paragraphID == affectedParagraph {
                diagnostics[i].isStale = true
                diagnostics[i].status = .stale
                diagnostics[i].staleReason = "Superseded by new analysis"
            }
        }
        diagnostics.append(contentsOf: result.diagnostics)
        persistDiagnostics()
        manualReview = ManualReviewCalculator.status(diagnostics: diagnostics, proposals: proposals)
        statusMessage = "Analysis: \(result.diagnostics.count) issues across \(result.scopesRun.count) scopes"
    }

    func runSafeAutoFix() {
        guard var document = activeDocument else { return }
        if let fix = safeFix.apply(to: document.plainText, canon: canonEntities) {
            let proposal = ChangeProposalService.makeProposal(
                projectID: currentProject?.id ?? UUID(),
                documentID: document.id,
                scope: .document,
                scopeID: nil,
                source: .deterministic,
                title: "Safe auto fix",
                reason: fix.description,
                beforeText: fix.original,
                afterText: fix.fixed,
                riskLevel: .low
            )
            proposals.append(proposal)
            openProposalForReview(proposal)
            statusMessage = "Safe fixes prepared for review"
        } else {
            statusMessage = "No safe fixes available"
        }
        persistProposals()
    }

    func runFullPipeline() {
        guard let project = currentProject, let document = activeDocument, let index = documentIndex, let folder = currentFolder else { return }
        isPipelineRunning = true
        pipelinePassResults = []
        let provider: (any LocalAIProvider)? = {
            if case .available = ollamaHealth, project.ollamaSettings.llmPassesEnabled { return llmCoordinator.provider }
            return nil
        }()
        let input = PipelineInput(
            project: project,
            document: document,
            index: index,
            structure: structure,
            canon: canonEntities,
            memory: narrativeMemory,
            ruleFiles: enabledRuleFiles,
            diagnostics: diagnostics,
            scope: .paragraph,
            paragraphID: selectedParagraphID,
            aiProvider: provider,
            routeLLM: { [weak self] task in
                self?.llmCoordinator.route(task) ?? .mechanicalOnly
            }
        )
        Task {
            let (run, newDiags, newProposals, newCanon) = await pipelineEngine.run(passes: pipelineEngine.defaultPasses(), input: input) { result in
                Task { @MainActor in
                    if let idx = self.pipelinePassResults.firstIndex(where: { $0.id == result.id }) {
                        self.pipelinePassResults[idx] = result
                    } else {
                        self.pipelinePassResults.append(result)
                    }
                }
            }
            diagnostics = newDiags
            proposals.append(contentsOf: newProposals)
            mergeCanonSuggestions(newCanon)
            analysisRuns.append(run)
            persistAnalysisRuns()
            isPipelineRunning = false
            persistDiagnostics()
            persistProposals()
            let summary = PipelineRunSummary.summarize(passResults: run.passResults)
            manualReview = ManualReviewCalculator.status(
                diagnostics: diagnostics,
                proposals: proposals,
                passResults: run.passResults,
                llmPassesEnabled: project.ollamaSettings.llmPassesEnabled
            )
            var project = project
            project.lastPipelineStatus = summary.statusLabel
            project.diagnosticsSummary = summarizeDiagnostics()
            persistProject(project, folder: folder)
            currentProject = project
            statusMessage = summary.statusLabel
            await llmCoordinator.scheduleUnloadIfNeeded(
                settings: project.ollamaSettings,
                policy: project.ollamaSettings.resolvedModelSettings.keepAlivePolicy,
                performanceMode: performanceMode
            )
        }
    }

    func buildContextPreview() {
        guard let project = currentProject, let document = activeDocument, let index = documentIndex else { return }
        contextPacket = ContextBuilder().build(
            task: "Preview context",
            scope: .paragraph,
            document: document,
            index: index,
            paragraphID: selectedParagraphID,
            structure: structure,
            memory: narrativeMemory,
            canon: canonEntities,
            ruleFiles: enabledRuleFiles,
            categories: [.minimumGate, .coreProse],
            diagnostics: diagnostics
        )
    }

    func reloadEditRules() {
        if currentFolder != nil {
            reloadProjectEditRules()
        } else {
            ruleFiles = EditRuleLoader.loadAll()
            statusMessage = ruleFiles.isEmpty ? "No rule files loaded" : "\(ruleFiles.count) rule files loaded"
        }
    }

    func setDiagnosticStatus(_ id: UUID, status: DiagnosticStatus) {
        guard let idx = diagnostics.firstIndex(where: { $0.id == id }) else { return }
        diagnostics[idx].status = status
        if status == .resolved || status == .ignored {
            diagnostics[idx].isStale = false
        }
        persistDiagnostics()
        manualReview = ManualReviewCalculator.status(diagnostics: diagnostics, proposals: proposals)
        updateWordCount()
    }

    func applySafeFix(for diagnostic: Diagnostic) {
        guard diagnostic.fixLevel == .safeAutoFix else {
            statusMessage = "Editorial fixes require a change proposal — use Create proposal"
            return
        }
        guard let document = activeDocument, let project = currentProject else { return }

        let before: String
        let after: String

        if let pid = diagnostic.paragraphID,
           let indexed = documentIndex?.paragraphs.first(where: { $0.paragraph.id == pid }) {
            let text = document.plainText
            let start = text.index(text.startIndex, offsetBy: indexed.rangeStart)
            let end = text.index(text.startIndex, offsetBy: min(indexed.rangeEnd, text.count))
            let paragraphText = String(text[start..<end])
            if let fix = safeFix.apply(to: paragraphText, canon: canonEntities) {
                before = paragraphText
                after = fix.fixed
            } else if let suggested = diagnostic.suggestedFix {
                before = paragraphText
                after = suggested
            } else {
                statusMessage = "No safe fix available"
                return
            }
        } else if let fix = safeFix.apply(to: document.plainText, canon: canonEntities) {
            before = fix.original
            after = fix.fixed
        } else {
            statusMessage = "No safe fix available"
            return
        }

        let proposal = ChangeProposalService.makeProposal(
            projectID: project.id,
            documentID: document.id,
            scope: diagnostic.scope,
            scopeID: diagnostic.paragraphID,
            source: .deterministic,
            title: "Safe fix: \(diagnostic.title)",
            reason: diagnostic.message,
            beforeText: before,
            afterText: after,
            riskLevel: .low
        )
        proposals.append(proposal)
        openProposalForReview(proposal)
        persistProposals()
        statusMessage = "Safe fix prepared for review"
    }

    func refreshSummaries(useLLM: Bool = false) {
        guard let project = currentProject, let document = activeDocument, let index = documentIndex else { return }
        Task {
            var updated: [NarrativeMemory] = narrativeMemory
            let sceneMemories = SummaryRefreshService.refreshSceneSummaries(structure: structure, index: index, projectID: project.id)
            let chapterMemories = SummaryRefreshService.refreshChapterSummaries(structure: structure, index: index, projectID: project.id)
            let docMemory = SummaryRefreshService.refreshDocumentSummary(document: document, projectID: project.id)

            updated.removeAll { $0.scope == .scene || $0.scope == .chapter || ($0.scope == .document && $0.scopeID == document.id) }
            updated.append(contentsOf: sceneMemories)
            updated.append(contentsOf: chapterMemories)
            updated.append(docMemory)

            if useLLM, case .available = ollamaHealth, project.ollamaSettings.llmPassesEnabled {
                for i in updated.indices where updated[i].scope == .scene {
                    if let scene = structure.scenes.first(where: { $0.id == updated[i].scopeID }) {
                        let text = SummaryRefreshService.refreshSceneSummaries(structure: structure, index: index, projectID: project.id)
                            .first(where: { $0.scopeID == scene.id })?.summary ?? ""
                        if let summary = try? await SummaryRefreshService.refreshViaLLM(
                            scope: .scene, scopeID: scene.id, text: text, project: project, provider: llmCoordinator.provider
                        ) {
                            updated[i].summary = summary
                        }
                    }
                }
            }

            narrativeMemory = updated
            persistNarrativeMemory()
            statusMessage = "Summaries refreshed (\(sceneMemories.count) scenes, \(chapterMemories.count) chapters)"
        }
    }

    func acceptCanonSuggestion(_ suggestion: CanonUpdateSuggestion) {
        guard let projectID = currentProject?.id else { return }
        if let idx = canonEntities.firstIndex(where: { $0.name == suggestion.name && $0.type == suggestion.entityType }) {
            canonEntities[idx].facts.append(suggestion.fact)
            canonEntities[idx].updatedAt = Date()
        } else {
            addCanonEntity(CanonEntity(
                id: UUID(),
                projectID: projectID,
                type: suggestion.entityType,
                name: suggestion.name,
                aliases: [],
                description: "",
                facts: [suggestion.fact],
                constraints: [],
                createdAt: Date(),
                updatedAt: Date()
            ))
        }
        if let idx = canonSuggestions.firstIndex(where: { $0.id == suggestion.id }) {
            canonSuggestions[idx].status = .accepted
        }
        persistCanonSuggestions()
        statusMessage = "Canon updated: \(suggestion.name)"
    }

    func rejectCanonSuggestion(_ suggestion: CanonUpdateSuggestion) {
        if let idx = canonSuggestions.firstIndex(where: { $0.id == suggestion.id }) {
            canonSuggestions[idx].status = .rejected
        }
        persistCanonSuggestions()
    }

    private func mergeCanonSuggestions(_ incoming: [CanonUpdateSuggestion]) {
        for suggestion in incoming where suggestion.status == .pending {
            if !canonSuggestions.contains(where: { $0.name == suggestion.name && $0.fact == suggestion.fact && $0.status == .pending }) {
                canonSuggestions.append(suggestion)
            }
        }
        persistCanonSuggestions()
    }

    private func persistCanonSuggestions() {
        guard let folder = currentFolder else { return }
        do {
            try canonSuggestionStore.save(canonSuggestions, folder: folder)
        } catch {
            reportPersistenceFailure("Canon suggestions", error)
        }
    }

    func createProposalFromDiagnostic(_ diagnostic: Diagnostic) {
        guard let document = activeDocument, let project = currentProject else { return }
        let before: String
        if let pid = diagnostic.paragraphID,
           let indexed = documentIndex?.paragraphs.first(where: { $0.paragraph.id == pid }) {
            before = indexed.paragraph.text
        } else {
            before = diagnostic.evidence
        }
        let after = diagnostic.suggestedFix ?? before
        let proposal = ChangeProposalService.makeProposal(
            projectID: project.id,
            documentID: document.id,
            scope: diagnostic.scope,
            scopeID: diagnostic.paragraphID,
            source: diagnostic.source == .llm ? .llm : .deterministic,
            title: diagnostic.title,
            reason: diagnostic.message,
            beforeText: before,
            afterText: after,
            riskLevel: diagnostic.fixLevel == .safeAutoFix ? .low : .medium
        )
        proposals.append(proposal)
        openProposalForReview(proposal)
        persistProposals()
    }

    func runDeeperAnalysis(for diagnostic: Diagnostic) {
        if let pid = diagnostic.paragraphID {
            selectedParagraphID = pid
        }
        switch diagnostic.scope {
        case .scene, .previousSceneCurrentScene:
            runSceneAnalysis()
        case .chapter, .chapterSection, .previousChapterCurrentChapter:
            runChapterAnalysis()
        default:
            runParagraphDiagnostics()
        }
    }

    func expandSceneWithLLM(skeleton: String, outcome: String) async {
        guard let project = currentProject, let document = activeDocument, let index = documentIndex else {
            errorMessage = "No active manuscript"
            return
        }
        isSceneExpansionRunning = true
        statusMessage = "Expanding scene via Ollama…"

        let packet = ContextBuilder().build(
            task: "Expand scene skeleton",
            scope: .scene,
            document: document,
            index: index,
            paragraphID: selectedParagraphID,
            structure: structure,
            memory: narrativeMemory,
            canon: canonEntities,
            ruleFiles: enabledRuleFiles,
            categories: [.dialogue, .characterVoice, .atmosphereSensory, .minimumGate],
            diagnostics: diagnostics
        )

        let result = await SceneExpansionCoordinator.expand(
            skeleton: skeleton,
            outcome: outcome,
            project: project,
            document: document,
            context: packet,
            coordinator: llmCoordinator,
            performanceMode: performanceMode
        )

        isSceneExpansionRunning = false
        switch result {
        case .success(let proposal):
            proposals.append(proposal)
            openProposalForReview(proposal)
            persistProposals()
            statusMessage = "Scene expansion ready for review"
        case .failure(let error):
            if case .unavailable = ollamaHealth {
                statusMessage = "Ollama unavailable. Scene expansion is unavailable; deterministic checks still work."
            } else {
                errorMessage = "Scene expansion failed: \(error.localizedDescription)"
                statusMessage = "Scene expansion failed"
            }
        }
    }

    func suggestChapterSplits() {
        guard let index = documentIndex else { return }
        chapterSplitSuggestions = ChapterSplitAnalyzer.suggestSplits(index: index)
        statusMessage = "\(chapterSplitSuggestions.count) split suggestions"
    }

    func createChapterSplitProposal(_ suggestion: ChapterSplitSuggestion) {
        guard let project = currentProject, let document = activeDocument,
              let indexed = documentIndex?.paragraphs.first(where: { $0.paragraph.id == suggestion.paragraphID }) else { return }
        let marker = suggestion.splitType == .hardChapterBreak ? "\n\n***\n\n" : "\n\n---\n\n"
        let before = indexed.paragraph.text
        let after = before + marker
        let proposal = ChangeProposalService.makeProposal(
            projectID: project.id,
            documentID: document.id,
            scope: .chapter,
            scopeID: suggestion.paragraphID,
            source: .chapterSplit,
            title: "Chapter split: \(suggestion.splitType.rawValue)",
            reason: suggestion.reason,
            beforeText: before,
            afterText: after,
            riskLevel: suggestion.risk
        )
        proposals.append(proposal)
        openProposalForReview(proposal)
        persistProposals()
    }

    func clearAllDiagnostics() {
        diagnostics.removeAll()
        persistDiagnostics()
        manualReview = ManualReviewCalculator.status(diagnostics: diagnostics, proposals: proposals)
        statusMessage = "Diagnostics cleared"
    }

    func clearAnalysisRunHistory() {
        analysisRuns.removeAll()
        persistAnalysisRuns()
        statusMessage = "Analysis history cleared"
    }

    func updateCanonEntity(_ entity: CanonEntity) {
        guard let idx = canonEntities.firstIndex(where: { $0.id == entity.id }) else { return }
        canonEntities[idx] = entity
        persistCanon()
        statusMessage = "Canon updated"
    }

    func acceptProposal(_ proposal: ChangeProposal, editedAfter: String? = nil) {
        guard var document = activeDocument else { return }
        createSafetySnapshot(reason: .beforeRuleApply, note: "Before applying proposal")
        let replacement = editedAfter ?? proposal.afterText
        if let scopeID = proposal.scopeID, let indexed = documentIndex?.paragraphs.first(where: { $0.paragraph.id == scopeID }) {
            var text = document.plainText
            let range = indexed.rangeStart..<indexed.rangeEnd
            let start = text.index(text.startIndex, offsetBy: range.lowerBound)
            let end = text.index(text.startIndex, offsetBy: min(range.upperBound, text.count))
            text.replaceSubrange(start..<end, with: replacement)
            document.plainText = text
        } else {
            document.plainText = document.plainText.replacingOccurrences(of: proposal.beforeText, with: replacement)
        }
        document.acceptedPlainText = document.plainText
        activeDocument = document
        if let folder = currentFolder {
            do {
                try documentStore.save(document, folder: folder)
            } catch {
                reportPersistenceFailure("Manuscript", error)
            }
            persistAcceptedBaseline(document.plainText, documentID: document.id, folder: folder)
        }
        if let idx = proposals.firstIndex(where: { $0.id == proposal.id }) {
            proposals[idx].status = editedAfter == nil ? .accepted : .edited
        }
        bumpEditorContentEpoch()
        onEditorTextChange(document.plainText)
        persistProposals()
    }

    func rejectProposal(_ proposal: ChangeProposal) {
        if let idx = proposals.firstIndex(where: { $0.id == proposal.id }) {
            proposals[idx].status = .rejected
        }
        persistProposals()
        manualReview = ManualReviewCalculator.status(diagnostics: diagnostics, proposals: proposals)
    }

    func openProposalForReview(_ proposal: ChangeProposal) {
        selectedProposal = proposal
        revisionReviewActive = true
        diffDisplayMode = .lightHighlight
    }

    func addCanonEntity(_ entity: CanonEntity) {
        canonEntities.append(entity)
        persistCanon()
    }

    func importManuscript(service: DocumentImportService, replaceActive: Bool = false) {
        guard let project = currentProject, let folder = currentFolder else { return }
        do {
            if replaceActive, var existing = activeDocument {
                createSafetySnapshot(reason: .beforeImport, note: "Before import replace")
                let imported = try ImportExportCoordinator.pickAndImport(service: service)
                existing.plainText = imported.plainText
                existing.formattingSpans = imported.formattingSpans
                existing.updatedAt = Date()
                let archived = try ManuscriptSnapshotService.archiveImportSnapshot(
                    text: imported.plainText,
                    documentID: existing.id,
                    folder: folder,
                    label: "import-replace",
                    projectID: project.id
                )
                try documentStore.save(existing, folder: folder)
                loadDocument(existing)
                reindexDocument()
                statusMessage = "Replaced working manuscript for \(existing.title). Original import snapshot preserved; new import archived as \(archived.lastPathComponent)."
                return
            }
            let document = try ImportExportCoordinator.importFile(service: service, projectID: project.id, folder: folder, documentStore: documentStore)
            documents.append(document)
            loadDocument(document)
            statusMessage = "Imported \(document.title) (\(service.menuLabel))"
        } catch {
            if (error as NSError).code != 0 { errorMessage = error.localizedDescription }
        }
    }

    func deleteDocument(_ document: Document) {
        guard let folder = currentFolder, let project = currentProject else { return }
        if activeDocument?.id == document.id {
            createSafetySnapshot(reason: .beforeDestructiveAction, note: "Before delete document")
        }
        do {
            try documentStore.deleteDocument(documentID: document.id, folder: folder)
            try? ManuscriptSnapshotStore.deleteSnapshots(documentID: document.id, folder: folder)
            documents.removeAll { $0.id == document.id }
            if activeDocument?.id == document.id {
                if let next = documents.first {
                    loadDocument(next)
                } else {
                    activeDocument = nil
                    documentIndex = nil
                    diagnostics = []
                    proposals = []
                    syncEmbeddedOfficeEditor()
                }
            }
            if project.activeDocumentID == document.id, var updated = currentProject {
                updated.activeDocumentID = activeDocument?.id
                try projectStore.saveProject(updated, folder: folder)
                currentProject = updated
            }
            statusMessage = "Deleted \(document.title)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCanonEntity(id: UUID) {
        canonEntities.removeAll { $0.id == id }
        persistCanon()
        statusMessage = "Canon entry removed"
    }

    func exportManuscript(service: DocumentExportService) {
        guard let document = activeDocument else { return }
        do {
            try ImportExportCoordinator.exportFile(service: service, document: document)
            statusMessage = "Exported \(document.title) (\(service.menuLabel))"
        } catch {
            if (error as NSError).code != 0 { errorMessage = error.localizedDescription }
        }
    }

    func createSceneExpansionProposal(skeleton: String, outcome: String) {
        Task { await expandSceneWithLLM(skeleton: skeleton, outcome: outcome) }
    }

    func addNarrativeMemory(_ memory: NarrativeMemory) {
        narrativeMemory.append(memory)
        persistNarrativeMemory()
    }

    func updateNarrativeMemory(_ memory: NarrativeMemory) {
        guard let idx = narrativeMemory.firstIndex(where: { $0.id == memory.id }) else { return }
        narrativeMemory[idx] = memory
        persistNarrativeMemory()
    }

    func deleteNarrativeMemory(id: UUID) {
        narrativeMemory.removeAll { $0.id == id }
        persistNarrativeMemory()
    }

    func savePerformanceMode(_ mode: PerformanceMode) {
        performanceMode = mode
        guard var project = currentProject, let folder = currentFolder else { return }
        project.settings.performanceMode = mode
        currentProject = project
        persistProject(project, folder: folder)
    }

    func updateOllamaSettings(
        endpoint: String,
        modelName: String,
        llmPassesEnabled: Bool,
        embeddingsEnabled: Bool,
        embeddingModelName: String,
        modelSettings: ModelSettings,
        hadLLMEnabled: Bool = true
    ) {
        guard var project = currentProject, let folder = currentFolder else { return }
        if hadLLMEnabled && !llmPassesEnabled {
            Task { await llmCoordinator.scheduleUnloadIfNeeded(
                settings: project.ollamaSettings,
                policy: .quiet,
                performanceMode: performanceMode
            ) }
        }
        project.ollamaSettings.endpoint = endpoint
        project.ollamaSettings.modelName = modelName
        project.ollamaSettings.llmPassesEnabled = llmPassesEnabled
        project.ollamaSettings.embeddingsEnabled = embeddingsEnabled
        project.ollamaSettings.embeddingModelName = embeddingModelName
        var ms = modelSettings
        if ms.primaryModelName.isEmpty { ms.primaryModelName = modelName }
        project.ollamaSettings.modelSettings = ms
        currentProject = project
        persistProject(project, folder: folder)
        analysisQueue.maxConcurrentLLM = ms.maxConcurrentLLMTasks
        Task { await refreshOllamaStatus() }
        rebuildSemanticIndex(fullRebuild: true)
        statusMessage = "Ollama settings saved"
    }

    private func loadProjectSidecarData(folder: URL) {
        do {
            canonEntities = try canonStore.load(folder: folder)
        } catch {
            reportPersistenceFailure("Canon", error)
            canonEntities = []
        }
        do {
            narrativeMemory = try canonStore.loadMemory(folder: folder)
        } catch {
            reportPersistenceFailure("Narrative memory", error)
            narrativeMemory = []
        }
        do {
            canonSuggestions = try canonSuggestionStore.load(folder: folder)
        } catch {
            reportPersistenceFailure("Canon suggestions", error)
            canonSuggestions = []
        }
        do {
            analysisRuns = try diagnosticsStore.loadAnalysisRuns(folder: folder)
        } catch {
            reportPersistenceFailure("Analysis history", error)
            analysisRuns = []
        }
    }

    private func persistCanon() {
        guard let folder = currentFolder else { return }
        do {
            try canonStore.save(canonEntities, folder: folder)
        } catch {
            reportPersistenceFailure("Canon", error)
        }
    }

    private func persistNarrativeMemory() {
        guard let folder = currentFolder else { return }
        do {
            try canonStore.saveMemory(narrativeMemory, folder: folder)
        } catch {
            reportPersistenceFailure("Narrative memory", error)
        }
    }

    private func persistDiagnostics() {
        guard let document = activeDocument, let folder = currentFolder else { return }
        do {
            try diagnosticsStore.save(diagnostics, documentID: document.id, folder: folder)
        } catch {
            reportPersistenceFailure("Diagnostics", error)
        }
    }

    private func persistProposals() {
        guard let document = activeDocument, let folder = currentFolder else { return }
        do {
            try diagnosticsStore.saveProposals(proposals, documentID: document.id, folder: folder)
        } catch {
            reportPersistenceFailure("Proposals", error)
        }
    }

    private func updateWordCount() {
        guard var project = currentProject, let document = activeDocument else { return }
        project.wordCount = TextUtilities.wordCount(document.plainText)
        project.diagnosticsSummary = summarizeDiagnostics()
        currentProject = project
    }

    private func summarizeDiagnostics() -> DiagnosticsSummary {
        let open = diagnostics.filter { $0.status == .open && !$0.isStale }
        return DiagnosticsSummary(
            blocking: open.filter { $0.severity == .blocking }.count,
            errors: open.filter { $0.severity == .error }.count,
            warnings: open.filter { $0.severity == .warning }.count,
            info: open.filter { $0.severity == .info }.count,
            pendingProposals: proposals.filter { $0.status == .pending }.count
        )
    }

    func scrollToDiagnostic(_ diagnostic: Diagnostic) {
        if let start = diagnostic.startOffset {
            let end = diagnostic.endOffset ?? start
            scrollToRange = NSRange(location: start, length: max(0, end - start))
            return
        }
        if let pid = diagnostic.paragraphID,
           let indexed = documentIndex?.paragraphs.first(where: { $0.paragraph.id == pid }) {
            scrollToRange = NSRange(location: indexed.rangeStart, length: max(0, indexed.rangeEnd - indexed.rangeStart))
        }
    }

    func updateSceneFunction(sceneID: UUID, function: String) {
        guard let idx = structure.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        structure.scenes[idx].function = function
        structure.scenes[idx].updatedAt = Date()
        if let folder = currentFolder, let docID = activeDocument?.id {
            persistStructureBestEffort(documentID: docID, folder: folder)
        }
    }

    func jumpToParagraph(_ paragraphID: UUID) {
        selectedParagraphID = paragraphID
        if let indexed = documentIndex?.paragraphs.first(where: { $0.paragraph.id == paragraphID }) {
            scrollToRange = NSRange(location: indexed.rangeStart, length: 0)
        }
    }

    func rebuildSemanticIndex(fullRebuild: Bool = false) {
        guard let project = currentProject, let document = activeDocument, let index = documentIndex else { return }
        Task {
            let onlyDirty: Set<UUID>? = fullRebuild ? nil : Set(dirtyStates.map(\.paragraphID))
            await semanticIndex.index(
                paragraphs: index.paragraphs.map(\.paragraph),
                settings: project.ollamaSettings,
                health: ollamaHealth,
                onlyParagraphIDs: onlyDirty
            )
            semanticIndexModeLabel = semanticIndex.lastMode
            if let persisted = semanticIndex.persistedIndex(documentID: document.id),
               let folder = currentFolder {
                do {
                    try EmbeddingIndexStore.save(persisted, folder: folder)
                } catch {
                    await MainActor.run {
                        self.reportPersistenceFailure("Semantic index", error)
                    }
                }
            }
        }
    }

    func runSemanticSearch() {
        guard let project = currentProject else { return }
        Task {
            semanticSearchResults = await semanticIndex.search(
                query: semanticSearchQuery,
                limit: 20,
                settings: project.ollamaSettings
            )
            semanticIndexModeLabel = semanticIndex.lastMode
            statusMessage = "\(semanticSearchResults.count) paragraphs matched (\(semanticIndexModeLabel))"
        }
    }

    func updateProject(
        entry: ProjectRegistryEntry,
        name: String,
        subtitle: String,
        newCoverURL: URL? = nil,
        removeCover: Bool = false
    ) {
        do {
            let updated = try projectStore.updateProjectMetadata(
                folder: entry.folderURL,
                projectID: entry.id,
                name: name,
                subtitle: subtitle,
                newCoverURL: newCoverURL,
                removeCover: removeCover
            )
            projects = registry.entries
            if currentProject?.id == entry.id {
                currentProject = updated
                currentFolder = entry.folderURL
            }
            statusMessage = "Updated \(updated.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProject(_ entry: ProjectRegistryEntry) {
        if let doc = activeDocument, currentFolder == entry.folderURL {
            createSafetySnapshot(reason: .beforeDestructiveAction, note: "Before delete project")
            _ = doc
        }
        do {
            try projectStore.deleteProject(folder: entry.folderURL, projectID: entry.id)
            projects = registry.entries
            if currentProject?.id == entry.id {
                currentProject = nil
                currentFolder = nil
                navigation = .library
            }
            statusMessage = "Deleted \(entry.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicateProject(_ entry: ProjectRegistryEntry) {
        do {
            let parent = entry.folderURL.deletingLastPathComponent()
            let copyName = "\(entry.name) Copy"
            let (project, folder) = try projectStore.createProject(
                name: copyName,
                subtitle: entry.subtitle,
                parentFolder: parent
            )
            let fm = FileManager.default
            let subdirs = ["manuscript", "snapshots", "covers", "memory", "diagnostics", "edit-rules", "indexes", "exports"]
            for sub in subdirs {
                let src = entry.folderURL.appendingPathComponent(sub, isDirectory: true)
                let dst = folder.appendingPathComponent(sub, isDirectory: true)
                guard fm.fileExists(atPath: src.path) else { continue }
                if let items = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) {
                    for item in items {
                        let target = dst.appendingPathComponent(item.lastPathComponent)
                        if !fm.fileExists(atPath: target.path) {
                            try? fm.copyItem(at: item, to: target)
                        }
                    }
                }
            }
            var updated = project
            updated.wordCount = entry.wordCount
            if let cover = entry.coverImagePath {
                updated.coverImagePath = cover
            }
            try projectStore.saveProject(updated, folder: folder)
            syncRegistryEntry(ProjectRegistryEntry(
                id: project.id, name: project.name, subtitle: project.subtitle, folderURL: folder,
                coverImagePath: entry.coverImagePath, lastOpened: Date(), lastEdited: Date(),
                wordCount: entry.wordCount, diagnosticsSummary: entry.diagnosticsSummary,
                lastAnalysisStatus: entry.lastAnalysisStatus
            ))
            statusMessage = "Duplicated as \(copyName)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistAnalysisRuns() {
        guard let folder = currentFolder else { return }
        let trimmed = Array(analysisRuns.suffix(50))
        do {
            try diagnosticsStore.saveAnalysisRuns(trimmed, folder: folder)
        } catch {
            reportPersistenceFailure("Analysis history", error)
        }
    }
}

// MARK: - AI Assistant (selection-aware chat)

extension AppState {
    func clearEditorSelectionContext() {
        selectionLength = 0
        documentEditorBridge.selection = .empty
    }

    func sendAIChat(userMessage: String, mode: AiChatInstructionMode) async {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let project = currentProject, let document = activeDocument else {
            errorMessage = "Open a manuscript first."
            return
        }
        guard case .available = ollamaHealth, project.ollamaSettings.llmPassesEnabled else {
            aiChatMessages.append(AiChatMessage(role: .assistant, text: "Ollama is unavailable or LLM passes are disabled. Deterministic tools still work."))
            return
        }

        let userMsg = AiChatMessage(role: .user, text: trimmed)
        aiChatMessages.append(userMsg)
        aiChatIsLoading = true

        let target = documentEditorBridge.buildAiChatTarget(
            documentId: document.id,
            projectId: project.id,
            plainText: document.plainText
        )
        let rulesContext = enabledRuleFiles
            .filter(\.enabled)
            .prefix(6)
            .map { "[\($0.fileName)] \($0.detectedCategory.displayName)" }
            .joined(separator: "\n")
        let request = AiChatRequest(
            projectId: project.id,
            documentId: document.id,
            userMessage: trimmed,
            target: target,
            rulesContext: rulesContext.isEmpty ? nil : rulesContext,
            documentContext: nil,
            selectedText: documentEditorBridge.selection.hasSelection ? documentEditorBridge.selection.selectedText : nil,
            instructionMode: mode
        )
        let prompt = AiChatService().buildPrompt(request: request)

        do {
            let response = try await llmCoordinator.runTextTask(
                task: .rewriteProposal,
                prompt: prompt,
                settings: project.ollamaSettings,
                performanceMode: performanceMode
            )
            let actions = AiChatService().suggestedActions(
                for: mode,
                hasSelection: documentEditorBridge.selection.hasSelection
            )
            aiChatMessages.append(AiChatMessage(role: .assistant, text: response, proposedActions: actions))
        } catch let error as LocalLLMError {
            if case .skipped(let reason) = error {
                aiChatMessages.append(AiChatMessage(role: .assistant, text: reason))
            } else {
                aiChatMessages.append(AiChatMessage(role: .assistant, text: "Request failed: \(error.localizedDescription)"))
            }
        } catch {
            aiChatMessages.append(AiChatMessage(role: .assistant, text: "Request failed: \(error.localizedDescription)"))
        }
        aiChatIsLoading = false
    }

    func applyAIChatAction(_ action: AiChatApplyAction, assistantText: String) {
        guard activeDocument != nil else { return }
        if action == .copyOnly {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(assistantText, forType: .string)
            statusMessage = "Copied to clipboard"
            return
        }

        guard let project = currentProject, let document = activeDocument else { return }
        guard let preview = makeAIChatProposalPreview(
            action: action,
            assistantText: assistantText,
            documentText: document.plainText
        ) else {
            return
        }

        let proposal = ChangeProposalService.makeProposal(
            projectID: project.id,
            documentID: document.id,
            scope: .document,
            scopeID: nil,
            source: .llm,
            title: action.proposalTitle,
            reason: "AI assistant output prepared for manual review. The manuscript is unchanged until you accept this proposal.",
            beforeText: preview.before,
            afterText: preview.after,
            riskLevel: .medium
        )
        proposals.append(proposal)
        openProposalForReview(proposal)
        persistProposals()
        statusMessage = "AI proposal ready for review"
    }

    private func makeAIChatProposalPreview(
        action: AiChatApplyAction,
        assistantText: String,
        documentText: String
    ) -> (before: String, after: String)? {
        documentEditorBridge.refreshSelection()
        guard documentEditorBridge.editorKind == .legacyPrototype else {
            errorMessage = "AI edits require the office editor JS bridge before they can become manuscript proposals. Copy is available now."
            return nil
        }

        switch action {
        case .copyOnly:
            return nil
        case .replaceSelection:
            guard documentEditorBridge.selection.hasSelection else {
                errorMessage = "No text selected."
                return nil
            }
            let start = min(max(documentEditorBridge.selection.location, 0), documentText.count)
            let end = min(start + documentEditorBridge.selection.length, documentText.count)
            var updated = documentText
            let startIdx = updated.index(updated.startIndex, offsetBy: start)
            let endIdx = updated.index(updated.startIndex, offsetBy: end)
            updated.replaceSubrange(startIdx..<endIdx, with: assistantText)
            return (documentText, updated)
        case .insertAtCursor:
            let loc = min(max(documentEditorBridge.selection.location, 0), documentText.count)
            var updated = documentText
            let idx = updated.index(updated.startIndex, offsetBy: loc)
            updated.insert(contentsOf: assistantText, at: idx)
            return (documentText, updated)
        case .appendAfterSelection:
            let loc = min(
                max(documentEditorBridge.selection.location + documentEditorBridge.selection.length, 0),
                documentText.count
            )
            var updated = documentText
            let idx = updated.index(updated.startIndex, offsetBy: loc)
            updated.insert(contentsOf: assistantText, at: idx)
            return (documentText, updated)
        }
    }

    func saveDocumentEditorSettings(serverURL: String, kind: DocumentEditorKind, dockerCLIPath: String? = nil) {
        DocumentEditorSettings.saveServerURL(serverURL)
        DocumentEditorSettings.saveDockerCLIPath(dockerCLIPath)
        DocumentEditorSettings.saveEditorKind(kind, userSelected: true)
        documentEditorBridge.documentServerURL = serverURL
        documentEditorBridge.editorKind = kind
        if kind == .legacyPrototype {
            embeddedOfficeCoordinator.reset()
        } else {
            syncEmbeddedOfficeEditor()
        }
        statusMessage = "Document editor settings saved"
    }

    func syncEmbeddedOfficeEditor() {
        embeddedOfficeCoordinator.sync(
            activeDocument: activeDocument,
            projectFolder: currentFolder,
            serverURL: documentEditorBridge.documentServerURL,
            editorKind: documentEditorBridge.editorKind
        )
        documentEditorBridge.connectionState = embeddedOfficeCoordinator.connectionState
    }

    func retryEmbeddedOfficeEditor() {
        Task {
            if editorStartup != .ready {
                editorStartup = .loading(message: EditorStartupMessage.connecting)
                let result = await ensureDocumentServerRunning(updateStartup: true)
                switch result {
                case .alreadyRunning, .startedManagedContainer:
                    editorStartup = .ready
                case .failure:
                    editorStartup = .unavailable(message: EditorStartupMessage.unavailable)
                }
            }
            embeddedOfficeCoordinator.retryConnection()
            documentEditorBridge.connectionState = embeddedOfficeCoordinator.connectionState
        }
    }

    func startLocalDocumentServer() {
        retryEmbeddedOfficeEditor()
    }

    private func handleONLYOFFICESaveBack(documentID: UUID, result: Result<URL, Error>) async {
        switch result {
        case .failure(let error):
            documentSaveState = .saveError
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = "ONLYOFFICE save failed"
        case .success(let docxURL):
            guard var doc = activeDocument, doc.id == documentID, let folder = currentFolder else { return }
            documentSaveState = .saving
            do {
                _ = try EmbeddedDocumentSaveService.syncDocumentMetadata(document: &doc, savedDocxURL: docxURL)
                activeDocument = doc
                if let index = documents.firstIndex(where: { $0.id == doc.id }) {
                    documents[index] = doc
                }
                try documentStore.save(doc, folder: folder)
                if var project = currentProject {
                    project.wordCount = TextUtilities.wordCount(doc.plainText)
                    currentProject = project
                    try projectStore.saveProject(project, folder: folder)
                }
                documentSaveState = .saved
                statusMessage = "Manuscript saved from ONLYOFFICE"
                bumpEditorContentEpoch()
                reindexDocument()
            } catch {
                documentSaveState = .saveError
                errorMessage = error.localizedDescription
                statusMessage = "Could not sync manuscript after ONLYOFFICE save"
            }
        }
    }

    func switchDocumentEditorToLegacyFallback() {
        saveDocumentEditorSettings(
            serverURL: documentEditorBridge.documentServerURL,
            kind: .legacyPrototype
        )
        statusMessage = "Legacy prototype editor active — not the production path"
    }
}

private extension AiChatApplyAction {
    var proposalTitle: String {
        switch self {
        case .replaceSelection:
            return "AI replace selection"
        case .insertAtCursor:
            return "AI insert at cursor"
        case .appendAfterSelection:
            return "AI append after selection"
        case .copyOnly:
            return "AI copy"
        }
    }
}

extension AppState {
    var registryUnavailable: Bool { registryLoadFailed }

    var registryUnavailableMessage: String? {
        registry.lastLoadError?.localizedDescription ?? errorMessage
    }

    func reportPersistenceFailure(_ context: String, _ error: Error) {
        let message = "\(context): \(error.localizedDescription)"
        errorMessage = message
        statusMessage = "Save failed"
    }

    func syncRegistryEntry(_ entry: ProjectRegistryEntry) {
        do {
            try registry.upsert(entry)
            projects = registry.entries
            registryLoadFailed = false
        } catch {
            reportPersistenceFailure("Project library", error)
        }
    }

    func persistProject(_ project: Project, folder: URL) {
        do {
            try projectStore.saveProject(project, folder: folder)
            projects = registry.entries
        } catch {
            reportPersistenceFailure("Project", error)
        }
    }

    func persistIndexBestEffort(_ index: DocumentIndex, folder: URL) {
        do {
            try documentStore.saveIndex(index, folder: folder)
        } catch {
            // Best-effort during typing/reindex; manuscript JSON autosave is authoritative.
        }
    }

    func persistStructureBestEffort(documentID: UUID, folder: URL) {
        do {
            try documentStore.saveStructure(structure, documentID: documentID, folder: folder)
        } catch {
            // Best-effort structure cache while editing.
        }
    }

    func persistAcceptedBaseline(_ text: String, documentID: UUID, folder: URL) {
        let url = ProjectPaths.acceptedManuscriptURL(folder: folder, documentID: documentID)
        do {
            try AtomicFileWriter.write(text: text, to: url)
        } catch {
            reportPersistenceFailure("Accepted baseline", error)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import Foundation

struct ProjectSettings: Codable, Hashable, Sendable {
    var defaultLanguage: String
    var defaultRuleProfile: String
    var performanceMode: PerformanceMode

    static let `default` = ProjectSettings(
        defaultLanguage: "uk",
        defaultRuleProfile: "default",
        performanceMode: .balanced
    )
}

struct ModelSettings: Codable, Hashable, Sendable {
    var primaryModelName: String
    var utilityModelName: String?
    var embeddingModelName: String
    var allowUtilityModel: Bool
    var allowEmbeddings: Bool
    var maxLoadedLLMModels: Int
    var maxConcurrentLLMTasks: Int
    var keepAlivePolicy: KeepAlivePolicy
    /// User-assigned roles for the primary model (suggestions only).
    var primaryModelRoles: [ModelRole]
    /// Optional per-model role map: `modelName` → roles.
    var roleAssignments: [String: [ModelRole]]

    init(
        primaryModelName: String,
        utilityModelName: String?,
        embeddingModelName: String,
        allowUtilityModel: Bool,
        allowEmbeddings: Bool,
        maxLoadedLLMModels: Int,
        maxConcurrentLLMTasks: Int,
        keepAlivePolicy: KeepAlivePolicy,
        primaryModelRoles: [ModelRole],
        roleAssignments: [String: [ModelRole]]
    ) {
        self.primaryModelName = primaryModelName
        self.utilityModelName = utilityModelName
        self.embeddingModelName = embeddingModelName
        self.allowUtilityModel = allowUtilityModel
        self.allowEmbeddings = allowEmbeddings
        self.maxLoadedLLMModels = maxLoadedLLMModels
        self.maxConcurrentLLMTasks = maxConcurrentLLMTasks
        self.keepAlivePolicy = keepAlivePolicy
        self.primaryModelRoles = primaryModelRoles
        self.roleAssignments = roleAssignments
    }

    static let `default` = ModelSettings(
        primaryModelName: "",
        utilityModelName: nil,
        embeddingModelName: "nomic-embed-text",
        allowUtilityModel: false,
        allowEmbeddings: false,
        maxLoadedLLMModels: 1,
        maxConcurrentLLMTasks: 1,
        keepAlivePolicy: .balanced,
        primaryModelRoles: [.generalReasoning, .proseAnalysis],
        roleAssignments: [:]
    )

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryModelName = try c.decode(String.self, forKey: .primaryModelName)
        utilityModelName = try c.decodeIfPresent(String.self, forKey: .utilityModelName)
        embeddingModelName = try c.decodeIfPresent(String.self, forKey: .embeddingModelName) ?? "nomic-embed-text"
        allowUtilityModel = try c.decodeIfPresent(Bool.self, forKey: .allowUtilityModel) ?? false
        allowEmbeddings = try c.decodeIfPresent(Bool.self, forKey: .allowEmbeddings) ?? false
        maxLoadedLLMModels = try c.decodeIfPresent(Int.self, forKey: .maxLoadedLLMModels) ?? 1
        maxConcurrentLLMTasks = try c.decodeIfPresent(Int.self, forKey: .maxConcurrentLLMTasks) ?? 1
        keepAlivePolicy = try c.decodeIfPresent(KeepAlivePolicy.self, forKey: .keepAlivePolicy) ?? .balanced
        primaryModelRoles = try c.decodeIfPresent([ModelRole].self, forKey: .primaryModelRoles) ?? [.generalReasoning, .proseAnalysis]
        roleAssignments = try c.decodeIfPresent([String: [ModelRole]].self, forKey: .roleAssignments) ?? [:]
    }
}

struct OllamaSettings: Codable, Hashable, Sendable {
    var endpoint: String
    var modelName: String
    var temperature: Double
    var maxTokens: Int
    var timeoutSeconds: Double
    var llmPassesEnabled: Bool
    var embeddingsEnabled: Bool
    var embeddingModelName: String
    var modelSettings: ModelSettings?

    static let `default` = OllamaSettings(
        endpoint: "http://127.0.0.1:11434",
        modelName: "",
        temperature: 0.2,
        maxTokens: 2048,
        timeoutSeconds: 120,
        llmPassesEnabled: true,
        embeddingsEnabled: false,
        embeddingModelName: "nomic-embed-text",
        modelSettings: .default
    )

    var resolvedModelSettings: ModelSettings {
        var s = modelSettings ?? .default
        if s.primaryModelName.isEmpty, !modelName.isEmpty {
            s.primaryModelName = modelName
        }
        if !embeddingsEnabled {
            s.allowEmbeddings = false
        }
        return s
    }

    /// Primary generative model for routing (falls back to legacy `modelName`).
    var effectivePrimaryModel: String {
        let primary = resolvedModelSettings.primaryModelName
        if !primary.isEmpty { return primary }
        return modelName
    }
}

struct DiagnosticsSummary: Codable, Hashable, Sendable {
    var blocking: Int
    var errors: Int
    var warnings: Int
    var info: Int
    var pendingProposals: Int

    static let empty = DiagnosticsSummary(blocking: 0, errors: 0, warnings: 0, info: 0, pendingProposals: 0)
}

struct Project: Identifiable, Hashable, Sendable {
    var schemaVersion: Int
    var id: UUID
    var name: String
    var subtitle: String
    var rootURL: URL?
    var createdAt: Date
    var updatedAt: Date
    var activeDocumentID: UUID?
    var settings: ProjectSettings
    var enabledRuleFileIDs: [UUID]
    var ollamaSettings: OllamaSettings
    var coverImagePath: String?

    var wordCount: Int?
    var diagnosticsSummary: DiagnosticsSummary
    var lastPipelineStatus: String?

    init(
        schemaVersion: Int = PersistenceSchema.project,
        id: UUID,
        name: String,
        subtitle: String,
        rootURL: URL?,
        createdAt: Date,
        updatedAt: Date,
        activeDocumentID: UUID?,
        settings: ProjectSettings,
        enabledRuleFileIDs: [UUID],
        ollamaSettings: OllamaSettings,
        coverImagePath: String?,
        wordCount: Int?,
        diagnosticsSummary: DiagnosticsSummary,
        lastPipelineStatus: String?
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.rootURL = rootURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activeDocumentID = activeDocumentID
        self.settings = settings
        self.enabledRuleFileIDs = enabledRuleFileIDs
        self.ollamaSettings = ollamaSettings
        self.coverImagePath = coverImagePath
        self.wordCount = wordCount
        self.diagnosticsSummary = diagnosticsSummary
        self.lastPipelineStatus = lastPipelineStatus
    }
}

extension Project: Codable {
    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, subtitle, rootURL, createdAt, updatedAt
        case activeDocumentID, settings, enabledRuleFileIDs, ollamaSettings, coverImagePath
        case wordCount, diagnosticsSummary, lastPipelineStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? PersistenceSchema.project
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        subtitle = try c.decode(String.self, forKey: .subtitle)
        rootURL = try c.decodeIfPresent(URL.self, forKey: .rootURL)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        activeDocumentID = try c.decodeIfPresent(UUID.self, forKey: .activeDocumentID)
        settings = try c.decodeIfPresent(ProjectSettings.self, forKey: .settings) ?? .default
        enabledRuleFileIDs = try c.decodeIfPresent([UUID].self, forKey: .enabledRuleFileIDs) ?? []
        ollamaSettings = try c.decodeIfPresent(OllamaSettings.self, forKey: .ollamaSettings) ?? .default
        coverImagePath = try c.decodeIfPresent(String.self, forKey: .coverImagePath)
        wordCount = try c.decodeIfPresent(Int.self, forKey: .wordCount)
        diagnosticsSummary = try c.decodeIfPresent(DiagnosticsSummary.self, forKey: .diagnosticsSummary) ?? .empty
        lastPipelineStatus = try c.decodeIfPresent(String.self, forKey: .lastPipelineStatus)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(rootURL, forKey: .rootURL)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(activeDocumentID, forKey: .activeDocumentID)
        try c.encode(settings, forKey: .settings)
        try c.encode(enabledRuleFileIDs, forKey: .enabledRuleFileIDs)
        try c.encode(ollamaSettings, forKey: .ollamaSettings)
        try c.encodeIfPresent(coverImagePath, forKey: .coverImagePath)
        try c.encodeIfPresent(wordCount, forKey: .wordCount)
        try c.encode(diagnosticsSummary, forKey: .diagnosticsSummary)
        try c.encodeIfPresent(lastPipelineStatus, forKey: .lastPipelineStatus)
    }
}

struct ProjectRegistryEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var subtitle: String
    var folderURL: URL
    var coverImagePath: String?
    var lastOpened: Date?
    var lastEdited: Date?
    var wordCount: Int
    var diagnosticsSummary: DiagnosticsSummary
    var lastAnalysisStatus: String?
}

struct Document: Identifiable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var title: String
    var type: DocumentType
    var plainText: String
    var originalSnapshot: String?
    /// Last explicitly accepted manuscript baseline (after proposal review).
    var acceptedPlainText: String?
    /// Character ranges for bold/italic/headings (DOCX round-trip).
    var formattingSpans: [TextFormattingSpan]?
    /// Primary storage: office `.docx` vs legacy JSON plain-text sidecar.
    var storageKind: DocumentStorageKind
    /// File name under `manuscript/` when `storageKind == .docxPrimary` (default `{id}.docx`).
    var docxFileName: String?
    var createdAt: Date
    var updatedAt: Date
    /// Document schema version for migration-safe decoding.
    var version: Int

    init(
        id: UUID,
        projectID: UUID,
        title: String,
        type: DocumentType,
        plainText: String,
        originalSnapshot: String?,
        acceptedPlainText: String?,
        formattingSpans: [TextFormattingSpan]?,
        storageKind: DocumentStorageKind = .plainTextSidecar,
        docxFileName: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        version: Int = PersistenceSchema.document
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.type = type
        self.plainText = plainText
        self.originalSnapshot = originalSnapshot
        self.acceptedPlainText = acceptedPlainText
        self.formattingSpans = formattingSpans
        self.storageKind = storageKind
        self.docxFileName = docxFileName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }
}

extension Document: Codable {
    enum CodingKeys: String, CodingKey {
        case id, projectID, title, type, plainText, originalSnapshot
        case acceptedPlainText, formattingSpans, storageKind, docxFileName
        case createdAt, updatedAt, version
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectID = try c.decode(UUID.self, forKey: .projectID)
        title = try c.decode(String.self, forKey: .title)
        type = try c.decode(DocumentType.self, forKey: .type)
        plainText = try c.decode(String.self, forKey: .plainText)
        originalSnapshot = try c.decodeIfPresent(String.self, forKey: .originalSnapshot)
        acceptedPlainText = try c.decodeIfPresent(String.self, forKey: .acceptedPlainText)
        formattingSpans = try c.decodeIfPresent([TextFormattingSpan].self, forKey: .formattingSpans)
        storageKind = try c.decodeIfPresent(DocumentStorageKind.self, forKey: .storageKind) ?? .plainTextSidecar
        docxFileName = try c.decodeIfPresent(String.self, forKey: .docxFileName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? PersistenceSchema.document
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(projectID, forKey: .projectID)
        try c.encode(title, forKey: .title)
        try c.encode(type, forKey: .type)
        try c.encode(plainText, forKey: .plainText)
        try c.encodeIfPresent(originalSnapshot, forKey: .originalSnapshot)
        try c.encodeIfPresent(acceptedPlainText, forKey: .acceptedPlainText)
        try c.encodeIfPresent(formattingSpans, forKey: .formattingSpans)
        try c.encode(storageKind, forKey: .storageKind)
        try c.encodeIfPresent(docxFileName, forKey: .docxFileName)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
    }
}

struct Chapter: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var documentID: UUID
    var title: String
    var order: Int
    var summary: String
    var startParagraphID: UUID?
    var endParagraphID: UUID?
    var diagnosticsSummary: DiagnosticsSummary
    var createdAt: Date
    var updatedAt: Date
}

struct Scene: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var chapterID: UUID
    var title: String
    var order: Int
    var summary: String
    var function: String
    var locationID: UUID?
    var timelinePosition: String?
    var povCharacterID: UUID?
    var startParagraphID: UUID?
    var endParagraphID: UUID?
    var diagnosticsSummary: DiagnosticsSummary
    var createdAt: Date
    var updatedAt: Date

    // Scene index metadata
    var boundarySource: SceneBoundarySource
    var confidence: Double
    var indexStatus: SceneRecordStatus
    var preview: String
    var isManualBoundary: Bool
    var wordCount: Int
    var characterCount: Int

    init(
        id: UUID,
        chapterID: UUID,
        title: String,
        order: Int,
        summary: String = "",
        function: String = "",
        locationID: UUID? = nil,
        timelinePosition: String? = nil,
        povCharacterID: UUID? = nil,
        startParagraphID: UUID? = nil,
        endParagraphID: UUID? = nil,
        diagnosticsSummary: DiagnosticsSummary = .empty,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        boundarySource: SceneBoundarySource = .autoDetected,
        confidence: Double = 1,
        indexStatus: SceneRecordStatus = .clean,
        preview: String = "",
        isManualBoundary: Bool = false,
        wordCount: Int = 0,
        characterCount: Int = 0
    ) {
        self.id = id
        self.chapterID = chapterID
        self.title = title
        self.order = order
        self.summary = summary
        self.function = function
        self.locationID = locationID
        self.timelinePosition = timelinePosition
        self.povCharacterID = povCharacterID
        self.startParagraphID = startParagraphID
        self.endParagraphID = endParagraphID
        self.diagnosticsSummary = diagnosticsSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.boundarySource = boundarySource
        self.confidence = confidence
        self.indexStatus = indexStatus
        self.preview = preview
        self.isManualBoundary = isManualBoundary
        self.wordCount = wordCount
        self.characterCount = characterCount
    }

    enum CodingKeys: String, CodingKey {
        case id, chapterID, title, order, summary, function, locationID, timelinePosition
        case povCharacterID, startParagraphID, endParagraphID, diagnosticsSummary, createdAt, updatedAt
        case boundarySource, confidence, indexStatus, preview, isManualBoundary, wordCount, characterCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        chapterID = try c.decode(UUID.self, forKey: .chapterID)
        title = try c.decode(String.self, forKey: .title)
        order = try c.decode(Int.self, forKey: .order)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        function = try c.decodeIfPresent(String.self, forKey: .function) ?? ""
        locationID = try c.decodeIfPresent(UUID.self, forKey: .locationID)
        timelinePosition = try c.decodeIfPresent(String.self, forKey: .timelinePosition)
        povCharacterID = try c.decodeIfPresent(UUID.self, forKey: .povCharacterID)
        startParagraphID = try c.decodeIfPresent(UUID.self, forKey: .startParagraphID)
        endParagraphID = try c.decodeIfPresent(UUID.self, forKey: .endParagraphID)
        diagnosticsSummary = try c.decodeIfPresent(DiagnosticsSummary.self, forKey: .diagnosticsSummary) ?? .empty
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        boundarySource = try c.decodeIfPresent(SceneBoundarySource.self, forKey: .boundarySource) ?? .autoDetected
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 1
        indexStatus = try c.decodeIfPresent(SceneRecordStatus.self, forKey: .indexStatus) ?? .clean
        preview = try c.decodeIfPresent(String.self, forKey: .preview) ?? ""
        isManualBoundary = try c.decodeIfPresent(Bool.self, forKey: .isManualBoundary) ?? false
        wordCount = try c.decodeIfPresent(Int.self, forKey: .wordCount) ?? 0
        characterCount = try c.decodeIfPresent(Int.self, forKey: .characterCount) ?? 0
    }
}

struct Paragraph: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var sceneID: UUID?
    var chapterID: UUID?
    var documentID: UUID
    var order: Int
    var text: String
    var hash: String
    var wordCount: Int
    var sentenceCount: Int
    var lastAnalyzedHash: String?
    var createdAt: Date
    var updatedAt: Date
}

struct MarkdownSection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var heading: String
    var level: Int
    var content: String
}

struct EditRuleFile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var fileName: String
    var path: String
    var rawMarkdown: String
    var parsedSections: [MarkdownSection]
    var detectedCategory: EditRuleCategory
    var priority: Int
    var enabled: Bool
    var loadedAt: Date
}

struct EditRule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var ruleFileID: UUID
    var title: String
    var description: String
    var severity: RuleSeverity
    var scope: RuleScope
    var category: EditRuleCategory
    var sourceFile: String
    var sourceHeading: String
    var detectionMode: DetectionMode
}

struct EditRuleExcerpt: Codable, Hashable, Sendable {
    var fileName: String
    var heading: String
    var content: String
    var category: EditRuleCategory
}

struct Diagnostic: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var documentID: UUID
    var chapterID: UUID?
    var sceneID: UUID?
    var paragraphID: UUID?
    var ruleID: UUID?
    var source: DiagnosticSource
    var severity: RuleSeverity
    var scope: RuleScope
    var title: String
    var message: String
    var evidence: String
    var startOffset: Int?
    var endOffset: Int?
    var suggestedFix: String?
    var fixLevel: FixLevel
    var status: DiagnosticStatus
    var textHashAtCreation: String?
    var scopeHashAtCreation: String?
    var isStale: Bool
    var staleReason: String?
    var createdAt: Date
}

struct CanonEntity: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var type: CanonEntityType
    var name: String
    var aliases: [String]
    var description: String
    var facts: [String]
    var constraints: [String]
    var createdAt: Date
    var updatedAt: Date
}

struct NarrativeMemory: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var scope: MemoryScope
    var scopeID: UUID
    var summary: String
    var openThreads: [String]
    var resolvedThreads: [String]
    var activeObjects: [String]
    var characterStates: [String]
    var atmospherePatterns: [String]
    var timelineNotes: [String]
    var sourceHash: String?
    var updatedAt: Date
}

struct PipelinePassResult: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var mode: PipelinePassMode
    var status: PipelinePassStatus
    var startedAt: Date?
    var finishedAt: Date?
    var diagnosticsCreated: Int
    var proposalsCreated: Int
    var ruleFilesUsed: [String]
    var contextScope: RuleScope?
    var failureReason: String?
    /// Hybrid / deterministic-only passes: mechanical phase outcome.
    var deterministicStatus: PipelinePassStatus?
    /// Hybrid / LLM passes: model phase outcome (nil when pass has no LLM phase).
    var llmStatus: PipelinePassStatus?
}

struct AnalysisRun: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var documentID: UUID
    var scope: RuleScope
    var scopeID: UUID?
    var pipelineID: String
    var status: AnalysisRunStatus
    var startedAt: Date
    var finishedAt: Date?
    var passResults: [PipelinePassResult]
    var createdDiagnosticIDs: [UUID]
    var modelUsed: String?
}

struct TextDiffChunk: Codable, Hashable, Sendable {
    var kind: DiffChunkKind
    var text: String
}

enum DiffChunkKind: String, Codable, Sendable {
    case unchanged, inserted, deleted
}

struct ChangeProposal: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var documentID: UUID
    var scope: RuleScope
    var scopeID: UUID?
    var source: ChangeProposalSource
    var title: String
    var reason: String
    var beforeText: String
    var afterText: String
    var diff: [TextDiffChunk]
    var riskLevel: RiskLevel
    var status: ChangeProposalStatus
    var createdAt: Date
}

struct ContextPacket: Codable, Hashable, Sendable {
    var task: String
    var scope: RuleScope
    var currentText: String
    var previousText: String?
    var nextText: String?
    var sceneSummary: String?
    var previousSceneSummary: String?
    var chapterSummary: String?
    var documentSummary: String?
    var projectMemory: String?
    var relevantEditRules: [EditRuleExcerpt]
    var relevantCanon: [CanonEntity]
    var activeObjects: [String]
    var characterStates: [String]
    var openThreads: [String]
    var existingDiagnostics: [Diagnostic]
}

struct ParagraphDirtyState: Identifiable, Codable, Hashable, Sendable {
    var id: UUID { paragraphID }
    var paragraphID: UUID
    var previousHash: String?
    var currentHash: String
    var changedAt: Date
    var dirtyReasons: [String]
    var affectedScopes: [RuleScope]
}

struct ChapterSplitSuggestion: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var paragraphID: UUID
    var confidence: Double
    var reason: String
    var risk: RiskLevel
    var splitType: SplitSuggestionType
}

struct ManualReviewStatus: Codable, Hashable, Sendable {
    var isReady: Bool
    var blockingIssues: Int
    var errors: Int
    var warnings: Int
    var styleRisks: Int
    var canonRisks: Int
    var logicRisks: Int
    var aiPatternRisks: Int
    var pendingProposals: Int
    /// Human-readable blockers when `isReady` is false.
    var readinessNote: String?
}

struct IndexedParagraph: Identifiable, Codable, Hashable, Sendable {
    var id: UUID { paragraph.id }
    var paragraph: Paragraph
    var rangeStart: Int
    var rangeEnd: Int
}

struct DocumentIndex: Codable, Hashable, Sendable {
    var documentID: UUID
    var paragraphs: [IndexedParagraph]
    var dirtyParagraphStates: [ParagraphDirtyState]?
    var updatedAt: Date
}

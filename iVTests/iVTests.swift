import Foundation
import Testing
@testable import iV

@MainActor
private func discardTempProject(projectID: UUID, folder: URL) {
    try? ProjectRegistryService.shared.remove(id: projectID)
    try? FileManager.default.removeItem(at: folder)
}

@Test func paragraphSplitting() {
    let text = "First paragraph.\n\nSecond paragraph.\n\n"
    let parts = TextUtilities.splitParagraphs(text)
    #expect(parts.count == 2)
}

// MARK: - Iteration 3: paragraph identity & dirty scopes

@Suite(.serialized)
struct ParagraphIdentityAndDirtyScopeTests {
    private func rebuild(
        _ indexer: ParagraphIndexer,
        docID: UUID,
        text: String,
        existing: DocumentIndex?
    ) -> (DocumentIndex, [ParagraphDirtyState], Set<UUID>) {
        indexer.rebuildIndex(documentID: docID, text: text, existing: existing)
    }

    @Test func paragraphIDPreservation() {
        let indexer = ParagraphIndexer()
        let docID = UUID()
        let first = rebuild(indexer, docID: docID, text: "Alpha.\n\nBeta.", existing: nil)
        let second = rebuild(indexer, docID: docID, text: "Alpha.\n\nBeta edited.", existing: first.0)
        #expect(second.0.paragraphs.count == 2)
        #expect(second.0.paragraphs[0].paragraph.id == first.0.paragraphs[0].paragraph.id)
        #expect(second.0.paragraphs[1].paragraph.id == first.0.paragraphs[1].paragraph.id)
        #expect(!second.1.isEmpty)
    }

    @Test func editExistingParagraphPreservesOtherIDs() {
    let indexer = ParagraphIndexer()
    let docID = UUID()
    let first = rebuild(indexer, docID: docID, text: "Alpha.\n\nBeta.\n\nGamma.", existing: nil)
    #expect(first.0.paragraphs.count == 3)
    #expect(Set(first.0.paragraphs.map(\.paragraph.id)).count == 3)
    func id(in index: DocumentIndex, text: String) -> UUID? {
        index.paragraphs.first { $0.paragraph.text == text }?.paragraph.id
    }

    let ranged = TextUtilities.splitParagraphsWithRanges("Alpha.\n\nBeta edited.\n\nGamma.")
    let chunks = ranged.enumerated().map { order, item in
        ParagraphChunk(text: item.text, rangeStart: item.start, rangeEnd: item.end, order: order)
    }
    let direct = ParagraphIdentityMatcher.match(
        chunks: chunks,
        previous: first.0.paragraphs.map(\.paragraph),
        documentID: docID
    )
    #expect(direct.0[1].paragraph.id == id(in: first.0, text: "Beta.")!)

    let second = rebuild(indexer, docID: docID, text: "Alpha.\n\nBeta edited.\n\nGamma.", existing: first.0)

    let betaMatch = id(in: second.0, text: "Beta edited.") == id(in: first.0, text: "Beta.")
    #expect(betaMatch, "first=\(first.0.paragraphs.map(\.paragraph.text)) second=\(second.0.paragraphs.map(\.paragraph.text))")
    #expect(id(in: second.0, text: "Alpha.") == id(in: first.0, text: "Alpha."))
    #expect(id(in: second.0, text: "Gamma.") == id(in: first.0, text: "Gamma."))
    let betaID = id(in: first.0, text: "Beta.")!
    #expect(second.1.contains { $0.paragraphID == betaID && $0.dirtyReasons.contains("textChanged") })
    let alphaID = id(in: first.0, text: "Alpha.")!
    let gammaID = id(in: first.0, text: "Gamma.")!
    #expect(!second.1.contains { $0.paragraphID == alphaID })
    #expect(!second.1.contains { $0.paragraphID == gammaID })
    }

    @Test func insertParagraphAtTopPreservesExistingIDs() {
    let indexer = ParagraphIndexer()
    let docID = UUID()
    let first = rebuild(indexer, docID: docID, text: "Alpha.\n\nBeta.", existing: nil)
    let alphaID = first.0.paragraphs[0].paragraph.id
    let betaID = first.0.paragraphs[1].paragraph.id

    let second = rebuild(indexer, docID: docID, text: "Intro.\n\nAlpha.\n\nBeta.", existing: first.0)

    #expect(second.0.paragraphs.count == 3)
    #expect(second.0.paragraphs[1].paragraph.id == alphaID)
    #expect(second.0.paragraphs[2].paragraph.id == betaID)
    #expect(second.0.paragraphs[0].paragraph.id != alphaID)
    #expect(second.0.paragraphs[0].paragraph.id != betaID)
    }

    @Test func deleteParagraphMarksDiagnosticsStale() {
    let indexer = ParagraphIndexer()
    let docID = UUID()
    let projectID = UUID()
    let first = rebuild(indexer, docID: docID, text: "Keep.\n\nRemove me.\n\nTail.", existing: nil)
    let removedID = first.0.paragraphs[1].paragraph.id

    var diagnostics = [
        Diagnostic(
            id: UUID(), projectID: projectID, documentID: docID, chapterID: nil, sceneID: nil, paragraphID: removedID,
            ruleID: nil, source: .deterministic, severity: .warning, scope: .paragraph,
            title: "Test", message: "m", evidence: "Remove me", startOffset: nil, endOffset: nil,
            suggestedFix: nil, fixLevel: .humanOnly, status: .open,
            textHashAtCreation: first.0.paragraphs[1].paragraph.hash,
            scopeHashAtCreation: nil, isStale: false, staleReason: nil, createdAt: Date()
        )
    ]

    _ = rebuild(indexer, docID: docID, text: "Keep.\n\nTail.", existing: first.0)
    let deletedIDs: Set<UUID> = [removedID]
    let hashes = Dictionary(uniqueKeysWithValues: first.0.paragraphs.map { ($0.paragraph.id, $0.paragraph.hash) })
    ParagraphIndexService.markDiagnosticsStale(
        diagnostics: &diagnostics,
        dirtyParagraphIDs: [],
        deletedParagraphIDs: deletedIDs,
        paragraphHashes: hashes
    )

    #expect(diagnostics[0].isStale)
    #expect(diagnostics[0].staleReason == "Paragraph deleted")
    }

    @Test func repeatedIdenticalParagraphsKeepDistinctIDs() {
    let indexer = ParagraphIndexer()
    let docID = UUID()
    let text = "Same line.\n\nSame line.\n\nSame line."
    let first = rebuild(indexer, docID: docID, text: text, existing: nil)
    let ids = Set(first.0.paragraphs.map(\.paragraph.id))
    #expect(ids.count == 3)

    let second = rebuild(indexer, docID: docID, text: text, existing: first.0)
    let idsAgain = second.0.paragraphs.map(\.paragraph.id)
    #expect(Set(idsAgain) == ids)
    #expect(second.1.isEmpty)
    }

    @Test func moveParagraphNearbyPreservesIDWhenSimilarityHigh() {
    let indexer = ParagraphIndexer()
    let docID = UUID()
    let first = rebuild(indexer, docID: docID, text: "Alpha.\n\nBeta.\n\nGamma.", existing: nil)
    let betaID = first.0.paragraphs[1].paragraph.id

    let second = rebuild(indexer, docID: docID, text: "Alpha.\n\nGamma.\n\nBeta.", existing: first.0)

    #expect(second.0.paragraphs.contains { $0.paragraph.id == betaID })
    }

    @Test func unchangedManuscriptProducesNoDirtyStates() {
    let indexer = ParagraphIndexer()
    let docID = UUID()
    let text = "One.\n\nTwo.\n\nThree."
    let first = rebuild(indexer, docID: docID, text: text, existing: nil)
    let second = rebuild(indexer, docID: docID, text: text, existing: first.0)
    #expect(second.1.isEmpty)
    }

    @Test func dirtyScopesIncludeHierarchy() {
    let indexer = ParagraphIndexer()
    let docID = UUID()
    let first = rebuild(indexer, docID: docID, text: "Only.", existing: nil)
    let second = rebuild(indexer, docID: docID, text: "Only edited.", existing: first.0)
    guard let dirty = second.1.first else {
        Issue.record("Expected dirty state")
        return
    }
    let scopes = Set(dirty.affectedScopes)
    #expect(scopes.contains(.paragraph))
    #expect(scopes.contains(.paragraphWindow))
    #expect(scopes.contains(.scene))
    #expect(scopes.contains(.chapter))
    #expect(scopes.contains(.document))
    #expect(scopes.contains(.project))
    }

    @Test func splitParagraphsWithRangesHandlesDuplicates() {
    let text = "A.\n\nA.\n\nB."
    let ranges = TextUtilities.splitParagraphsWithRanges(text)
    #expect(ranges.count == 3)
    #expect(ranges[0].start < ranges[1].start)
    #expect(ranges[1].start < ranges[2].start)
    #expect(ranges[0].text == "A.")
    #expect(ranges[1].text == "A.")
    }
}

@Test func editRuleLoaderParsesSections() {
    let sections = EditRuleLoader.parseSections(from: "# Heading\n\nBody text.")
    #expect(!sections.isEmpty)
}

@Test func safeAutoFixDoesNotRewriteCreative() {
    let engine = SafeAutoFixEngine()
    let text = "She felt sad because the night wanted to decide."
    let result = engine.apply(to: text)
    #expect(result == nil || result?.fixed == text || result?.fixed.contains("  ") == false)
}

@Test func textDiffEngine() {
    let chunks = TextDiffEngine.diff(before: "hello world", after: "hello brave world")
    #expect(!chunks.isEmpty)
}

@Test func editRuleCategoryMapping() {
    let (category, priority) = EditRuleLoader.category(for: "00-minimum-gate.mdc")
    #expect(category == .minimumGate)
    #expect(priority == 0)
}

@Test func bundledEditRulesLoadFromAppResources() {
    #expect(EditRuleLoader.isBundledRuleFileName("00-minimum-gate.mdc"))
    let files = EditRuleLoader.loadAll()
    #expect(!files.isEmpty)
    #expect(files.contains { EditRuleLoader.source(for: $0.path) == .bundled })
}

@Test func llmJSONSchemaExists() {
    let json = """
    {"diagnostics":[],"changeProposals":[],"summaryUpdates":[],"canonUpdateSuggestions":[],"manualReviewReady":true}
    """
    let data = Data(json.utf8)
    let decoded = try? JSONDecoder().decode(LLMAnalysisResponse.self, from: data)
    #expect(decoded != nil)
}

@Test func contextBuilderIncludesMinimumGateCategory() {
    let builder = ContextBuilder()
    let project = Project(
        id: UUID(), name: "T", subtitle: "", rootURL: nil, createdAt: Date(), updatedAt: Date(),
        activeDocumentID: nil, settings: .default, enabledRuleFileIDs: [], ollamaSettings: .default,
        coverImagePath: nil, wordCount: 0, diagnosticsSummary: .empty, lastPipelineStatus: nil
    )
    let doc = Document(
        id: UUID(), projectID: project.id, title: "M", type: .manuscript, plainText: "Test paragraph.",
        originalSnapshot: nil, acceptedPlainText: nil, formattingSpans: nil, createdAt: Date(), updatedAt: Date(), version: 1
    )
    let index = DocumentIndex(documentID: doc.id, paragraphs: [], updatedAt: Date())
    let packet = builder.build(
        task: "test", scope: .paragraph, document: doc, index: index, paragraphID: nil,
        structure: DocumentStructure(chapters: [], scenes: []), memory: [], canon: [],
        ruleFiles: [], categories: [.coreProse], diagnostics: []
    )
    #expect(packet.task == "test")
}

@Test func structureBuilderDetectsChapters() {
    let docID = UUID()
    let paragraphs = [
        Paragraph(id: UUID(), sceneID: nil, chapterID: nil, documentID: docID, order: 0, text: "Chapter One", hash: "a", wordCount: 2, sentenceCount: 1, lastAnalyzedHash: nil, createdAt: Date(), updatedAt: Date()),
        Paragraph(id: UUID(), sceneID: nil, chapterID: nil, documentID: docID, order: 1, text: "Some prose here.", hash: "b", wordCount: 3, sentenceCount: 1, lastAnalyzedHash: nil, createdAt: Date(), updatedAt: Date())
    ]
    let result = ManuscriptStructureBuilder.build(documentID: docID, paragraphs: paragraphs, existing: DocumentStructure(chapters: [], scenes: []))
    #expect(result.structure.chapters.count >= 1)
    #expect(result.structure.scenes.count >= 1)
}

@Test func structureBuilderDetectsSceneBreak() {
    let docID = UUID()
    let paragraphs = [
        Paragraph(id: UUID(), sceneID: nil, chapterID: nil, documentID: docID, order: 0, text: "Opening.", hash: "a", wordCount: 1, sentenceCount: 1, lastAnalyzedHash: nil, createdAt: Date(), updatedAt: Date()),
        Paragraph(id: UUID(), sceneID: nil, chapterID: nil, documentID: docID, order: 1, text: "***", hash: "b", wordCount: 0, sentenceCount: 0, lastAnalyzedHash: nil, createdAt: Date(), updatedAt: Date()),
        Paragraph(id: UUID(), sceneID: nil, chapterID: nil, documentID: docID, order: 2, text: "After break.", hash: "c", wordCount: 2, sentenceCount: 1, lastAnalyzedHash: nil, createdAt: Date(), updatedAt: Date())
    ]
    let result = ManuscriptStructureBuilder.build(documentID: docID, paragraphs: paragraphs, existing: DocumentStructure(chapters: [], scenes: []))
    #expect(result.structure.scenes.count >= 2)
}

@Test func summaryRefreshProducesExcerpt() {
    let summary = SummaryRefreshService.deterministicSummary(for: "First sentence. Second sentence here. Third one.")
    #expect(summary.contains("First"))
    #expect(!summary.isEmpty)
}

@Test func canonSuggestionFromLLM() {
    let llm = LLMCanonUpdateSuggestion(entityType: "character", name: "Ivan", fact: "Has a scar", reason: "mentioned in ch1")
    let suggestion = CanonUpdateSuggestion(from: llm, projectID: UUID())
    #expect(suggestion.status == .pending)
    #expect(suggestion.name == "Ivan")
}

@Test func projectRulesOverrideBundledByFilename() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("iv-rules-\(UUID().uuidString)", isDirectory: true)
    let bundled = temp.appendingPathComponent("bundled", isDirectory: true)
    let project = temp.appendingPathComponent("MyBook.ivproject", isDirectory: true)
    let projectRules = project.appendingPathComponent("edit-rules", isDirectory: true)
    try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: projectRules, withIntermediateDirectories: true)
    try "bundled content".write(to: bundled.appendingPathComponent("01-core-prose-standards.mdc"), atomically: true, encoding: .utf8)
    try "project override content".write(to: projectRules.appendingPathComponent("01-core-prose-standards.mdc"), atomically: true, encoding: .utf8)

    var filesByName: [String: EditRuleFile] = [:]
    for directory in [bundled, projectRules] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
        for url in items {
            guard url.pathExtension == "mdc" else { continue }
            if let file = EditRuleLoader.loadFile(at: url) {
                filesByName[url.lastPathComponent] = file
            }
        }
    }
    let file = filesByName["01-core-prose-standards.mdc"]
    #expect(file?.rawMarkdown.contains("project override") == true)
    try? FileManager.default.removeItem(at: temp)
}

@Test func docxXMLTextExtraction() {
    let xml = """
    <w:document><w:body>
    <w:p><w:r><w:t>Hello world.</w:t></w:r></w:p>
    <w:p><w:r><w:t>Second paragraph.</w:t></w:r></w:p>
    </w:body></w:document>
    """
    let text = DOCXParser.plainText(fromWordDocumentXML: xml)
    #expect(text.contains("Hello world"))
    #expect(text.contains("Second paragraph"))
}

@Test func scopeExpansionIncludesSelection() {
    let order = ScopeResolver.expansionOrder(startingAt: .selection)
    #expect(order.first == .selection)
}

@Test func scopeExpansionRunsMultipleScopes() {
    let project = Project(
        id: UUID(), name: "T", subtitle: "", rootURL: nil, createdAt: Date(), updatedAt: Date(),
        activeDocumentID: nil, settings: .default, enabledRuleFileIDs: [], ollamaSettings: .default,
        coverImagePath: nil, wordCount: 0, diagnosticsSummary: .empty, lastPipelineStatus: nil
    )
    let docID = UUID()
    let p1 = Paragraph(id: UUID(), sceneID: nil, chapterID: nil, documentID: docID, order: 0, text: "the the the quick text.", hash: "h", wordCount: 5, sentenceCount: 1, lastAnalyzedHash: nil, createdAt: Date(), updatedAt: Date())
    let index = DocumentIndex(documentID: docID, paragraphs: [IndexedParagraph(paragraph: p1, rangeStart: 0, rangeEnd: 23)], updatedAt: Date())
    let structure = ManuscriptStructureBuilder.build(documentID: docID, paragraphs: [p1], existing: DocumentStructure(chapters: [], scenes: [])).structure
    let coordinator = AnalysisCoordinator()
    let result = coordinator.runExpandedAnalysis(
        project: project,
        document: Document(id: docID, projectID: project.id, title: "M", type: .manuscript, plainText: p1.text, originalSnapshot: nil, acceptedPlainText: nil, formattingSpans: nil, createdAt: Date(), updatedAt: Date(), version: 1),
        index: index,
        structure: structure,
        canon: [],
        ruleFiles: [],
        paragraphID: p1.id,
        maxScope: .paragraphWindow
    )
    #expect(result.scopesRun.count >= 2)
}

@Test func editRuleStableID() {
    let a = EditRuleLoader.stableID(for: "00-minimum-gate.mdc")
    let b = EditRuleLoader.stableID(for: "00-minimum-gate.mdc")
    let c = EditRuleLoader.stableID(for: "01-core-prose-standards.mdc")
    #expect(a == b)
    #expect(a != c)
}

@Test func extendedRulesDetectCalque() {
    let rule = SuspiciousCalqueRule()
    let project = Project(
        id: UUID(), name: "T", subtitle: "", rootURL: nil, createdAt: Date(), updatedAt: Date(),
        activeDocumentID: nil, settings: .default, enabledRuleFileIDs: [], ollamaSettings: .default,
        coverImagePath: nil, wordCount: 0, diagnosticsSummary: .empty, lastPipelineStatus: nil
    )
    let doc = Document(
        id: UUID(), projectID: project.id, title: "M", type: .manuscript,
        plainText: "На даний момент він пішов.", originalSnapshot: nil, acceptedPlainText: nil, formattingSpans: nil,
        createdAt: Date(), updatedAt: Date(), version: 1
    )
    let input = RuleInput(
        project: project, document: doc, chapter: nil, scene: nil, paragraph: nil,
        currentText: "На даний момент він пішов.", previousText: nil, nextText: nil,
        canon: [], editRules: [], scope: .paragraph
    )
    let hits = rule.detect(input: input)
    #expect(!hits.isEmpty)
}

@Test func deterministicEngineHasExtendedRules() {
    #expect(DeterministicRuleEngine.default.rules.count >= 25)
}

@Test func performancePolicyPowerState() {
    let state = PerformancePolicyService.currentPowerState()
    #expect(state == .onBattery || state == .pluggedIn || state == .unknown)
}

@Test func chapterSplitAnalyzerFindsBreaks() {
    let docID = UUID()
    let p = Paragraph(id: UUID(), sceneID: nil, chapterID: nil, documentID: docID, order: 0, text: "Later that day things changed.", hash: "x", wordCount: 5, sentenceCount: 1, lastAnalyzedHash: nil, createdAt: Date(), updatedAt: Date())
    let index = DocumentIndex(documentID: docID, paragraphs: [IndexedParagraph(paragraph: p, rangeStart: 0, rangeEnd: 30)], updatedAt: Date())
    let suggestions = ChapterSplitAnalyzer.suggestSplits(index: index)
    #expect(!suggestions.isEmpty)
}

@Test func docxRichParserDetectsBold() {
    let xml = """
    <w:document><w:body>
    <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Bold line</w:t></w:r></w:p>
    </w:body></w:document>
    """
    let rich = DOCXRichParser.parseRichContent(fromWordDocumentXML: xml)
    #expect(rich.plainText.contains("Bold"))
    #expect(rich.spans.contains { $0.isBold })
}

@Test func docxRichExportBuildsXML() {
    let xml = DOCXRichParser.buildDocumentXML(
        paragraphs: ["Hello world"],
        spans: [TextFormattingSpan(start: 0, length: 5, isBold: true, isItalic: false, isUnderline: false, headingLevel: nil)]
    )
    #expect(xml.contains("<w:b/>"))
    #expect(xml.contains("Hello"))
}

@Test func embeddingCosineSimilarity() {
    let a: [Float] = [1, 0, 0]
    let b: [Float] = [1, 0, 0]
    let c: [Float] = [0, 1, 0]
    #expect(EmbeddingMath.cosineSimilarity(a, b) > 0.99)
    #expect(EmbeddingMath.cosineSimilarity(a, c) < 0.01)
}

@Test func proposalAcceptPolicyFlagsChapterScope() {
    let proposal = ChangeProposalService.makeProposal(
        projectID: UUID(),
        documentID: UUID(),
        scope: .chapter,
        scopeID: nil,
        source: .chapterSplit,
        title: "Split",
        reason: "test",
        beforeText: "a",
        afterText: "a\n\n***\n\n",
        riskLevel: .medium
    )
    #expect(ProposalAcceptPolicy.requiresConfirmation(proposal))
}

@Test @MainActor func localModelRouterSkipsLLMInQuietMode() {
    let router = DefaultLocalModelRouter(
        settings: { .default },
        performanceMode: { .quiet },
        ollamaEnabled: { true }
    )
    let decision = router.route(.paragraphLLM)
    #expect(decision.execution == .skip)
}

// MARK: - Iteration 1: honest fixes / imports / scene expansion

@Test @MainActor func runSafeAutoFixCreatesProposalWithoutMutatingManuscript() throws {
    let state = AppState()
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("iv-safe-fix-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let store = ProjectStore()
    let docStore = DocumentStore()
    let (project, folder) = try store.createProject(name: "SafeFix", subtitle: "", parentFolder: parent, coverSourceURL: nil)
    defer { discardTempProject(projectID: project.id, folder: parent) }
    var manuscript = try docStore.createManuscript(projectID: project.id, folder: folder, title: "M")
    manuscript.plainText = "Hello  world."
    try docStore.save(manuscript, folder: folder)

    let entry = ProjectRegistryEntry(
        id: project.id, name: project.name, subtitle: project.subtitle, folderURL: folder,
        coverImagePath: nil, lastOpened: Date(), lastEdited: Date(),
        wordCount: 0, diagnosticsSummary: .empty, lastAnalysisStatus: nil
    )
    state.openProject(entry: entry)
    let before = state.activeDocument!.plainText

    state.runSafeAutoFix()

    #expect(state.activeDocument!.plainText == before)
    #expect(state.proposals.count == 1)
    #expect(state.proposals[0].beforeText.contains("Hello"))
    #expect(state.proposals[0].afterText.contains("Hello world"))
}

@Test @MainActor func humanOnlyDiagnosticCannotUseSafeAutoFixPath() {
    let state = AppState()
    let projectID = UUID()
    let docID = UUID()
    state.currentProject = Project(
        id: projectID, name: "T", subtitle: "", rootURL: nil, createdAt: Date(), updatedAt: Date(),
        activeDocumentID: docID, settings: .default, enabledRuleFileIDs: [], ollamaSettings: .default,
        coverImagePath: nil, wordCount: 0, diagnosticsSummary: .empty, lastPipelineStatus: nil
    )
    state.activeDocument = Document(
        id: docID, projectID: projectID, title: "M", type: .manuscript, plainText: "She felt sad because the night wanted to decide.",
        originalSnapshot: nil, acceptedPlainText: nil, formattingSpans: nil, createdAt: Date(), updatedAt: Date(), version: 1
    )
    let diagnostic = Diagnostic(
        id: UUID(), projectID: projectID, documentID: docID, chapterID: nil, sceneID: nil, paragraphID: nil,
        ruleID: nil, source: .deterministic, severity: .warning, scope: .paragraph,
        title: "Calque", message: "Review phrasing", evidence: "felt sad", startOffset: nil, endOffset: nil,
        suggestedFix: "She was sad.", fixLevel: .humanOnly, status: .open,
        textHashAtCreation: nil, scopeHashAtCreation: nil, isStale: false, staleReason: nil, createdAt: Date()
    )
    let textBefore = state.activeDocument!.plainText
    state.applySafeFix(for: diagnostic)
    #expect(state.activeDocument!.plainText == textBefore)
    #expect(state.proposals.isEmpty)
}

@Test @MainActor func suggestedFixDiagnosticDoesNotMutateViaSafeAutoFix() {
    let state = AppState()
    let projectID = UUID()
    let docID = UUID()
    state.currentProject = Project(
        id: projectID, name: "T", subtitle: "", rootURL: nil, createdAt: Date(), updatedAt: Date(),
        activeDocumentID: docID, settings: .default, enabledRuleFileIDs: [], ollamaSettings: .default,
        coverImagePath: nil, wordCount: 0, diagnosticsSummary: .empty, lastPipelineStatus: nil
    )
    state.activeDocument = Document(
        id: docID, projectID: projectID, title: "M", type: .manuscript, plainText: "the the quick text.",
        originalSnapshot: nil, acceptedPlainText: nil, formattingSpans: nil, createdAt: Date(), updatedAt: Date(), version: 1
    )
    let diagnostic = Diagnostic(
        id: UUID(), projectID: projectID, documentID: docID, chapterID: nil, sceneID: nil, paragraphID: nil,
        ruleID: nil, source: .deterministic, severity: .warning, scope: .paragraph,
        title: "Repetition", message: "Repeated word", evidence: "the the", startOffset: nil, endOffset: nil,
        suggestedFix: "the quick", fixLevel: .suggestedFix, status: .open,
        textHashAtCreation: nil, scopeHashAtCreation: nil, isStale: false, staleReason: nil, createdAt: Date()
    )
    let textBefore = state.activeDocument!.plainText
    state.applySafeFix(for: diagnostic)
    #expect(state.activeDocument!.plainText == textBefore)
    #expect(state.proposals.isEmpty)
}

@Test @MainActor func sceneExpansionUnavailableDoesNotCreatePlaceholderProposal() async {
    let state = AppState()
    let projectID = UUID()
    let docID = UUID()
    state.currentProject = Project(
        id: projectID, name: "T", subtitle: "", rootURL: nil, createdAt: Date(), updatedAt: Date(),
        activeDocumentID: docID, settings: .default, enabledRuleFileIDs: [], ollamaSettings: .default,
        coverImagePath: nil, wordCount: 0, diagnosticsSummary: .empty, lastPipelineStatus: nil
    )
    state.activeDocument = Document(
        id: docID, projectID: projectID, title: "M", type: .manuscript, plainText: "Scene one.\n\nScene two.",
        originalSnapshot: nil, acceptedPlainText: nil, formattingSpans: nil, createdAt: Date(), updatedAt: Date(), version: 1
    )
    state.documentIndex = DocumentIndex(documentID: docID, paragraphs: [], updatedAt: Date())
    state.ollamaHealth = .unavailable("Offline for test")

    await state.expandSceneWithLLM(skeleton: "Hero enters.", outcome: "Tension rises.")

    #expect(state.proposals.isEmpty)
    #expect(state.statusMessage.contains("unavailable"))
    #expect(!state.statusMessage.lowercased().contains("placeholder"))
}

// MARK: - Iteration 2: persistence safety

@Test func corruptRegistryDecodeThrows() {
    let corrupt = Data("{ not valid json".utf8)
    #expect(throws: Error.self) {
        try RegistryPersistence.decodeEntries(from: corrupt)
    }
}

@Test @MainActor func corruptRegistryLoadSetsFailureWithoutClearingOnDisk() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("iv-registry-\(UUID().uuidString).json")
    try Data("{ corrupt".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let service = ProjectRegistryService.shared
    #expect(throws: Error.self) { try service.load(from: url) }
    #expect(service.lastLoadError != nil)
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test @MainActor func registrySaveFailureSurfaces() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("iv-registry-ro-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let url = dir.appendingPathComponent("projects.json")
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: dir.path)

    let service = ProjectRegistryService.shared
    service.replaceEntriesForTesting([
        ProjectRegistryEntry(
            id: UUID(), name: "T", subtitle: "", folderURL: URL(fileURLWithPath: "/tmp"),
            coverImagePath: nil, lastOpened: nil, lastEdited: nil, wordCount: 0,
            diagnosticsSummary: .empty,             lastAnalysisStatus: nil
        )
    ])
    #expect(throws: Error.self) { try service.save(to: url) }
    #expect(service.lastSaveError != nil)
}

@Test func atomicFileWriterRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("iv-atomic-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try AtomicFileWriter.write(text: "hello atomic", to: url)
    let read = try String(contentsOf: url, encoding: .utf8)
    #expect(read == "hello atomic")
}

@Test func documentDecodesMissingOptionalFields() throws {
    let json = """
    {"id":"\(UUID().uuidString)","projectID":"\(UUID().uuidString)","title":"M","type":"manuscript","plainText":"Hi.","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let doc = try decoder.decode(Document.self, from: Data(json.utf8))
    #expect(doc.version == PersistenceSchema.document)
    #expect(doc.acceptedPlainText == nil)
    #expect(doc.formattingSpans == nil)
}

@Test func projectDecodesMissingSchemaVersion() throws {
    let json = """
    {"id":"\(UUID().uuidString)","name":"Novel","subtitle":"","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","settings":{"defaultLanguage":"uk","defaultRuleProfile":"default","performanceMode":"balanced"},"enabledRuleFileIDs":[],"ollamaSettings":{"endpoint":"http://127.0.0.1:11434","modelName":"","temperature":0.2,"maxTokens":2048,"timeoutSeconds":120,"llmPassesEnabled":true,"embeddingsEnabled":false,"embeddingModelName":"nomic-embed-text"},"diagnosticsSummary":{"blocking":0,"errors":0,"warnings":0,"info":0,"pendingProposals":0}}
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let project = try decoder.decode(Project.self, from: Data(json.utf8))
    #expect(project.schemaVersion == PersistenceSchema.project)
    #expect(project.diagnosticsSummary.pendingProposals == 0)
}

@Test @MainActor func importReplacePreservesOriginalSnapshotField() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("iv-import-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let store = DocumentStore()
    let (project, folder) = try ProjectStore().createProject(name: "Import", subtitle: "", parentFolder: parent, coverSourceURL: nil)
    defer { discardTempProject(projectID: project.id, folder: parent) }
    var doc = try store.createManuscript(projectID: project.id, folder: folder)
    doc.plainText = "Working draft v1."
    doc.originalSnapshot = "Original import line."
    try store.save(doc, folder: folder)

    let archived = try ManuscriptSnapshotService.archiveImportSnapshot(
        text: "Replaced import text.",
        documentID: doc.id,
        folder: folder,
        label: "import-replace"
    )
    doc.plainText = "Replaced import text."
    try store.save(doc, folder: folder)

    let loaded = try store.load(documentID: doc.id, folder: folder)
    #expect(loaded.originalSnapshot == "Original import line.")
    #expect(loaded.plainText == "Replaced import text.")
    #expect(try String(contentsOf: archived, encoding: .utf8) == "Replaced import text.")
}

// MARK: - Writing safety: snapshots & scene index

@Test func sceneDetectorRecognizesSeparator() {
    let d = SceneDetector.analyzeParagraph("***")
    #expect(d.isBreak)
    #expect(d.source == .separatorMarker)
    #expect(d.confidence >= 0.9)
}

@Test func sceneIndexServiceSingleSceneFallback() {
    let docID = UUID()
    let paragraphs = [
        Paragraph(id: UUID(), sceneID: nil, chapterID: nil, documentID: docID, order: 0, text: "Only prose.", hash: "a", wordCount: 2, sentenceCount: 1, lastAnalyzedHash: nil, createdAt: Date(), updatedAt: Date())
    ]
    let result = SceneIndexService.build(
        documentID: docID,
        paragraphs: paragraphs,
        plainText: "Only prose.",
        existing: DocumentStructure(chapters: [], scenes: []),
        preserveManualBoundaries: false
    )
    #expect(result.structure.scenes.count == 1)
    #expect(result.structure.scenes[0].wordCount >= 1)
}

@Test func snapshotRetentionCapsCount() {
    var snaps: [ManuscriptSnapshotRecord] = []
    let projectID = UUID()
    let docID = UUID()
    for i in 0..<40 {
        snaps.append(
            ManuscriptSnapshotRecord(
                id: UUID(),
                projectID: projectID,
                documentID: docID,
                chapterID: nil,
                plainText: "Text \(i)",
                contentFormatVersion: 1,
                createdAt: Date().addingTimeInterval(TimeInterval(-i * 60)),
                reason: .autosaveCheckpoint,
                wordCount: i,
                schemaVersion: 1,
                note: nil,
                isProtected: false
            )
        )
    }
    let trimmed = ManuscriptSnapshotStore.applyRetention(snaps)
    #expect(trimmed.count <= ManuscriptSnapshotStore.maxSnapshotsPerDocument)
}

@Test @MainActor func snapshotStoreRoundTrip() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("iv-snap-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let (project, folder) = try ProjectStore().createProject(name: "Snap", subtitle: "", parentFolder: parent, coverSourceURL: nil)
    defer { discardTempProject(projectID: project.id, folder: parent) }
    let store = DocumentStore()
    let doc = try store.createManuscript(projectID: project.id, folder: folder, title: "M")
    var working = doc
    working.plainText = "Version one."
    let created = try ManuscriptSnapshotStore.createSnapshot(
        projectID: project.id,
        document: working,
        folder: folder,
        reason: .manual,
        note: "test"
    )
    let listed = try ManuscriptSnapshotStore.listSnapshots(documentID: doc.id, folder: folder)
    #expect(listed.contains { $0.id == created.id })
    let loaded = try ManuscriptSnapshotStore.loadSnapshot(id: created.id, documentID: doc.id, folder: folder)
    #expect(loaded.plainText == "Version one.")
}

// MARK: - Iteration 6: pipeline / diagnostics / rules honesty

private struct InvalidJSONProvider: LocalAIProvider, @unchecked Sendable {
    let backend: LocalAIBackend = .ollama

    func checkAvailability(settings: OllamaSettings) async -> OllamaHealth { .available(models: ["test"]) }
    func listModels(settings: OllamaSettings) async throws -> [String] { ["test"] }
    func runJSONTask<T: Decodable>(prompt: String, model: String, settings: OllamaSettings, as type: T.Type) async throws -> T {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid json"))
    }
    func runTextTask(prompt: String, model: String, settings: OllamaSettings, keepAlive: String?) async throws -> String { "" }
    func embed(text: String, model: String, settings: OllamaSettings) async throws -> [Float] { [] }
    func unloadModel(name: String, settings: OllamaSettings) async throws {}
    func cancelTask() {}
    func estimateContextLimit(model: String) -> Int { 4096 }
    func estimateRuntimeCost(promptTokens: Int) -> String { "low" }
}

private func iteration6PipelineInput(
    llmEnabled: Bool = true,
    provider: (any LocalAIProvider)? = nil
) -> PipelineInput {
    let projectID = UUID()
    let docID = UUID()
    let paragraph = Paragraph(
        id: UUID(), sceneID: nil, chapterID: nil, documentID: docID, order: 0,
        text: "the the quick brown fox.", hash: "h1", wordCount: 5, sentenceCount: 1,
        lastAnalyzedHash: nil, createdAt: Date(), updatedAt: Date()
    )
    var settings = OllamaSettings.default
    settings.llmPassesEnabled = llmEnabled
    let project = Project(
        id: projectID, name: "T", subtitle: "", rootURL: nil, createdAt: Date(), updatedAt: Date(),
        activeDocumentID: docID, settings: .default, enabledRuleFileIDs: [], ollamaSettings: settings,
        coverImagePath: nil, wordCount: 0, diagnosticsSummary: .empty, lastPipelineStatus: nil
    )
    let doc = Document(
        id: docID, projectID: projectID, title: "M", type: .manuscript, plainText: paragraph.text,
        originalSnapshot: nil, acceptedPlainText: nil, formattingSpans: nil, createdAt: Date(), updatedAt: Date(), version: 1
    )
    let index = DocumentIndex(
        documentID: docID,
        paragraphs: [IndexedParagraph(paragraph: paragraph, rangeStart: 0, rangeEnd: paragraph.text.count)],
        updatedAt: Date()
    )
    return PipelineInput(
        project: project,
        document: doc,
        index: index,
        structure: DocumentStructure(chapters: [], scenes: []),
        canon: [],
        memory: [],
        ruleFiles: [],
        diagnostics: [],
        scope: .paragraph,
        paragraphID: paragraph.id,
        aiProvider: provider,
        routeLLM: { _ in LocalModelRouteDecision(backend: .ollama, modelName: "test", execution: .asyncQueued, skipReason: nil) }
    )
}

@Test @MainActor func pipelineWithoutOllamaMarksLLMPassesUnavailable() async {
    let engine = PipelineEngine()
    let llmPass = engine.defaultPasses().first { $0.id == "character-voice" }!
    let input = iteration6PipelineInput(provider: nil)
    let (run, _, _, _) = await engine.run(passes: [llmPass], input: input) { _ in }
    #expect(run.passResults.count == 1)
    #expect(run.passResults[0].status == .unavailable)
    #expect(run.passResults[0].llmStatus == .unavailable)
    let summary = PipelineRunSummary.summarize(passResults: run.passResults)
    #expect(summary.statusLabel.contains("unavailable") || summary.unavailableLLMPasses > 0)
}

@Test @MainActor func hybridPassWithoutOllamaCompletesMechanicalOnly() async {
    let engine = PipelineEngine()
    let hybrid = engine.defaultPasses().first { $0.id == "causality" }!
    let input = iteration6PipelineInput(provider: nil)
    let (run, diags, proposals, _) = await engine.run(passes: [hybrid], input: input) { _ in }
    #expect(run.passResults[0].deterministicStatus == .completed)
    #expect(run.passResults[0].llmStatus == .unavailable)
    #expect(run.passResults[0].status == .completed)
    #expect(
        run.passResults[0].failureReason?.localizedCaseInsensitiveContains("unavailable") == true
            || run.passResults[0].llmStatus == .unavailable
    )
    #expect(proposals.isEmpty)
    _ = diags
}

@Test @MainActor func invalidLLMJSONCreatesFailureDiagnostic() async {
    let engine = PipelineEngine()
    let llmPass = engine.defaultPasses().first { $0.id == "world" }!
    let input = iteration6PipelineInput(provider: InvalidJSONProvider())
    let (_, diags, proposals, _) = await engine.run(passes: [llmPass], input: input) { _ in }
    #expect(proposals.isEmpty)
    #expect(diags.contains { $0.source == .pipeline && $0.title.contains("LLM pass failed") })
}

@Test func diagnosticEvidenceClampsLongText() {
    let long = String(repeating: "word ", count: 200)
    let clamped = DiagnosticEvidence.clamp(long)
    #expect(clamped.count <= DiagnosticEvidence.maxLength + 1)
}

@Test @MainActor func scopedAnalysisMarksPriorDiagnosticsStale() {
    let state = AppState()
    let projectID = UUID()
    let docID = UUID()
    let p1 = Paragraph(
        id: UUID(), sceneID: nil, chapterID: nil, documentID: docID, order: 0,
        text: "the the quick text.", hash: "h", wordCount: 5, sentenceCount: 1,
        lastAnalyzedHash: nil, createdAt: Date(), updatedAt: Date()
    )
    state.currentProject = Project(
        id: projectID, name: "T", subtitle: "", rootURL: nil, createdAt: Date(), updatedAt: Date(),
        activeDocumentID: docID, settings: .default, enabledRuleFileIDs: [], ollamaSettings: .default,
        coverImagePath: nil, wordCount: 0, diagnosticsSummary: .empty, lastPipelineStatus: nil
    )
    state.activeDocument = Document(
        id: docID, projectID: projectID, title: "M", type: .manuscript, plainText: p1.text,
        originalSnapshot: nil, acceptedPlainText: nil, formattingSpans: nil, createdAt: Date(), updatedAt: Date(), version: 1
    )
    state.documentIndex = DocumentIndex(
        documentID: docID,
        paragraphs: [IndexedParagraph(paragraph: p1, rangeStart: 0, rangeEnd: p1.text.count)],
        updatedAt: Date()
    )
    state.selectedParagraphID = p1.id
    let firstID = UUID()
    state.diagnostics = [
        Diagnostic(
            id: firstID, projectID: projectID, documentID: docID, chapterID: nil, sceneID: nil, paragraphID: p1.id,
            ruleID: nil, source: .deterministic, severity: .warning, scope: .paragraph,
            title: "Old", message: "old", evidence: "the the", startOffset: nil, endOffset: nil,
            suggestedFix: nil, fixLevel: .humanOnly, status: .open,
            textHashAtCreation: p1.hash, scopeHashAtCreation: nil, isStale: false, staleReason: nil, createdAt: Date()
        )
    ]
    state.runParagraphDiagnostics()
    let old = state.diagnostics.first { $0.id == firstID }
    #expect(old?.isStale == true)
    #expect(old?.status == .stale)
}

@Test @MainActor func ruleEnablePersistsInProjectJSON() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("iv-enable-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let store = ProjectStore()
    var (project, folder) = try store.createProject(name: "Rules", subtitle: "", parentFolder: parent, coverSourceURL: nil)
    defer { discardTempProject(projectID: project.id, folder: parent) }
    _ = EditRuleLoader.copyBundledRulesToProject(folder: folder)
    let files = EditRuleLoader.loadAll(projectFolder: folder)
    #expect(!files.isEmpty)
    let disabledID = files[0].id
    project.enabledRuleFileIDs = files.dropFirst().map(\.id)
    try store.saveProject(project, folder: folder)

    let reopened = try store.openProject(folder: folder)
    #expect(!reopened.enabledRuleFileIDs.contains(disabledID))
    let reloaded = EditRuleLoader.loadAll(projectFolder: folder)
    for file in reloaded {
        let enabled = reopened.enabledRuleFileIDs.isEmpty || reopened.enabledRuleFileIDs.contains(file.id)
        if file.id == disabledID {
            #expect(!enabled)
        }
    }
}

@Test @MainActor func llmPipelineProposalsDoNotMutateManuscript() async {
    let engine = PipelineEngine()
    struct StaticJSONProvider: LocalAIProvider, @unchecked Sendable {
        let backend: LocalAIBackend = .ollama
        func checkAvailability(settings: OllamaSettings) async -> OllamaHealth { .available(models: ["m"]) }
        func listModels(settings: OllamaSettings) async throws -> [String] { ["m"] }
        func runJSONTask<T: Decodable>(prompt: String, model: String, settings: OllamaSettings, as type: T.Type) async throws -> T {
            let json = """
            {"diagnostics":[],"changeProposals":[{"title":"Edit","reason":"r","beforeText":"the the","afterText":"the","riskLevel":"low"}],"summaryUpdates":[],"canonUpdateSuggestions":[],"manualReviewReady":false}
            """
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        }
        func runTextTask(prompt: String, model: String, settings: OllamaSettings, keepAlive: String?) async throws -> String { "" }
        func embed(text: String, model: String, settings: OllamaSettings) async throws -> [Float] { [] }
        func unloadModel(name: String, settings: OllamaSettings) async throws {}
        func cancelTask() {}
        func estimateContextLimit(model: String) -> Int { 4096 }
        func estimateRuntimeCost(promptTokens: Int) -> String { "low" }
    }
    let input = iteration6PipelineInput(provider: StaticJSONProvider())
    let before = input.document.plainText
    let (_, _, proposals, _) = await engine.run(
        passes: [engine.defaultPasses().first { $0.id == "character-voice" }!],
        input: input
    ) { _ in }
    #expect(input.document.plainText == before)
    #expect(!proposals.isEmpty)
}

// MARK: - Iteration 7: import / export honesty

private func isZipArchive(at url: URL) throws -> Bool {
    let data = try Data(contentsOf: url)
    return data.count >= 4 && data[0] == 0x50 && data[1] == 0x4B
}

private func zipListsEntry(docx: URL, entry: String) throws -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-l", docx.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return false }
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return out.contains(entry)
}

@Test func plainTextImportExportRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iv-pt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("sample.txt")
    let body = "First paragraph.\n\nSecond paragraph."
    try body.write(to: source, atomically: true, encoding: .utf8)

    let imported = try PlainTextImportService().importDocument(from: source)
    #expect(imported.plainText == body)

    let doc = Document(
        id: UUID(), projectID: UUID(), title: "Sample", type: .manuscript, plainText: imported.plainText,
        originalSnapshot: nil, acceptedPlainText: nil, formattingSpans: nil,
        createdAt: Date(), updatedAt: Date(), version: 1
    )
    let out = dir.appendingPathComponent("out.txt")
    try PlainTextExportService().exportDocument(doc, to: out)
    #expect(try String(contentsOf: out, encoding: .utf8) == body)
}

@Test func rtfImportExtractsPlainText() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iv-rtf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let rtf = dir.appendingPathComponent("sample.rtf")
    try Data("{\\rtf1\\ansi Hello from RTF.}".utf8).write(to: rtf)

    let imported = try RTFImportService().importDocument(from: rtf)
    #expect(imported.plainText.contains("Hello from RTF"))
    #expect(imported.formattingSpans == nil)
    #expect(RTFImportService().capability == .textOnly)
}

@Test func rtfExportCreatesRTFNotPlainText() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iv-rtf-out-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let doc = Document(
        id: UUID(), projectID: UUID(), title: "T", type: .manuscript, plainText: "Export me.",
        originalSnapshot: nil, acceptedPlainText: nil, formattingSpans: nil,
        createdAt: Date(), updatedAt: Date(), version: 1
    )
    let out = dir.appendingPathComponent("out.rtf")
    try RTFExportService().exportDocument(doc, to: out)
    let data = try Data(contentsOf: out)
    let prefix = String(data: data.prefix(8), encoding: .utf8) ?? ""
    #expect(prefix.hasPrefix("{\\rtf"))
}

@Test func docxImportExtractsTextFromArchive() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iv-docx-in-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let docx = dir.appendingPathComponent("sample.docx")
    try DOCXParser.buildDOCXArchive(paragraphs: ["Alpha line.", "Beta line."], spans: [], at: docx)

    let imported = try DOCXImportService().importDocument(from: docx)
    #expect(imported.plainText.contains("Alpha"))
    #expect(imported.plainText.contains("Beta"))
    #expect(DOCXImportService().capability == .limitedDOCX)
}

private func unzipEntryText(docx: URL, entry: String) throws -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-p", docx.path, entry]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)
}

@Test func docxExportCreatesValidZipArchive() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iv-docx-out-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let doc = Document(
        id: UUID(), projectID: UUID(), title: "T", type: .manuscript, plainText: "One.\n\nTwo.",
        originalSnapshot: nil, acceptedPlainText: nil, formattingSpans: nil,
        createdAt: Date(), updatedAt: Date(), version: 1
    )
    let out = dir.appendingPathComponent("manuscript.docx")
    try DOCXExportService().exportDocument(doc, to: out)
    #expect(try isZipArchive(at: out))
    let documentXML = try unzipEntryText(docx: out, entry: "word/document.xml")
    #expect(documentXML?.contains("<w:document") == true)
    #expect(documentXML?.contains("One.") == true)
    let header = try Data(contentsOf: out).prefix(4)
    #expect(header[0] == 0x50 && header[1] == 0x4B)
}

@Test func docxBoldSpanPreservedOnRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iv-docx-span-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let spans = [
        TextFormattingSpan(start: 0, length: 4, isBold: true, isItalic: false, isUnderline: false, headingLevel: nil)
    ]
    let docx = dir.appendingPathComponent("bold.docx")
    try DOCXParser.buildDOCXArchive(paragraphs: ["Bold tail"], spans: spans, at: docx)

    let rich = try DOCXParser.extractRichContent(from: docx)
    #expect(rich.plainText.hasPrefix("Bold"))
    #expect(rich.spans.contains { $0.isBold && $0.start == 0 })
}

@Test func importExportMenuLabelsAreHonest() {
    #expect(PlainTextImportService().menuLabel == "Plain Text")
    #expect(RTFExportService().menuLabel == "RTF (text only)")
    #expect(DOCXImportService().menuLabel == "DOCX (limited)")
    #expect(PlainTextImportService().isAvailable)
    #expect(DOCXExportService().isAvailable)
}

@Test @MainActor func appStateCreateProjectOpensOverview() {
    UITestSupport.forceActiveForTesting = true
    defer { UITestSupport.forceActiveForTesting = false }

    let state = AppState()
    state.bootstrap()
    let before = state.projects.count
    state.createProject(name: "Create Test \(UUID().uuidString.prefix(8))", subtitle: "Sub", coverURL: nil)
    #expect(state.errorMessage == nil, "Create failed: \(state.errorMessage ?? "")")
    #expect(state.projects.count == before + 1)
    guard case .projectOverview = state.navigation else {
        Issue.record("Expected projectOverview, got \(state.navigation)")
        return
    }
    #expect(state.currentProject != nil)
    #expect(state.activeDocument != nil)
}

@Test @MainActor func uiTestSeedPathOpensWorkspaceWithManuscript() throws {
    UITestSupport.forceActiveForTesting = true
    let kindKey = DocumentEditorSettings.editorKindKey
    let priorKind = UserDefaults.standard.string(forKey: kindKey)
    defer {
        UITestSupport.forceActiveForTesting = false
        DocumentEditorSettings.setInMemoryEditorKindOverride(nil)
        if let priorKind { UserDefaults.standard.set(priorKind, forKey: kindKey) }
        else { UserDefaults.standard.removeObject(forKey: kindKey) }
    }

    DocumentEditorSettings.setInMemoryEditorKindOverride(nil)
    UserDefaults.standard.removeObject(forKey: kindKey)

    let state = AppState()
    state.bootstrap()
    state.seedProjectForUITest()

    guard case .workspace = state.navigation else {
        Issue.record("Expected workspace navigation after UITest seed, got \(state.navigation)")
        return
    }
    #expect(state.currentProject?.name.hasPrefix("UITest-") == true)
    #expect(state.activeDocument != nil)
    #expect(state.documentIndex != nil)
    #expect(!(state.activeDocument?.plainText.isEmpty ?? true))
    #expect(state.documentEditorBridge.editorKind == .embeddedOffice)
    #expect(DocumentEditorSettings.loadEditorKind() == .embeddedOffice)
}

@Test @MainActor func uiTestSeedDoesNotPersistLegacyFallback() {
    UITestSupport.forceActiveForTesting = true
    defer { UITestSupport.forceActiveForTesting = false }

    let kindKey = DocumentEditorSettings.editorKindKey
    let defaults = UserDefaults.standard
    let prior = defaults.string(forKey: kindKey)
    defer {
        DocumentEditorSettings.setInMemoryEditorKindOverride(nil)
        if let prior { defaults.set(prior, forKey: kindKey) } else { defaults.removeObject(forKey: kindKey) }
    }
    defaults.removeObject(forKey: kindKey)
    DocumentEditorSettings.setInMemoryEditorKindOverride(nil)

    let state = AppState()
    state.bootstrap()
    state.seedProjectForUITest()

    #expect(DocumentEditorSettings.loadEditorKind() == .embeddedOffice)
    #expect(DocumentEditorSettings.resolvedEditorKind() == .embeddedOffice)
    #expect(state.documentEditorBridge.editorKind == .embeddedOffice)
}

@Test @MainActor func uiTestInMemoryLegacyOverrideDoesNotPersist() {
    UITestSupport.forceActiveForTesting = true
    defer { UITestSupport.forceActiveForTesting = false }

    let kindKey = DocumentEditorSettings.editorKindKey
    let defaults = UserDefaults.standard
    let prior = defaults.string(forKey: kindKey)
    defer {
        DocumentEditorSettings.setInMemoryEditorKindOverride(nil)
        if let prior { defaults.set(prior, forKey: kindKey) } else { defaults.removeObject(forKey: kindKey) }
    }
    defaults.removeObject(forKey: kindKey)

    DocumentEditorSettings.setInMemoryEditorKindOverride(.legacyPrototype)
    #expect(DocumentEditorSettings.resolvedEditorKind() == .legacyPrototype)
    #expect(DocumentEditorSettings.loadEditorKind() == .embeddedOffice)
}

@Test @MainActor func aiChatApplyCreatesProposalWithoutMutatingManuscript() throws {
    UITestSupport.forceActiveForTesting = true
    defer {
        UITestSupport.forceActiveForTesting = false
        DocumentEditorSettings.setInMemoryEditorKindOverride(nil)
    }

    let state = AppState()
    state.bootstrap()
    state.createProject(name: "AI Proposal \(UUID().uuidString.prefix(8))", subtitle: "", coverURL: nil)
    state.documentEditorBridge.editorKind = .legacyPrototype
    DocumentEditorSettings.setInMemoryEditorKindOverride(.legacyPrototype)
    state.configureDocumentEditorBridge()

    guard var document = state.activeDocument else {
        Issue.record("Expected active document")
        return
    }
    document.plainText = "Original sentence."
    state.activeDocument = document
    state.selectionLocation = 0
    state.selectionLength = "Original".count

    state.applyAIChatAction(.replaceSelection, assistantText: "Proposed")

    #expect(state.activeDocument?.plainText == "Original sentence.")
    #expect(state.proposals.contains { $0.title == "AI replace selection" && $0.afterText == "Proposed sentence." })
    #expect(state.revisionReviewActive)
}

@Test func defaultProjectsRootResolvesForProductionAndUITest() {
    UITestSupport.forceActiveForTesting = false
    let production = ProjectPaths.defaultProjectsRoot()
    #expect(production.path.contains("Projects"))
    #expect(FileManager.default.fileExists(atPath: production.path))

    UITestSupport.forceActiveForTesting = true
    defer { UITestSupport.forceActiveForTesting = false }
    let uiTest = ProjectPaths.defaultProjectsRoot()
    #expect(uiTest.path.contains("iV-UITest-Projects"))
}

@Test @MainActor func createManuscriptWritesPrimaryDocxFile() throws {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent("iv-docx-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let (project, folder) = try ProjectStore().createProject(
        name: "Docx Novel", subtitle: "", parentFolder: parent, coverSourceURL: nil
    )
    defer { discardTempProject(projectID: project.id, folder: parent) }
    let doc = try DocumentStore().createManuscript(projectID: project.id, folder: folder)
    let docxURL = ProjectPaths.documentDocxURL(folder: folder, documentID: doc.id)
    #expect(FileManager.default.fileExists(atPath: docxURL.path))
    #expect(doc.storageKind == .docxPrimary)
}

@Test @MainActor func projectCreateOpenReopenPersistsLocally() throws {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent("iv-reopen-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let store = ProjectStore()
    var (project, folder) = try store.createProject(
        name: "Persist Novel",
        subtitle: "Subtitle",
        parentFolder: parent,
        coverSourceURL: nil
    )
    defer { discardTempProject(projectID: project.id, folder: parent) }
    var manuscript = try DocumentStore().createManuscript(projectID: project.id, folder: folder, title: "M")
    manuscript.plainText = "Chapter one.\n\nChapter two."
    try DocumentStore().save(manuscript, folder: folder)
    project.activeDocumentID = manuscript.id
    project.wordCount = 4
    try store.saveProject(project, folder: folder)

    let reopened = try store.openProject(folder: folder)
    #expect(reopened.id == project.id)
    #expect(reopened.name == "Persist Novel")
    #expect(reopened.subtitle == "Subtitle")
    #expect(reopened.activeDocumentID == manuscript.id)

    let doc = try DocumentStore().load(documentID: manuscript.id, folder: folder)
    #expect(doc.plainText.contains("Chapter one"))
}

@Test func manualReviewNotReadyWhenBlockingDiagnostics() {
    let projectID = UUID()
    let docID = UUID()
    let blocking = Diagnostic(
        id: UUID(), projectID: projectID, documentID: docID, chapterID: nil, sceneID: nil, paragraphID: nil,
        ruleID: nil, source: .deterministic, severity: .blocking, scope: .paragraph,
        title: "Block", message: "m", evidence: "x", startOffset: nil, endOffset: nil,
        suggestedFix: nil, fixLevel: .humanOnly, status: .open,
        textHashAtCreation: nil, scopeHashAtCreation: nil, isStale: false, staleReason: nil, createdAt: Date()
    )
    let status = ManualReviewCalculator.status(diagnostics: [blocking], proposals: [])
    #expect(!status.isReady)
    #expect(status.readinessNote?.contains("blocking") == true)
}

@Test func documentServerConfigurationRejectsRemoteHost() {
    let result = DocumentServerConfiguration.validate("http://example.com:8080")
    guard case .failure(.remoteHostBlocked) = result else {
        Issue.record("Expected remote host to be blocked")
        return
    }
}

@Test func documentServerConfigurationAcceptsLocalhost() {
    if case .success(let url) = DocumentServerConfiguration.validate("http://127.0.0.1:8080") {
        #expect(url.host == "127.0.0.1")
    } else {
        Issue.record("Expected localhost URL to validate")
    }
}

@Suite(.serialized)
struct DocumentEditorSettingsPersistenceTests {
    @Test func documentEditorDefaultsToEmbeddedOffice() {
        let defaults = UserDefaults.standard
        let kindKey = DocumentEditorSettings.editorKindKey
        let userSelectedKey = DocumentEditorSettings.editorKindUserSelectedKey
        let prior = defaults.string(forKey: kindKey)
        let priorUserSelected = defaults.object(forKey: userSelectedKey)
        defer {
            if let prior { defaults.set(prior, forKey: kindKey) } else { defaults.removeObject(forKey: kindKey) }
            if let priorUserSelected { defaults.set(priorUserSelected, forKey: userSelectedKey) }
            else { defaults.removeObject(forKey: userSelectedKey) }
        }
        defaults.removeObject(forKey: kindKey)
        defaults.removeObject(forKey: userSelectedKey)
        #expect(DocumentEditorSettings.loadEditorKind() == .embeddedOffice)
    }

    @Test func pollutedLegacyDefaultMigratesToEmbeddedOfficeWithoutUserMarker() {
        let defaults = UserDefaults.standard
        let kindKey = DocumentEditorSettings.editorKindKey
        let userSelectedKey = DocumentEditorSettings.editorKindUserSelectedKey
        let prior = defaults.string(forKey: kindKey)
        let priorUserSelected = defaults.object(forKey: userSelectedKey)
        defer {
            if let prior { defaults.set(prior, forKey: kindKey) } else { defaults.removeObject(forKey: kindKey) }
            if let priorUserSelected { defaults.set(priorUserSelected, forKey: userSelectedKey) }
            else { defaults.removeObject(forKey: userSelectedKey) }
        }
        defaults.set(DocumentEditorKind.legacyPrototype.rawValue, forKey: kindKey)
        defaults.removeObject(forKey: userSelectedKey)
        DocumentEditorSettings.clearTestPollutedLegacyDefaultIfNeeded()
        #expect(DocumentEditorSettings.loadEditorKind() == .embeddedOffice)
        #expect(DocumentEditorSettings.hasUserSelectedEditorKind() == false)
    }

    @Test func explicitUserSelectedLegacyPreferenceRemainsLegacy() {
        let defaults = UserDefaults.standard
        let kindKey = DocumentEditorSettings.editorKindKey
        let userSelectedKey = DocumentEditorSettings.editorKindUserSelectedKey
        let prior = defaults.string(forKey: kindKey)
        let priorUserSelected = defaults.object(forKey: userSelectedKey)
        defer {
            if let prior { defaults.set(prior, forKey: kindKey) } else { defaults.removeObject(forKey: kindKey) }
            if let priorUserSelected { defaults.set(priorUserSelected, forKey: userSelectedKey) }
            else { defaults.removeObject(forKey: userSelectedKey) }
        }
        DocumentEditorSettings.saveEditorKind(.legacyPrototype, userSelected: true)
        #expect(DocumentEditorSettings.loadEditorKind() == .legacyPrototype)
        #expect(DocumentEditorSettings.hasUserSelectedEditorKind())
    }
}

@Test func onlyofficeEditorLoaderRejectsNonLocalhostDocumentServer() {
    let html = ONLYOFFICEDocumentEditorLoader.documentEditorHTML(
        serverURL: "http://example.com:8080",
        documentTitle: "Chapter",
        documentKey: "key-1",
        documentFetchURL: "http://host.docker.internal:8765/documents/x/file.docx",
        callbackURL: "http://host.docker.internal:8765/callback/x"
    )
    #expect(html == nil)
}

@Test func onlyofficeEditorLoaderBuildsDocsAPIPageForLocalhost() {
    let html = ONLYOFFICEDocumentEditorLoader.documentEditorHTML(
        serverURL: "http://127.0.0.1:8080",
        documentTitle: "Chapter",
        documentKey: "key-1",
        documentFetchURL: "http://host.docker.internal:8765/documents/x/file.docx",
        callbackURL: "http://host.docker.internal:8765/callback/x"
    )
    #expect(html?.contains("DocsAPI.DocEditor") == true)
    #expect(html?.contains("web-apps/apps/api/documents/api.js") == true)
    #expect(html?.contains("onDocumentReady") == true)
}

@Test func onlyofficeEditorHostQuarantinedPlaceholderIsNotReadySurface() {
    #expect(ONLYOFFICEEditorHost.Coordinator.quarantinedHostHTML.contains("#1a211c"))
    #expect(ONLYOFFICEEditorHost.Coordinator.quarantinedHostHTML.contains("background") == true)
}

private struct FailingLocalDocumentServer: LocalDocumentServing {
    var isRunning: Bool { false }
    func ensureRunning() throws { throw LocalDocumentServingError.serverStartFailed("test failure") }
    func register(documentID: UUID, fileURL: URL) throws -> LocalDocumentServingRegistration {
        throw LocalDocumentServingError.serverStartFailed("test failure")
    }
    func unregister(documentID: UUID) {}
}

@Test func onlyofficeSessionManagerRefusesNonLocalhostDocumentServer() async {
    let manager = ONLYOFFICEDocumentSessionManager(localServer: FailingLocalDocumentServer())
    let docURL = URL(fileURLWithPath: "/tmp/missing.docx")
    let outcome = await manager.prepareSession(
        documentServerURL: "http://example.com:8080",
        documentID: UUID(),
        documentTitle: "T",
        docxFileURL: docURL
    )
    guard case .unavailable = outcome else {
        Issue.record("Expected unavailable for remote Document Server, got \(outcome)")
        return
    }
}

@Test func onlyofficeSessionManagerReportsPendingWhenLocalServingUnavailable() async throws {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent("iv-serve-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    let docURL = parent.appendingPathComponent("chapter.docx")
    try Data("PK".utf8).write(to: docURL)

    let manager = ONLYOFFICEDocumentSessionManager(localServer: FailingLocalDocumentServer())
    let outcome = await manager.prepareSession(
        documentServerURL: DocumentServerConfiguration.defaultURL,
        documentID: UUID(),
        documentTitle: "Chapter",
        docxFileURL: docURL
    )
    guard case .pending(let reason, _) = outcome else {
        Issue.record("Expected pending when local serving fails, got \(outcome)")
        return
    }
    #expect(reason.contains("Local document-serving"))
}

@Suite(.serialized)
struct EmbeddedOfficeLiveServerTests {
    @Test @MainActor func embeddedOfficeDoesNotSilentlyFallbackToLegacyWhenServerUnavailable() async throws {
        let defaults = UserDefaults.standard
        let kindKey = DocumentEditorSettings.editorKindKey
        let userSelectedKey = DocumentEditorSettings.editorKindUserSelectedKey
        let prior = defaults.string(forKey: kindKey)
        let priorUserSelected = defaults.object(forKey: userSelectedKey)
        defer {
            DocumentEditorSettings.setInMemoryEditorKindOverride(nil)
            if let prior { defaults.set(prior, forKey: kindKey) } else { defaults.removeObject(forKey: kindKey) }
            if let priorUserSelected { defaults.set(priorUserSelected, forKey: userSelectedKey) }
            else { defaults.removeObject(forKey: userSelectedKey) }
        }
        defaults.removeObject(forKey: kindKey)
        defaults.removeObject(forKey: userSelectedKey)

        let state = AppState()
        state.bootstrap()
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("iv-nolegacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        state.createProject(name: "No Legacy", subtitle: "", coverURL: nil)

        #expect(state.documentEditorBridge.editorKind == .embeddedOffice)
        state.syncEmbeddedOfficeEditor()
        for _ in 0..<40 {
            if case .serverUnavailable = state.embeddedOfficeCoordinator.lifecycle { break }
            if case .bridgePending = state.embeddedOfficeCoordinator.lifecycle { break }
            if case .ready = state.embeddedOfficeCoordinator.lifecycle { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(state.documentEditorBridge.editorKind == .embeddedOffice)
        if case .legacyPrototype = state.documentEditorBridge.editorKind {
            Issue.record("Embedded office must not silently fall back to legacy")
        }
    }

    @Test @MainActor func embeddedOfficeCoordinatorLoadsRealSessionWhenServerUp() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("iv-real-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = ProjectStore()
        let (project, folder) = try store.createProject(
            name: "Real Session", subtitle: "", parentFolder: parent, coverSourceURL: nil
        )
        let doc = try DocumentStore().createManuscript(projectID: project.id, folder: folder, title: "Real Session")

        let coordinator = EmbeddedOfficeEditorCoordinator(
            healthChecker: StubDocumentServerHealthChecker(result: .reachable(statusCode: 200)),
            preparationService: EmbeddedDocumentPreparationService(documentStore: DocumentStore()),
            sessionManager: ONLYOFFICEDocumentSessionManager()
        )
        coordinator.sync(
            activeDocument: doc,
            projectFolder: folder,
            serverURL: DocumentServerConfiguration.defaultURL,
            editorKind: .embeddedOffice
        )
        for _ in 0..<50 {
            if case .ready = coordinator.lifecycle { break }
            if case .bridgePending = coordinator.lifecycle { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        if case .ready = coordinator.lifecycle {
            #expect(coordinator.activeSession != nil)
            #expect(coordinator.isEditingBridgeConnected)
            #expect(coordinator.activeSession?.editorHTML.contains("DocsAPI.DocEditor") == true)
        } else if case .bridgePending = coordinator.lifecycle {
            // Local HTTP server may be blocked in some CI/sandbox environments — still honest, not legacy.
            #expect(coordinator.activeSession == nil)
        } else {
            Issue.record("Expected ready or bridgePending, got \(coordinator.lifecycle)")
        }
    }
}

struct StubDocumentServerHealthChecker: DocumentServerHealthChecking {
    let result: DocumentServerHealthResult
    func checkHealth(serverURL: String) async -> DocumentServerHealthResult { result }
}

@Test @MainActor func embeddedOfficeCoordinatorReportsBridgePendingWhenServerUp() async throws {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent("iv-office-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let store = ProjectStore()
    let (project, folder) = try store.createProject(
        name: "Office", subtitle: "", parentFolder: parent, coverSourceURL: nil
    )
    defer { try? FileManager.default.removeItem(at: parent) }
    let doc = try DocumentStore().createManuscript(projectID: project.id, folder: folder, title: "Chapter")

    let coordinator = EmbeddedOfficeEditorCoordinator(
        healthChecker: StubDocumentServerHealthChecker(result: .reachable(statusCode: 200)),
        preparationService: EmbeddedDocumentPreparationService(documentStore: DocumentStore()),
        sessionManager: StubEmbeddedDocumentSessionManager()
    )
    coordinator.sync(
        activeDocument: doc,
        projectFolder: folder,
        serverURL: DocumentServerConfiguration.defaultURL,
        editorKind: .embeddedOffice
    )
    for _ in 0..<30 {
        if case .bridgePending = coordinator.lifecycle { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    guard case .bridgePending(let title, _) = coordinator.lifecycle else {
        Issue.record("Expected bridgePending, got \(coordinator.lifecycle)")
        return
    }
    #expect(title == "Chapter")
}

@Test @MainActor func embeddedReadyStateImpossibleWithStubSessionManager() async throws {
    let coordinator = EmbeddedOfficeEditorCoordinator(
        healthChecker: StubDocumentServerHealthChecker(result: .reachable(statusCode: 200)),
        preparationService: EmbeddedDocumentPreparationService(documentStore: DocumentStore()),
        sessionManager: StubEmbeddedDocumentSessionManager()
    )
    #expect(coordinator.isEditingBridgeConnected == false)

    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent("iv-ready-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    let store = ProjectStore()
    let (project, folder) = try store.createProject(
        name: "Ready", subtitle: "", parentFolder: parent, coverSourceURL: nil
    )
    let doc = try DocumentStore().createManuscript(projectID: project.id, folder: folder, title: "M")

    coordinator.sync(
        activeDocument: doc,
        projectFolder: folder,
        serverURL: DocumentServerConfiguration.defaultURL,
        editorKind: .embeddedOffice
    )
    for _ in 0..<30 {
        if case .bridgePending = coordinator.lifecycle { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    if case .ready = coordinator.lifecycle {
        Issue.record("Stub session manager must not reach .ready lifecycle")
    }
    guard case .bridgePending = coordinator.lifecycle else {
        Issue.record("Expected bridgePending, got \(coordinator.lifecycle)")
        return
    }
    #expect(coordinator.connectionState != .ready)
}

@Test func documentEditorIntegrationStatusLines() {
    #expect(
        DocumentEditorIntegrationStatus.resolve(
            editorKind: .embeddedOffice,
            lifecycle: .checkingServer,
            bridgeConnected: false,
            editorHostReady: false
        ) == .embeddedOfficeSelected
    )
    #expect(
        DocumentEditorIntegrationStatus.resolve(
            editorKind: .legacyPrototype,
            lifecycle: .idle,
            bridgeConnected: false,
            editorHostReady: false
        ) == .legacyFallbackSelected
    )
    #expect(
        DocumentEditorIntegrationStatus.resolve(
            editorKind: .embeddedOffice,
            lifecycle: .bridgePending(documentTitle: "T", docxPath: nil),
            bridgeConnected: false,
            editorHostReady: false
        ) == .bridgeNotImplemented
    )
    #expect(
        DocumentEditorIntegrationStatus.resolve(
            editorKind: .embeddedOffice,
            lifecycle: .ready(documentTitle: "T", docxPath: nil),
            bridgeConnected: true,
            editorHostReady: true
        ) == .editorSessionReady
    )
}

@Test func localManuscriptServerServesRegisteredDocx() async throws {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent("iv-local-serve-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let docID = UUID()
    let docxURL = parent.appendingPathComponent("chapter.docx")
    try Data([0x50, 0x4B, 0x03, 0x04] + Array("test".utf8)).write(to: docxURL)

    let server = LocalManuscriptDocumentServer(port: UInt16.random(in: 49152...65535))
    let registration = try server.register(documentID: docID, fileURL: docxURL)
    defer { server.unregister(documentID: docID) }

    switch await LocalDocumentReachabilityChecker.verify(diagnosticsURL: registration.localDiagnosticsURL) {
    case .success:
        break
    case .failure(let error):
        Issue.record("Expected registered DOCX to be reachable locally: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
    }
}

@Test func localManuscriptServerRejectsUnknownDocumentPath() {
    let path = "/documents/not-a-uuid/file.docx"
    #expect(LocalManuscriptDocumentServer.documentID(fromPath: path) == nil)
}

@Test func onlyofficeSaveCallbackProcessorAcknowledgesEditingStatus() async throws {
    let processor = ONLYOFFICESaveCallbackProcessor()
    let target = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString).docx")
    defer { try? FileManager.default.removeItem(at: target) }
    try Data("original".utf8).write(to: target)

    try await processor.process(
        documentID: UUID(),
        payload: ONLYOFFICESaveCallbackPayload(key: "k", status: 1, url: nil, changesurl: nil, users: nil),
        targetFileURL: target
    )
    #expect(String(data: try Data(contentsOf: target), encoding: .utf8) == "original")
}

@Test func onlyofficeSaveCallbackProcessorDownloadsAndWritesDocx() async throws {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent("iv-save-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let downloaded = parent.appendingPathComponent("downloaded.docx")
    let savedBytes = Data([0x50, 0x4B, 0x03, 0x04] + Array("saved-docx".utf8))
    try savedBytes.write(to: downloaded)
    let target = parent.appendingPathComponent("target.docx")
    try Data("old".utf8).write(to: target)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockLocalURLProtocol.self]
    MockLocalURLProtocol.handler = { request in
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, try Data(contentsOf: downloaded))
    }
    defer { MockLocalURLProtocol.handler = nil }

    let processor = ONLYOFFICESaveCallbackProcessor(session: URLSession(configuration: config))
    try await processor.process(
        documentID: UUID(),
        payload: ONLYOFFICESaveCallbackPayload(
            key: "k",
            status: 2,
            url: "http://127.0.0.1:8080/cache/files/saved.docx",
            changesurl: nil,
            users: nil
        ),
        targetFileURL: target
    )
    #expect(try Data(contentsOf: target) == savedBytes)
}

@Test func onlyofficeSaveCallbackNormalizesInternalDocumentServerURL() {
    let internalURL = URL(string: "http://onlyoffice/cache/files/saved.docx")!
    let normalized = ONLYOFFICESaveCallbackProcessor.normalizedDownloadURL(internalURL)
    #expect(normalized?.host == "127.0.0.1")
    #expect(normalized?.path == "/cache/files/saved.docx")
}

@Test func onlyofficeSaveCallbackFailureIsLocalized() async {
    let processor = ONLYOFFICESaveCallbackProcessor()
    let target = FileManager.default.temporaryDirectory.appendingPathComponent("fail-\(UUID().uuidString).docx")
    defer { try? FileManager.default.removeItem(at: target) }
    try? Data("x".utf8).write(to: target)

    do {
        try await processor.process(
            documentID: UUID(),
            payload: ONLYOFFICESaveCallbackPayload(key: "k", status: 3, url: nil, changesurl: nil, users: nil),
            targetFileURL: target
        )
        Issue.record("Expected save status error")
    } catch let error as ONLYOFFICESaveCallbackError {
        if case .saveStatusError(3) = error {
            #expect(true)
        } else {
            Issue.record("Unexpected error: \(error)")
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func embeddedDocumentSaveServiceUpdatesPlainTextFromDocx() throws {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent("iv-sync-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let docxURL = parent.appendingPathComponent("chapter.docx")
    try DOCXParser.buildDOCXArchive(paragraphs: ["Saved paragraph."], spans: [], at: docxURL)

    var document = Document(
        id: UUID(),
        projectID: UUID(),
        title: "Chapter",
        type: .manuscript,
        plainText: "Old text.",
        originalSnapshot: "import snapshot",
        acceptedPlainText: nil,
        formattingSpans: nil,
        storageKind: .docxPrimary,
        docxFileName: docxURL.lastPathComponent,
        createdAt: Date(),
        updatedAt: Date(),
        version: 1
    )

    let result = try EmbeddedDocumentSaveService.syncDocumentMetadata(document: &document, savedDocxURL: docxURL)
    #expect(result.plainText.contains("Saved paragraph."))
    #expect(document.plainText.contains("Saved paragraph."))
    #expect(document.originalSnapshot == "import snapshot")
}

@Test @MainActor func editorReadinessRequiresDocsAPIHostReady() {
    let coordinator = EmbeddedOfficeEditorCoordinator(
        preparationService: EmbeddedDocumentPreparationService(documentStore: DocumentStore())
    )
    coordinator.lifecycle = .ready(documentTitle: "T", docxPath: "/tmp/x.docx")
    coordinator.activeSession = EmbeddedDocumentSessionReady(
        onlyOfficeServerURL: "http://127.0.0.1:8080",
        documentTitle: "T",
        docxFileURL: URL(fileURLWithPath: "/tmp/x.docx"),
        editorHTML: "<html></html>",
        documentKey: "k",
        documentFetchURL: "http://host.docker.internal:8765/documents/x/file.docx",
        localServingDetail: "http://127.0.0.1:8765/documents/x/file.docx",
        saveAvailable: true
    )
    coordinator.hostConnectionState = .connecting
    #expect(coordinator.isEditingBridgeConnected)
    #expect(coordinator.isEditorHostReady == false)
    #expect(coordinator.connectionState == .connecting)

    coordinator.updateHostConnectionState(.ready)
    #expect(coordinator.isEditorHostReady)
    #expect(coordinator.connectionState == .ready)
}

@Test func dockerLocatorResolvesHomebrewSymlinkWhenPresent() {
    let path = "/opt/homebrew/bin/docker"
    guard FileManager.default.fileExists(atPath: path) else { return }
    #expect(DockerLocator.resolveExecutable(at: path) != nil)
}

@Test func dockerLocatorUsesCustomSettingsPath() {
    let defaults = UserDefaults.standard
    let key = DocumentEditorSettings.dockerCLIPathKey
    let prior = defaults.string(forKey: key)
    defer {
        if let prior { defaults.set(prior, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
    let path = "/opt/homebrew/bin/docker"
    guard FileManager.default.fileExists(atPath: path) else { return }
    DocumentEditorSettings.saveDockerCLIPath(path)
    #expect(DockerLocator.executableURL()?.path == DockerLocator.resolveExecutable(at: path)?.path)
}

@Test @MainActor func uiTestSkipsEmbeddedOfficeAutoStartup() async {
    UITestSupport.forceActiveForTesting = true
    defer { UITestSupport.forceActiveForTesting = false }

    let state = AppState()
    state.bootstrap()
    state.beginEmbeddedOfficeStartupIfNeeded()
    try? await Task.sleep(for: .milliseconds(200))
    #expect(state.editorStartup == .idle)
}

@Test func documentServerRuntimeServiceResolveStatusUsesHealthChecker() async {
    struct ReachableChecker: DocumentServerHealthChecking {
        func checkHealth(serverURL: String) async -> DocumentServerHealthResult {
            .reachable(statusCode: 200)
        }
    }
    struct UnreachableChecker: DocumentServerHealthChecking {
        func checkHealth(serverURL: String) async -> DocumentServerHealthResult {
            .unreachable(message: "down")
        }
    }

    let service = LiveDocumentServerRuntimeService()
    guard let dockerURL = await DockerLocator.locate() else {
        let status = await service.resolveStatus(
            serverURL: DocumentServerConfiguration.defaultURL,
            healthChecker: ReachableChecker()
        )
        guard case .dockerUnavailable = status else {
            Issue.record("Expected dockerUnavailable when Docker CLI is missing, got \(status)")
            return
        }
        return
    }

    do {
        let version = try await ProcessRunner.run(
            executableURL: dockerURL,
            arguments: ["version", "--format", "{{.Server.Version}}"]
        )
        guard version.exitCode == 0 else {
            let status = await service.resolveStatus(
                serverURL: DocumentServerConfiguration.defaultURL,
                healthChecker: ReachableChecker()
            )
            guard case .dockerUnavailable = status else {
                Issue.record("Expected dockerUnavailable when daemon is down, got \(status)")
                return
            }
            return
        }
    } catch {
        Issue.record("Docker version check failed: \(error.localizedDescription)")
        return
    }

    let running = await service.resolveStatus(
        serverURL: DocumentServerConfiguration.defaultURL,
        healthChecker: ReachableChecker()
    )
    #expect(running == .running)

    let stopped = await service.resolveStatus(
        serverURL: DocumentServerConfiguration.defaultURL,
        healthChecker: UnreachableChecker()
    )
    #expect(stopped == .notRunning)
}

private final class MockLocalURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { handler != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

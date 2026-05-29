import Foundation

enum SummaryRefreshService {
  /// Deterministic excerpt summary (first sentences, capped).
  static func deterministicSummary(for text: String, maxWords: Int = 80) -> String {
    let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    var words: [String] = []
    for sentence in sentences {
      words.append(contentsOf: sentence.split { $0.isWhitespace }.map(String.init))
      if words.count >= maxWords { break }
    }
    let excerpt = words.prefix(maxWords).joined(separator: " ")
    return excerpt.isEmpty ? String(text.prefix(300)) : excerpt + (words.count >= maxWords ? "…" : "")
  }

  @MainActor
  static func refreshSceneSummaries(
    structure: DocumentStructure,
    index: DocumentIndex,
    projectID: UUID
  ) -> [NarrativeMemory] {
    structure.scenes.compactMap { scene -> NarrativeMemory? in
      guard let startID = scene.startParagraphID else { return nil }
      let text = textForScene(scene, index: index, structure: structure)
      guard !text.isEmpty else { return nil }
      return NarrativeMemory(
        id: UUID(),
        projectID: projectID,
        scope: .scene,
        scopeID: scene.id,
        summary: deterministicSummary(for: text),
        openThreads: [],
        resolvedThreads: [],
        activeObjects: [],
        characterStates: [],
        atmospherePatterns: [],
        timelineNotes: [],
        sourceHash: TextUtilities.hashText(text),
        updatedAt: Date()
      )
    }
  }

  @MainActor
  static func refreshChapterSummaries(
    structure: DocumentStructure,
    index: DocumentIndex,
    projectID: UUID
  ) -> [NarrativeMemory] {
    structure.chapters.compactMap { chapter -> NarrativeMemory? in
      let text = textForChapter(chapter, index: index)
      guard !text.isEmpty else { return nil }
      return NarrativeMemory(
        id: UUID(),
        projectID: projectID,
        scope: .chapter,
        scopeID: chapter.id,
        summary: deterministicSummary(for: text, maxWords: 120),
        openThreads: [],
        resolvedThreads: [],
        activeObjects: [],
        characterStates: [],
        atmospherePatterns: [],
        timelineNotes: [],
        sourceHash: TextUtilities.hashText(text),
        updatedAt: Date()
      )
    }
  }

  static func refreshDocumentSummary(document: Document, projectID: UUID) -> NarrativeMemory {
    NarrativeMemory(
      id: UUID(),
      projectID: projectID,
      scope: .document,
      scopeID: document.id,
      summary: deterministicSummary(for: document.plainText, maxWords: 150),
      openThreads: [],
      resolvedThreads: [],
      activeObjects: [],
      characterStates: [],
      atmospherePatterns: [],
      timelineNotes: [],
      sourceHash: TextUtilities.hashText(document.plainText),
      updatedAt: Date()
    )
  }

  @MainActor
  static func refreshViaLLM(
    scope: MemoryScope,
    scopeID: UUID,
    text: String,
    project: Project,
    provider: any LocalAIProvider
  ) async throws -> String {
    let prompt = """
    Summarize the following prose for editorial memory. Return JSON: {"summary": "..."}
    Scope: \(scope.rawValue)
    Text:
    \(text.prefix(6000))
    """
    struct Response: Decodable { let summary: String }
    let settings = project.ollamaSettings
    let model = settings.modelName.isEmpty ? (try? await provider.listModels(settings: settings).first) ?? "llama3.2" : settings.modelName
    let response = try await provider.runJSONTask(prompt: prompt, model: model, settings: settings, as: Response.self)
    return response.summary
  }

  private static func textForScene(_ scene: Scene, index: DocumentIndex, structure: DocumentStructure) -> String {
    let paragraphs = index.paragraphs.map(\.paragraph)
    guard let startID = scene.startParagraphID,
          let startOrder = paragraphs.firstIndex(where: { $0.id == startID }) else { return "" }
    let endOrder: Int
    if let endID = scene.endParagraphID, let end = paragraphs.firstIndex(where: { $0.id == endID }) {
      endOrder = end
    } else if let next = structure.scenes.filter({ $0.chapterID == scene.chapterID && $0.order > scene.order }).sorted(by: { $0.order < $1.order }).first,
              let nextStart = next.startParagraphID,
              let nextIdx = paragraphs.firstIndex(where: { $0.id == nextStart }) {
      endOrder = max(startOrder, nextIdx - 1)
    } else {
      endOrder = paragraphs.count - 1
    }
    return paragraphs[startOrder...endOrder].map(\.text).joined(separator: "\n\n")
  }

  private static func textForChapter(_ chapter: Chapter, index: DocumentIndex) -> String {
    let paragraphs = index.paragraphs.map(\.paragraph)
    guard let startID = chapter.startParagraphID,
          let startOrder = paragraphs.firstIndex(where: { $0.id == startID }) else { return "" }
    let endOrder = chapter.endParagraphID.flatMap { id in paragraphs.firstIndex(where: { $0.id == id }) } ?? (paragraphs.count - 1)
    return paragraphs[startOrder...endOrder].map(\.text).joined(separator: "\n\n")
  }
}

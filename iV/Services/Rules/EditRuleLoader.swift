import Foundation

enum EditRuleLoader {
    static func category(for fileName: String) -> (EditRuleCategory, Int) {
        switch fileName.lowercased() {
        case let n where n.hasPrefix("00-minimum-gate"): return (.minimumGate, 0)
        case let n where n.hasPrefix("01-core-prose"): return (.coreProse, 10)
        case let n where n.hasPrefix("02-style-line"): return (.styleLineControl, 20)
        case let n where n.hasPrefix("03-dialogue"): return (.dialogue, 30)
        case let n where n.hasPrefix("04-character"): return (.characterVoice, 40)
        case let n where n.hasPrefix("05-world"): return (.worldInformation, 50)
        case let n where n.hasPrefix("06-atmosphere"): return (.atmosphereSensory, 60)
        case let n where n.hasPrefix("07-action"): return (.actionAftermath, 70)
        case let n where n.hasPrefix("08-canon"): return (.canonLanguage, 80)
        case let n where n.hasPrefix("09-causality"): return (.causalityPOVLogic, 90)
        default: return (.custom, 100)
        }
    }

    /// Xcode may copy bundled rules into `Resources/edit-rules/` or flat into `Resources/`.
    static func isBundledRuleFileName(_ fileName: String) -> Bool {
        let pattern = #"^\d{2}-.+\.(mdc|md)$"#
        return fileName.range(of: pattern, options: .regularExpression) != nil
    }

    static func source(for path: String) -> EditRuleFileSource {
        if path.contains(".ivproject") { return .project }
        if isBundledPath(path) { return .bundled }
        return .development
    }

    static func isBundledPath(_ path: String) -> Bool {
        if path.contains(".ivproject") { return false }
        if path.contains("/edit-rules/") { return true }
        let name = URL(fileURLWithPath: path).lastPathComponent
        if path.contains("Contents/Resources"), isBundledRuleFileName(name) { return true }
        return false
    }

    static func bundledRulesDirectory() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let nested = resourceURL.appendingPathComponent("edit-rules", isDirectory: true)
        if FileManager.default.fileExists(atPath: nested.path) { return nested }
        return resourceURL
    }

    /// Lower index = lower priority. Project rules override repo/bundled rules with the same filename.
    static func discoverDirectories(projectFolder: URL? = nil) -> [URL] {
        var dirs: [URL] = []
        if let bundled = bundledRulesDirectory() {
            dirs.append(bundled)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("src/edit-rules", isDirectory: true),
            cwd.appendingPathComponent("edit-rules", isDirectory: true),
            cwd.deletingLastPathComponent().appendingPathComponent("src/edit-rules", isDirectory: true),
            cwd.deletingLastPathComponent().appendingPathComponent("edit-rules", isDirectory: true)
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if !dirs.contains(url) { dirs.append(url) }
        }
        if let projectFolder {
            let projectRules = ProjectPaths.editRulesFolder(in: projectFolder)
            if FileManager.default.fileExists(atPath: projectRules.path) {
                dirs.append(projectRules)
            }
        }
        return dirs
    }

    static func loadAll(projectFolder: URL? = nil) -> [EditRuleFile] {
        var filesByName: [String: EditRuleFile] = [:]
        let bundledRoot = Bundle.main.resourceURL
        for directory in discoverDirectories(projectFolder: projectFolder) {
            guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = url.lastPathComponent
                if directory == bundledRoot, !isBundledRuleFileName(name) { continue }
                let ext = url.pathExtension.lowercased()
                guard ext == "mdc" || ext == "md" else { continue }
                if let file = loadFile(at: url) {
                    filesByName[name] = file
                }
            }
        }
        return filesByName.values.sorted { $0.priority < $1.priority }
    }

    @discardableResult
    static func copyBundledRulesToProject(folder: URL) -> Int {
        let dest = ProjectPaths.editRulesFolder(in: folder)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        var copied = 0
        guard let bundledDir = bundledRulesDirectory(),
              let items = try? FileManager.default.contentsOfDirectory(at: bundledDir, includingPropertiesForKeys: nil) else {
            return 0
        }
        for url in items where isBundledRuleFileName(url.lastPathComponent) {
            let target = dest.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.copyItem(at: url, to: target)
                copied += 1
            }
        }
        return copied
    }

    static func loadFile(at url: URL) -> EditRuleFile? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let (category, priority) = category(for: url.lastPathComponent)
        let sections = parseSections(from: raw)
        return EditRuleFile(
            id: stableID(for: url.lastPathComponent),
            fileName: url.lastPathComponent,
            path: url.path,
            rawMarkdown: raw,
            parsedSections: sections,
            detectedCategory: category,
            priority: priority,
            enabled: true,
            loadedAt: Date()
        )
    }

    static func parseSections(from markdown: String) -> [MarkdownSection] {
        var sections: [MarkdownSection] = []
        var currentHeading = "Introduction"
        var currentLevel = 1
        var buffer: [String] = []

        func flush() {
            let content = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty || currentHeading != "Introduction" {
                sections.append(MarkdownSection(id: UUID(), heading: currentHeading, level: currentLevel, content: content))
            }
            buffer.removeAll()
        }

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("#") {
                flush()
                let hashes = line.prefix(while: { $0 == "#" }).count
                currentLevel = max(hashes, 1)
                currentHeading = line.drop(while: { $0 == "#" || $0 == " " }).trimmingCharacters(in: .whitespaces)
            } else {
                buffer.append(line)
            }
        }
        flush()
        return sections
    }

    /// Stable ID per filename so project `enabledRuleFileIDs` persist across reloads.
    static func stableID(for fileName: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in fileName.utf8.enumerated() {
            bytes[i % 16] ^= b
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum EditRuleExcerptBuilder {
    static func excerpts(from files: [EditRuleFile], categories: [EditRuleCategory], maxChars: Int = 4000) -> [EditRuleExcerpt] {
        var result: [EditRuleExcerpt] = []
        var used = 0
        for file in files where file.enabled && categories.contains(file.detectedCategory) {
            for section in file.parsedSections {
                let content = section.content
                guard !content.isEmpty else { continue }
                if used + content.count > maxChars { break }
                result.append(EditRuleExcerpt(fileName: file.fileName, heading: section.heading, content: content, category: file.detectedCategory))
                used += content.count
            }
        }
        return result
    }
}

import Foundation

enum AtomicFileWriter {
    static func write(data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tempURL = directory.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }

    static func write<T: Encodable>(_ value: T, to url: URL, encoder: JSONEncoder = JSONEncoder()) throws {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try write(data: data, to: url)
    }

    static func write(text: String, to url: URL, encoding: String.Encoding = .utf8) throws {
        guard let data = text.data(using: encoding) else {
            throw NSError(
                domain: "AtomicFileWriter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode text as \(encoding)."]
            )
        }
        try write(data: data, to: url)
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }
}

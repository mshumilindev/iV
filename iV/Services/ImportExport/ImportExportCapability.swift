import Foundation

/// Honest capability tier for import/export — drives menu labels and status messages.
enum ImportExportCapability: String, Sendable {
    /// Full roundtrip for the format (plain text).
    case full
    /// Text is preserved; rich formatting is not roundtripped (RTF).
    case textOnly
    /// Valid DOCX archive with limited inline styles — not full Word compatibility.
    case limitedDOCX

    var menuQualifier: String {
        switch self {
        case .full: ""
        case .textOnly: " (text only)"
        case .limitedDOCX: " (limited)"
        }
    }

    var limitationSummary: String {
        switch self {
        case .full:
            "Full plain-text import and export."
        case .textOnly:
            "Imports and exports manuscript text only. RTF styles and layout are not preserved."
        case .limitedDOCX:
            "Valid Word .docx with text and limited bold, italic, underline, and headings—not full Word compatibility."
        }
    }
}

extension DocumentImportService {
    var menuLabel: String { formatName + capability.menuQualifier }

    var limitationSummary: String { capability.limitationSummary }
}

extension DocumentExportService {
    var menuLabel: String { formatName + capability.menuQualifier }

    var limitationSummary: String { capability.limitationSummary }
}

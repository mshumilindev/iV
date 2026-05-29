import Foundation

enum SplitEditorReference: String, CaseIterable, Sendable {
    case none
    case importSnapshot
    case acceptedBaseline
    case selectedParagraph

    var label: String {
        switch self {
        case .none: "Off"
        case .importSnapshot: "Import snapshot"
        case .acceptedBaseline: "Accepted baseline"
        case .selectedParagraph: "Current paragraph"
        }
    }
}

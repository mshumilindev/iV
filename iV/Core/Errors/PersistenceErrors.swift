import Foundation

enum PersistenceError: LocalizedError {
    case registryCorrupt(path: String, underlying: Error)
    case registrySaveFailed(path: String, underlying: Error)
    case storeReadFailed(resource: String, underlying: Error)
    case storeWriteFailed(resource: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .registryCorrupt(let path, let underlying):
            "Project library file is corrupt or unreadable at \(path). The file was not deleted. (\(underlying.localizedDescription))"
        case .registrySaveFailed(let path, let underlying):
            "Could not save project library at \(path). (\(underlying.localizedDescription))"
        case .storeReadFailed(let resource, let underlying):
            "Could not read \(resource). (\(underlying.localizedDescription))"
        case .storeWriteFailed(let resource, let underlying):
            "Could not save \(resource). (\(underlying.localizedDescription))"
        }
    }
}

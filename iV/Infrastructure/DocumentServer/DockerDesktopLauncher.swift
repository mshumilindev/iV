import AppKit
import Foundation

enum DockerDesktopLauncher {
    private static let applicationPaths = [
        "/Applications/Docker.app",
    ]

    static var isInstalled: Bool {
        applicationPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    @discardableResult
    static func openIfInstalled() -> Bool {
        guard let path = applicationPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return false
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        return true
    }
}

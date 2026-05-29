import AppKit
import Foundation

final class IVAppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        guard let appState else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await appState.shutdownEmbeddedOfficeIfNeeded()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 15)
    }
}

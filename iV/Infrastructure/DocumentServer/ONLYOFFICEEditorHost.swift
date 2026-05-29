import SwiftUI
import WebKit

/// Hosts ONLYOFFICE Document Server editor frame when a real DocsAPI session is available.
struct ONLYOFFICEEditorHost: NSViewRepresentable {
    let session: EmbeddedDocumentSessionReady?
    var onConnectionChange: (DocumentEditorConnectionState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onConnectionChange: onConnectionChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.userContentController.add(context.coordinator, name: Coordinator.messageHandlerName)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.setAccessibilityIdentifier("workspace.manuscript.office.frame")
        context.coordinator.loadEditor(in: webView, session: session)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let sessionKey = session?.documentKey
        if context.coordinator.lastSessionKey != sessionKey {
            context.coordinator.lastSessionKey = sessionKey
            context.coordinator.loadEditor(in: webView, session: session)
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageHandlerName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandlerName = "ivEditor"
        static let quarantinedHostHTML = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>body{margin:0;background:#1a211c;}</style></head><body></body></html>
        """

        var lastSessionKey: String?
        let onConnectionChange: (DocumentEditorConnectionState) -> Void

        init(onConnectionChange: @escaping (DocumentEditorConnectionState) -> Void) {
            self.onConnectionChange = onConnectionChange
        }

        func loadEditor(in webView: WKWebView, session: EmbeddedDocumentSessionReady?) {
            guard let session else {
                onConnectionChange(.unavailable("Editor session not ready."))
                webView.loadHTMLString(Self.quarantinedHostHTML, baseURL: nil)
                return
            }
            guard !session.editorHTML.isEmpty else {
                onConnectionChange(.unavailable("DocsAPI session HTML is missing."))
                webView.loadHTMLString(Self.quarantinedHostHTML, baseURL: nil)
                return
            }
            onConnectionChange(.connecting)
            webView.loadHTMLString(session.editorHTML, baseURL: URL(string: session.onlyOfficeServerURL))
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.messageHandlerName,
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }

            switch type {
            case "documentReady":
                onConnectionChange(.ready)
            case "loadError", "error":
                let msg = body["message"] as? String ?? "ONLYOFFICE editor failed to load."
                onConnectionChange(.error(msg))
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // `.ready` is emitted only from DocsAPI onDocumentReady — not from navigation alone.
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onConnectionChange(.error(error.localizedDescription))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onConnectionChange(.error(error.localizedDescription))
        }
    }
}

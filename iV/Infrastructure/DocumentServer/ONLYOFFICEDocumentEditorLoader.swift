import Foundation

/// Builds ONLYOFFICE DocsAPI `DocEditor` HTML for WKWebView embedding.
enum ONLYOFFICEDocumentEditorLoader {
    /// Returns HTML that loads `{serverURL}/web-apps/apps/api/documents/api.js` and initializes DocsAPI.DocEditor.
    /// Returns nil when Document Server URL is not localhost or required fields are missing.
    static func documentEditorHTML(
        serverURL: String,
        documentTitle: String,
        documentKey: String,
        documentFetchURL: String,
        callbackURL: String
    ) -> String? {
        guard case .success(let base) = DocumentServerConfiguration.validate(serverURL) else { return nil }
        guard !documentTitle.isEmpty, !documentKey.isEmpty, !documentFetchURL.isEmpty else { return nil }

        let apiScriptURL = base
            .appendingPathComponent("web-apps/apps/api/documents/api.js")
            .absoluteString

        let document: [String: Any] = [
            "fileType": "docx",
            "key": documentKey,
            "title": documentTitle,
            "url": documentFetchURL,
        ]
        let editorConfig: [String: Any] = [
            "mode": "edit",
            "callbackUrl": callbackURL,
            "lang": "en",
            "customization": [
                "forcesave": false,
                "compactHeader": true,
            ] as [String: Any],
        ]
        let config: [String: Any] = [
            "documentType": "word",
            "document": document,
            "editorConfig": editorConfig,
            "height": "100%",
            "width": "100%",
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let configJSON = String(data: jsonData, encoding: .utf8)
        else { return nil }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(documentTitle))</title>
          <script src="\(escapeHTML(apiScriptURL))"></script>
          <style>
            html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; background: #fff; }
            #editor { height: 100vh; width: 100vw; }
          </style>
        </head>
        <body>
          <div id="editor"></div>
          <script>
            (function() {
              function post(type, message) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ivEditor) {
                  window.webkit.messageHandlers.ivEditor.postMessage({ type: type, message: message || null });
                }
              }
              window.addEventListener('load', function() {
                if (typeof DocsAPI === 'undefined') {
                  post('loadError', 'ONLYOFFICE DocsAPI script did not load from Document Server.');
                  return;
                }
                var config = \(configJSON);
                config.events = {
                  onDocumentReady: function() { post('documentReady'); },
                  onError: function(event) {
                    var msg = (event && event.data) ? String(event.data) : 'ONLYOFFICE editor error';
                    post('error', msg);
                  }
                };
                try {
                  new DocsAPI.DocEditor('editor', config);
                } catch (err) {
                  post('loadError', err && err.message ? err.message : 'DocsAPI.DocEditor failed to initialize.');
                }
              });
            })();
          </script>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

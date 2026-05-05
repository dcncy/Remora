import AppKit
import SwiftUI
import WebKit

private final class FocusableWKWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

struct RemoraEditorWebView: NSViewRepresentable {
    var document: EditorDocument
    var saveRequestID: Int = 0
    var contentVersion: Int = 0
    var syncMode: EditorTextSyncMode = .continuous
    var autoScrollToBottom: Bool = false
    var onReady: (() -> Void)? = nil
    var onChange: ((Int) -> Void)? = nil
    var onTextChange: ((String) -> Void)? = nil
    var onSaveRequested: ((String) -> Void)? = nil
    var onError: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "remoraEditor")
        configuration.userContentController = userContentController

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        do {
            let html = try Self.inlineEditorHTML()
            webView.loadHTMLString(html, baseURL: nil)
        } catch {
            assertionFailure("Failed to build inline editor HTML: \(error.localizedDescription)")
            onError?("Failed to load editor resources: \(error.localizedDescription)")
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        EditorDebugLog.log("updateNSView ready=\(context.coordinator.debugIsReady) saveRequestID=\(saveRequestID) contentVersion=\(contentVersion) syncMode=\(syncMode)")
        context.coordinator.updateIfNeeded()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private enum TextRequestReason {
            case change
            case save
        }

        var parent: RemoraEditorWebView
        weak var webView: WKWebView?

        private var isReady = false
        private var lastAppliedDocument: EditorDocument?
        private var lastAppliedContentVersion: Int?
        private var lastAppliedTheme: String?
        private var lastProcessedSaveRequestID = 0
        private var isFetchingText = false
        private var pendingChangeFetch = false

        init(parent: RemoraEditorWebView) {
            self.parent = parent
        }

        var debugIsReady: Bool {
            isReady
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "remoraEditor" else { return }

            do {
                let data = try JSONSerialization.data(withJSONObject: message.body)
                let decoded = try JSONDecoder().decode(EditorBridgeMessage.self, from: data)
                EditorDebugLog.log("bridge <- \(decoded.type.rawValue) rev=\(decoded.revision.map(String.init) ?? "-") from=\(decoded.from.map(String.init) ?? "-") to=\(decoded.to.map(String.init) ?? "-") msg=\(decoded.message ?? "-")")
                handle(decoded)
            } catch {
                parent.onError?("Failed to decode editor bridge message: \(error.localizedDescription)")
            }
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            EditorDebugLog.log("didFinish navigation firstResponder=\(String(describing: webView.window?.firstResponder))")
            webView.evaluateJavaScript("window.RemoraEditor.focus()")
            updateIfNeeded()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.onError?("Editor navigation failed: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.onError?("Editor provisional navigation failed: \(error.localizedDescription)")
        }

        func updateIfNeeded() {
            guard isReady else { return }

            applyDocumentIfNeeded(parent.document, contentVersion: parent.contentVersion)
            applyThemeIfNeeded()

            if parent.saveRequestID != lastProcessedSaveRequestID {
                lastProcessedSaveRequestID = parent.saveRequestID
                EditorDebugLog.log("requestText(save) saveRequestID=\(parent.saveRequestID)")
                requestText(reason: .save)
            }
        }

        private func handle(_ message: EditorBridgeMessage) {
            switch message.type {
            case .ready:
                isReady = true
                updateIfNeeded()
                parent.onReady?()

            case .change:
                parent.onChange?(message.revision ?? 0)
                guard parent.syncMode == .continuous else { return }
                requestText(reason: .change)

            case .selectionChange:
                if parent.syncMode == .continuous {
                    break
                }
                return

            case .debug:
                if let message = message.message {
                    EditorDebugLog.log("js.debug \(message)")
                }
                return

            case .saveRequested:
                requestText(reason: .save)

            case .error:
                parent.onError?(message.message ?? "Unknown editor error")
            }
        }

        private func applyDocumentIfNeeded(_ document: EditorDocument, contentVersion: Int) {
            guard let previous = lastAppliedDocument else {
                setDocument(document, contentVersion: contentVersion)
                return
            }

            let externalContentChanged = lastAppliedContentVersion != contentVersion
            let textChanged = previous.text != document.text
            let configChanged =
                previous.path != document.path ||
                previous.language != document.language ||
                previous.isEditable != document.isEditable ||
                previous.lineWrapping != document.lineWrapping

            let shouldApplyText = parent.syncMode == .continuous
                ? textChanged
                : (externalContentChanged && textChanged)

            EditorDebugLog.log("applyDocumentIfNeeded externalContentChanged=\(externalContentChanged) textChanged=\(textChanged) configChanged=\(configChanged) shouldApplyText=\(shouldApplyText) contentVersion=\(contentVersion) lastAppliedContentVersion=\(lastAppliedContentVersion.map(String.init) ?? "-")")

            guard shouldApplyText || configChanged else { return }

            if shouldApplyText || configChanged {
                setDocument(document, contentVersion: contentVersion)
            }
        }

        private func setDocument(_ document: EditorDocument, contentVersion: Int) {
            EditorDebugLog.log("setDocument path=\(document.path ?? "-") chars=\(document.text.count) contentVersion=\(contentVersion) editable=\(document.isEditable)")
            let payload: [String: Any] = [
                "text": document.text,
                "path": document.path ?? "",
                "language": document.language.rawValue,
                "isEditable": document.isEditable,
                "lineWrapping": document.lineWrapping
            ]

            call("window.RemoraEditor.setDocument", argument: payload) { [weak self] in
                guard let self else { return }
                self.lastAppliedDocument = document
                self.lastAppliedContentVersion = contentVersion
                if self.parent.autoScrollToBottom {
                    self.call("window.RemoraEditor.scrollToBottom")
                }
            }
        }

        private func applyThemeIfNeeded() {
            guard let webView else { return }
            let theme = webView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? "dark"
                : "light"

            guard theme != lastAppliedTheme else { return }
            lastAppliedTheme = theme
            EditorDebugLog.log("setTheme \(theme)")
            call("window.RemoraEditor.setTheme", argument: theme)
        }

        private func requestText(reason: TextRequestReason) {
            guard let webView else { return }
            guard !isFetchingText else {
                if reason == .change {
                    pendingChangeFetch = true
                }
                return
            }

            isFetchingText = true
            webView.evaluateJavaScript("window.RemoraEditor.getText()") { [weak self] result, error in
                guard let self else { return }
                self.isFetchingText = false

                if let error {
                    self.parent.onError?("Editor getText failed: \(error.localizedDescription)")
                    return
                }

                let text = result as? String ?? ""
                EditorDebugLog.log("getText reason=\(reason == .save ? "save" : "change") chars=\(text.count)")
                if var applied = self.lastAppliedDocument {
                    applied.text = text
                    self.lastAppliedDocument = applied
                }

                switch reason {
                case .change:
                    self.parent.onTextChange?(text)
                    if self.pendingChangeFetch {
                        self.pendingChangeFetch = false
                        self.requestText(reason: .change)
                    }
                case .save:
                    self.parent.onSaveRequested?(text)
                }
            }
        }

        private func call(_ function: String, completion: (() -> Void)? = nil) {
            EditorDebugLog.log("js -> \(function)()")
            webView?.evaluateJavaScript("\(function)()") { _, _ in
                completion?()
            }
        }

        private func call(_ function: String, argument: String, completion: (() -> Void)? = nil) {
            let wrapped = [argument]
            guard let data = try? JSONSerialization.data(withJSONObject: wrapped),
                  let jsonArray = String(data: data, encoding: .utf8),
                  jsonArray.count >= 2
            else {
                return
            }

            let json = String(jsonArray.dropFirst().dropLast())

            EditorDebugLog.log("js -> \(function)(String)")
            webView?.evaluateJavaScript("\(function)(\(json))") { _, error in
                if let error {
                    self.parent.onError?("Editor JS call failed: \(error.localizedDescription)")
                }
                completion?()
            }
        }

        private func call(_ function: String, argument: [String: Any], completion: (() -> Void)? = nil) {
            guard let data = try? JSONSerialization.data(withJSONObject: argument),
                  let json = String(data: data, encoding: .utf8)
            else {
                return
            }

            EditorDebugLog.log("js -> \(function)(Object)")
            webView?.evaluateJavaScript("\(function)(\(json))") { _, error in
                if let error {
                    self.parent.onError?("Editor JS call failed: \(error.localizedDescription)")
                }
                completion?()
            }
        }
    }

    private static func inlineEditorHTML() throws -> String {
        let bundle = Bundle.module

        func loadResource(named name: String, extension ext: String) throws -> String {
            let directURL = bundle.url(forResource: name, withExtension: ext, subdirectory: "WebEditor")
                ?? bundle.url(forResource: name, withExtension: ext)
            guard let url = directURL else {
                throw NSError(domain: "RemoraEditorWebView", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Missing \(name).\(ext) in bundle resources"
                ])
            }
            return try String(contentsOf: url, encoding: .utf8)
        }

        let css = try loadResource(named: "editor", extension: "css")
        let js = try loadResource(named: "editor", extension: "js")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
          <title>Remora Editor</title>
          <style>\(css)</style>
        </head>
        <body>
          <div id="editor"></div>
          <script>\(js)</script>
        </body>
        </html>
        """
    }
}

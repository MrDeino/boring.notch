import SwiftUI
import WebKit

/// Phase 3 terminal key gate. Phase 2 adds OrchestratorManager.wantsKeyboard; merged canBecomeKey ORs both.
@MainActor
enum OrchestratorKeyGate {
    nonisolated(unsafe) static var terminalWantsKey = false
}

/// ttyd page at /term/ inside the expanded notch. Created on expand, torn down (about:blank) on collapse.
struct OrchestratorTerminalView: NSViewRepresentable {
    @Binding var state: TerminalState

    func makeCoordinator() -> Coordinator { Coordinator(state: $state) }

    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        w.setValue(false, forKey: "drawsBackground")
        w.navigationDelegate = context.coordinator
        w.load(URLRequest(url: URL(string: "http://127.0.0.1:4777/term/")!))
        return w
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.poll?.cancel()
        nsView.stopLoading()
        nsView.load(URLRequest(url: URL(string: "about:blank")!)) // releases ttyd's single client slot
        OrchestratorExpand.shared.releaseKey(nsView.window)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var state: Binding<TerminalState>
        var poll: Task<Void, Never>?
        init(state: Binding<TerminalState>) { self.state = state }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let u = navigationAction.request.url
            let ok = u?.absoluteString == "about:blank" || (u?.host == "127.0.0.1" && u?.port == 4777)
            decisionHandler(ok ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let h = navigationResponse.response as? HTTPURLResponse, h.statusCode != 200 {
                state.wrappedValue = .unavailable
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { state.wrappedValue = .unavailable }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // Cancelled non-200 responses land here too; they already set .unavailable.
            if (error as NSError).code != NSURLErrorCancelled { state.wrappedValue = .unavailable }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView.url?.host == "127.0.0.1" else { return }
            state.wrappedValue = .connecting
            OrchestratorKeyGate.terminalWantsKey = true
            webView.window?.makeKey()
            webView.window?.makeFirstResponder(webView)
            poll?.cancel()
            poll = Task { [weak webView] in
                for _ in 0..<5 {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let webView else { return }
                    let text = try? await webView.evaluateJavaScript("document.body.innerText") as? String
                    let s = terminalState(pageText: text)
                    state.wrappedValue = s
                    if s == .inUse { return }
                }
            }
        }
    }
}

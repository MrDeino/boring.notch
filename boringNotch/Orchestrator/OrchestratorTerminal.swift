import SwiftUI
import WebKit

/// Phase 3 terminal key gate. Phase 2 adds OrchestratorManager.wantsKeyboard; merged canBecomeKey ORs both.
@MainActor
enum OrchestratorKeyGate {
    nonisolated(unsafe) static var terminalWantsKey = false
    private static var previousApp: NSRunningApplication?

    /// The notch is a non-activating panel of an app that is never active, so a key panel still
    /// doesn't get keystrokes. Activate while the message box or terminal has focus; restore() hands it back.
    static func activate() {
        if let a = NSWorkspace.shared.frontmostApplication, a != NSRunningApplication.current { previousApp = a }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// refocus false = the user clicked another app, which already took focus.
    static func restore(refocus: Bool = true) {
        if refocus, NSApp.isActive { previousApp?.activate() }
        previousApp = nil
    }
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
        nsView.navigationDelegate = nil
        nsView.stopLoading()
        // Best effort; ttyd's single client slot is really freed when WebKit closes the page on dealloc.
        nsView.load(URLRequest(url: URL(string: "about:blank")!))
        OrchestratorExpand.shared.releaseKey(nsView.window)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var state: Binding<TerminalState>
        var poll: Task<Void, Never>?
        init(state: Binding<TerminalState>) { self.state = state }

        /// Text of leaf divs outside xterm's rows (ttyd's overlay has no class); null until xterm exists.
        static let overlayJS = """
        (() => { if (!document.querySelector('.xterm')) return null;
          return [...document.querySelectorAll('div')]
            .filter(d => !d.childElementCount && !d.closest('.xterm-rows, .xterm-accessibility'))
            .map(d => d.textContent).join('\\n'); })()
        """

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
            OrchestratorKeyGate.activate()
            webView.window?.makeKey()
            webView.window?.makeFirstResponder(webView)
            poll?.cancel()
            // Polls for as long as the terminal is shown (cancelled in dismantleNSView), so later drops are caught.
            poll = Task { [weak webView] in
                var first = true
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(first ? 1 : 2))
                    first = false
                    guard !Task.isCancelled, let webView else { return }
                    let text = try? await webView.evaluateJavaScript(Self.overlayJS) as? String
                    let s = terminalState(overlayText: text, previous: state.wrappedValue)
                    state.wrappedValue = s
                    if s == .inUse || s == .unavailable { return }
                }
            }
        }
    }
}

/// Frame 10: framed terminal with toolbar. Mounted only at level .terminal, so the WebView exists only then.
struct OrchestratorTerminalPanel: View {
    @EnvironmentObject var vm: BoringViewModel
    @State private var termState: TerminalState = .connecting
    @State private var termID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(OT.C.green).frame(width: 6, height: 6)
                Text("Terminal · keyboard captured")
                Spacer()
                Button { OrchestratorExpand.shared.setLevel(.expanded, vm: vm, window: nil) } label: {
                    Text("Collapse ⌃").foregroundStyle(OT.C.text).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(OT.C.raised, in: RoundedRectangle(cornerRadius: OT.R.cardS))
                }.buttonStyle(.plain)
            }
            .font(.system(size: 11)).foregroundStyle(OT.C.text5)
            .padding(.horizontal, 10).padding(.vertical, 6)
            Rectangle().fill(OT.C.divider).frame(height: 1)
            if termState == .connecting || termState == .connected {
                OrchestratorTerminalView(state: $termState).id(termID)
            } else {
                VStack(spacing: 8) {
                    Text(termState == .inUse ? "Terminal in use" : "Terminal unavailable")
                        .font(.system(size: 12)).foregroundStyle(OT.C.text)
                    Button { termState = .connecting; termID = UUID() } label: {
                        Text("Retry").font(.system(size: 11)).foregroundStyle(OT.C.text)
                            .padding(.horizontal, 12).padding(.vertical, 4).background(OT.C.raised, in: Capsule())
                    }.buttonStyle(.plain)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(OT.C.terminal)
        .clipShape(RoundedRectangle(cornerRadius: OT.R.cardL))
        .overlay(RoundedRectangle(cornerRadius: OT.R.cardL).strokeBorder(OT.C.divider, lineWidth: 1))
    }
}

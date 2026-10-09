import SwiftUI
import AppKit
import CodeMirror
import WebKit

/// SwiftUI wrapper around CodeMirror (WebKit-based) editor.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    var minHeight: CGFloat = 0
    var colors: DesignSystem.ColorPalette?

    @Environment(\.colorScheme) var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CodeMirrorContainerView {
        let container = CodeMirrorContainerView(minHeight: minHeight)
        context.coordinator.attach(webView: container.webView)
        configure(container.webView, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: CodeMirrorContainerView, context: Context) {
        nsView.minHeight = minHeight
        context.coordinator.parent = self
        context.coordinator.attach(webView: nsView.webView)
        

        configure(nsView.webView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: CodeMirrorContainerView, coordinator: Coordinator) {
        coordinator.detach(webView: nsView.webView)
        nsView.cleanup()
    }

    private func configure(_ webView: CodeMirrorWebView, coordinator: Coordinator) {
        coordinator.syncConfiguration(
            webView: webView,
            text: text,
            isEditable: isEditable,
            isDarkMode: colorScheme == .dark,
            appearance: CodeEditorAppearance(colors: colors ?? DesignSystem.Colors.palette(colorScheme))
        )
    }
}

// MARK: - Coordinator

final class Coordinator: NSObject, CodeMirrorWebViewDelegate {
    var parent: CodeEditorView
    private var isSyncingFromParent = false
    private var lastAppliedText: String = ""
    private var didConfigureEditor = false
    private var lastFontSize: Int?
    private var lastReadonly: Bool?
    private var lastDarkMode: Bool?
    private var lastAppearance: CodeEditorAppearance?
    private var isEditorLoaded = false
    private weak var registeredWebView: CodeMirrorWebView?

    init(parent: CodeEditorView) {
        self.parent = parent
    }

    func attach(webView: CodeMirrorWebView) {
        if registeredWebView !== webView {
            if let registeredWebView {
                CodeMirrorShortcutCenter.shared.unregister(webView: registeredWebView)
            }
            CodeMirrorShortcutCenter.shared.register(webView: webView)
            registeredWebView = webView
            didConfigureEditor = false
            lastFontSize = nil
            lastReadonly = nil
            lastDarkMode = nil
            lastAppearance = nil
            isEditorLoaded = false
        }
        
        webView.delegate = self
    }

    func detach(webView: CodeMirrorWebView) {
        if registeredWebView === webView {
            CodeMirrorShortcutCenter.shared.unregister(webView: webView)
            registeredWebView = nil
        }
        if webView.delegate === self {
            webView.delegate = nil
        }
    }

    deinit {
        if let registeredWebView {
            CodeMirrorShortcutCenter.shared.unregister(webView: registeredWebView)
        }
    }

    func syncConfiguration(
        webView: CodeMirrorWebView,
        text: String,
        isEditable: Bool,
        isDarkMode: Bool,
        appearance: CodeEditorAppearance
    ) {
        if !didConfigureEditor {
            webView.setLineWrapping(true)
            webView.setTabInsertsSpaces(true)
            webView.setMimeType("application/json")
            didConfigureEditor = true
        }

        let fontSize = Int(DesignSystem.Metrics.font(13).rounded())
        if lastFontSize != fontSize {
            webView.setFontSize(fontSize)
            lastFontSize = fontSize
        }
        if lastReadonly != !isEditable {
            webView.setReadonly(!isEditable)
            lastReadonly = !isEditable
        }
        if lastDarkMode != isDarkMode {
            webView.setDarkTheme(isDarkMode)
            lastDarkMode = isDarkMode
        }
        if isEditorLoaded, lastAppearance != appearance {
            lastAppearance = appearance
            webView.webview.callAsyncJavaScript(
                """
                let style = document.getElementById('frtm-editor-theme');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'frtm-editor-theme';
                    document.head.appendChild(style);
                }
                style.textContent = css;
                """,
                arguments: ["css": appearance.css], in: nil, in: .page
            ) { result in
                if case let .failure(error) = result {
                    NSLog("CodeMirror theme failed: \(error.localizedDescription)")
                }
            }
        }

        if lastAppliedText != text {
            isSyncingFromParent = true
            lastAppliedText = text
            webView.setContent(text, beautifyMode: .none)
        }
    }

    // MARK: CodeMirrorWebViewDelegate

    func codeMirrorViewDidLoadSuccess(_ sender: CodeMirrorWebView) {
        isEditorLoaded = true
        lastAppearance = nil
        syncConfiguration(
            webView: sender,
            text: parent.text,
            isEditable: parent.isEditable,
            isDarkMode: parent.colorScheme == .dark,
            appearance: CodeEditorAppearance(colors: parent.colors ?? DesignSystem.Colors.palette(parent.colorScheme))
        )
    }

    func codeMirrorViewDidLoadError(_ sender: CodeMirrorWebView, error: Error) {
        NSLog("CodeMirror load failed: \(error.localizedDescription)")
    }

    func codeMirrorViewDidChangeContent(_ sender: CodeMirrorWebView, content: String) {
        if isSyncingFromParent {
            isSyncingFromParent = false
            return
        }

        guard parent.text != content else { return }
        DispatchQueue.main.async {
            self.lastAppliedText = content
            self.parent.text = content
        }
    }
}

// MARK: - Container view to control intrinsic height

final class CodeMirrorContainerView: NSView {
    let webView: CodeMirrorWebView
    var minHeight: CGFloat {
        didSet {
            heightConstraint?.constant = minHeight
            invalidateIntrinsicContentSize()
        }
    }
    private var heightConstraint: NSLayoutConstraint?

    init(minHeight: CGFloat) {
        self.minHeight = minHeight
        self.webView = CodeMirrorWebView()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: minHeight)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        heightConstraint = webView.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint!
        ])
    }

    func cleanup() {
        guard let wkWebView = findWKWebView(in: webView) else { return }
        let controller = wkWebView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "codeMirrorDidReady")
        controller.removeScriptMessageHandler(forName: "codeMirrorTextContentDidChange")
        wkWebView.navigationDelegate = nil
        wkWebView.uiDelegate = nil
        wkWebView.stopLoading()
        wkWebView.loadHTMLString("", baseURL: nil)
    }

    private func findWKWebView(in view: NSView) -> WKWebView? {
        if let wkWebView = view as? WKWebView {
            return wkWebView
        }
        for subview in view.subviews {
            if let match = findWKWebView(in: subview) {
                return match
            }
        }
        return nil
    }
}

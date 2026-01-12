import SwiftUI
import AppKit
import CodeMirror

/// SwiftUI wrapper around CodeMirror (WebKit-based) editor.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    var minHeight: CGFloat = 0

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

    private func configure(_ webView: CodeMirrorWebView, coordinator: Coordinator) {
        coordinator.syncConfiguration(
            webView: webView,
            text: text,
            isEditable: isEditable,
            isDarkMode: colorScheme == .dark
        )
    }
}

// MARK: - Coordinator

final class Coordinator: NSObject, CodeMirrorWebViewDelegate {
    var parent: CodeEditorView
    private var isSyncingFromParent = false
    private var lastAppliedText: String = ""
    private var didConfigureEditor = false
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
        }
        
        webView.delegate = self
        didConfigureEditor = false
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
        isDarkMode: Bool
    ) {
        if !didConfigureEditor {
            webView.setLineWrapping(true)
            webView.setTabInsertsSpaces(true)
            webView.setFontSize(13)
            webView.setMimeType("application/json")
            didConfigureEditor = true
        }

        webView.setReadonly(!isEditable)
        webView.setDarkTheme(isDarkMode)

        if lastAppliedText != text {
            isSyncingFromParent = true
            lastAppliedText = text
            webView.setContent(text, beautifyMode: .none)
        }
    }

    // MARK: CodeMirrorWebViewDelegate

    func codeMirrorViewDidLoadSuccess(_ sender: CodeMirrorWebView) {
        syncConfiguration(
            webView: sender,
            text: parent.text,
            isEditable: parent.isEditable,
            isDarkMode: parent.colorScheme == .dark
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
}

import AppKit
import CodeMirror

/// Manages global shortcuts for CodeMirror editors so we can hook them to macOS commands.
final class CodeMirrorShortcutCenter {
    static let shared = CodeMirrorShortcutCenter()

    private let editors = NSHashTable<CodeMirrorWebView>.weakObjects()
    private var searchPresentationState: [ObjectIdentifier: Bool] = [:]

    private init() {}

    func register(webView: CodeMirrorWebView) {
        guard editors.allObjects.contains(where: { $0 === webView }) == false else { return }
        editors.add(webView)
        searchPresentationState[ObjectIdentifier(webView)] = false
    }

    func unregister(webView: CodeMirrorWebView) {
        editors.remove(webView)
        searchPresentationState.removeValue(forKey: ObjectIdentifier(webView))
    }

    func focusSearchInActiveEditor() {
        guard let editor = preferredEditor() else { return }
        let key = ObjectIdentifier(editor)
        editor.toggleFilterBar()
        let isShown = searchPresentationState[key] ?? false
        searchPresentationState[key] = !isShown
    }

    private func preferredEditor() -> CodeMirrorWebView? {
        let allEditors = editors.allObjects
        guard !allEditors.isEmpty else { return nil }

        guard let keyWindow = NSApp.keyWindow else {
            return allEditors.last
        }
        let responderView = keyWindow.firstResponder as? NSView
        let sameWindowEditors = allEditors.filter { $0.window === keyWindow }

        if let responderView {
            if let matching = sameWindowEditors.first(where: { responderView.isDescendant(of: $0) }) {
                return matching
            }
        }

        return sameWindowEditors.last ?? allEditors.last
    }
}

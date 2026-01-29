import AppKit
import SwiftUI

struct ShareAnchorView: NSViewRepresentable {
    let onResolve: @MainActor (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor in
            onResolve(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            onResolve(nsView)
        }
    }
}


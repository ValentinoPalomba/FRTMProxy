import AppKit
import Foundation
import UniformTypeIdentifiers

enum CaptureBodyExporter {
    @MainActor
    static func export(reference: String, flowID: String, phase: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(phase)-body.bin"
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    let bytes = try CaptureBodyStore.load(reference: reference, flowID: flowID, phase: phase)
                    try bytes.write(to: destination, options: .atomic)
                }.value
            } catch {
                let alert = NSAlert()
                alert.messageText = "Unable to export original body"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}

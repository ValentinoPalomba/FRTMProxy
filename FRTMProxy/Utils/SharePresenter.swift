import AppKit

@MainActor
enum SharePresenter {
    private static var activePicker: NSSharingServicePicker?

    static func normalizedItems(_ items: [Any]) -> [Any] {
        items.compactMap { item in
            if let string = item as? String {
                return string as NSString
            }
            if let url = item as? URL {
                return url as NSURL
            }
            return item
        }
    }

    static func availableServiceTitles(for items: [Any]) -> [String] {
        let normalized = normalizedItems(items)
        return NSSharingService.sharingServices(forItems: normalized)
            .compactMap(\.title)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func present(items: [Any], from view: NSView? = nil) {
        let normalized = normalizedItems(items)
        guard !normalized.isEmpty else { return }
        let anchorView = view ?? NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView
        guard let anchorView, anchorView.window != nil else { return }

        let picker = NSSharingServicePicker(items: normalized)
        activePicker = picker

        Task { @MainActor in
            let rect = CGRect(
                x: 0,
                y: 0,
                width: max(1, anchorView.bounds.width),
                height: max(1, anchorView.bounds.height)
            )
            picker.show(relativeTo: rect, of: anchorView, preferredEdge: .minY)
        }

        Task {
            try? await Task.sleep(for: .seconds(2))
            if activePicker === picker {
                activePicker = nil
            }
        }
    }
}

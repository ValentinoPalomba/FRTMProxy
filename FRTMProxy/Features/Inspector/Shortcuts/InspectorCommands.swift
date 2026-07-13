import SwiftUI

struct InspectorCommands {
    var isRunning: Bool
    var hasSelection: Bool
    var toggleProxy: () -> Void
    var clear: () -> Void
    var openCommandPalette: () -> Void
    var mapLocal: () -> Void
    var retry: () -> Void
    var copyURL: () -> Void
    var copyCurl: () -> Void
}

struct InspectorCommandsKey: FocusedValueKey {
    typealias Value = InspectorCommands
}

extension FocusedValues {
    var inspectorCommands: InspectorCommands? {
        get { self[InspectorCommandsKey.self] }
        set { self[InspectorCommandsKey.self] = newValue }
    }
}

struct InspectorCommandsMenu: Commands {
    @FocusedValue(\.inspectorCommands) private var commands

    var body: some Commands {
        CommandMenu("Proxy") {
            Button(commands?.isRunning == true ? "Stop Proxy" : "Start Proxy") {
                commands?.toggleProxy()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(commands == nil)

            Button("Clear Flows") { commands?.clear() }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(commands == nil)

            Divider()

            Button("Command Palette…") { commands?.openCommandPalette() }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(commands == nil)

            Divider()

            Button("Map Local…") { commands?.mapLocal() }
                .keyboardShortcut("m", modifiers: [.command, .option])
                .disabled(commands?.hasSelection != true)

            Button("Retry Request…") { commands?.retry() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(commands?.hasSelection != true)

            Button("Copy URL") { commands?.copyURL() }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(commands?.hasSelection != true)

            Button("Copy as cURL") { commands?.copyCurl() }
                .keyboardShortcut("y", modifiers: [.command, .option])
                .disabled(commands?.hasSelection != true)
        }
    }
}

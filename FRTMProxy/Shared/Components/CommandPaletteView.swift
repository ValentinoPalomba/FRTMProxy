import SwiftUI

struct CommandPaletteAction: Identifiable, Equatable {
    static func == (lhs: CommandPaletteAction, rhs: CommandPaletteAction) -> Bool {
        lhs.id == rhs.id
    }
    
    let id = UUID()
    let title: String
    let subtitle: String?
    let systemImage: String?
    let shortcut: String?
    let keywords: [String]
    let isEnabled: Bool
    let handler: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        shortcut: String? = nil,
        keywords: [String] = [],
        isEnabled: Bool = true,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.keywords = keywords
        self.isEnabled = isEnabled
        self.handler = handler
    }
}

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    let actions: [CommandPaletteAction]
    let colors: DesignSystem.ColorPalette

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    private var filteredActions: [CommandPaletteAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return actions }
        let tokens = trimmed.lowercased().split(separator: " ").map(String.init)
        return actions.filter { action in
            let haystack = ([action.title, action.subtitle ?? ""] + action.keywords).joined(separator: " ").lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .foregroundStyle(colors.textSecondary)
                    TextField("Type a command…", text: $query)
                        .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                        .focused($isSearchFocused)
                        .onSubmit { runSelectedAction() }
                }

                Divider()
                    .overlay(colors.border.opacity(0.7))

                if filteredActions.isEmpty {
                    VStack(spacing: 6) {
                        Text("No matching commands")
                            .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                            .foregroundStyle(colors.textSecondary)
                        Text("Try different keywords.")
                            .font(DesignSystem.Fonts.sans(11))
                            .foregroundStyle(colors.textSecondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, action in
                                    CommandPaletteRow(
                                        action: action,
                                        isSelected: index == selectedIndex,
                                        colors: colors
                                    )
                                    .id(action.id)
                                    .onTapGesture {
                                        selectedIndex = index
                                        runSelectedAction()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 320)
                        .onChange(of: selectedIndex) { _, _ in
                            guard !filteredActions.isEmpty else { return }
                            let clamped = min(max(selectedIndex, 0), filteredActions.count - 1)
                            let targetID = filteredActions[clamped].id
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(targetID, anchor: .center)
                            }
                        }
                        .onChange(of: filteredActions) { _, _ in
                            guard !filteredActions.isEmpty else { return }
                            let clamped = min(max(selectedIndex, 0), filteredActions.count - 1)
                            let targetID = filteredActions[clamped].id
                            proxy.scrollTo(targetID, anchor: .center)
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 520)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colors.surface)
                    .shadow(color: Color.black.opacity(0.25), radius: 18, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(colors.border, lineWidth: 1)
            )
            .onAppear {
                selectedIndex = 0
                isSearchFocused = true
            }
            .onChange(of: filteredActions) { _, _ in
                selectedIndex = 0
            }
            .onChange(of: query) { _, _ in
                selectedIndex = 0
            }
            .onMoveCommand { direction in
                guard !filteredActions.isEmpty else { return }
                switch direction {
                case .down:
                    selectedIndex = min(selectedIndex + 1, filteredActions.count - 1)
                case .up:
                    selectedIndex = max(selectedIndex - 1, 0)
                default:
                    break
                }
            }
            .onExitCommand {
                isPresented = false
            }
            .background(
                KeyEventMonitorView { event in
                    handleKeyEvent(event)
                }
            )
        }
    }

    private func runSelectedAction() {
        guard !filteredActions.isEmpty else { return }
        let action = filteredActions[min(selectedIndex, filteredActions.count - 1)]
        guard action.isEnabled else { return }
        isPresented = false
        action.handler()
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard isPresented else { return false }
        guard !filteredActions.isEmpty else {
            if event.keyCode == 53 { // escape
                isPresented = false
                return true
            }
            return false
        }

        switch event.keyCode {
        case 125: // down
            selectedIndex = min(selectedIndex + 1, filteredActions.count - 1)
            return true
        case 126: // up
            selectedIndex = max(selectedIndex - 1, 0)
            return true
        case 36: // return
            runSelectedAction()
            return true
        case 48: // tab
            if event.modifierFlags.contains(.shift) {
                selectedIndex = max(selectedIndex - 1, 0)
            } else {
                selectedIndex = min(selectedIndex + 1, filteredActions.count - 1)
            }
            return true
        case 53: // escape
            isPresented = false
            return true
        default:
            return false
        }
    }
}

private struct CommandPaletteRow: View {
    let action: CommandPaletteAction
    let isSelected: Bool
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: 12) {
            if let icon = action.systemImage {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                    .foregroundStyle(textColor)
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Fonts.sans(11))
                        .foregroundStyle(colors.textSecondary)
                }
            }

            Spacer()

            if let shortcut = action.shortcut {
                Text(shortcut)
                    .font(DesignSystem.Fonts.mono(11, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(colors.surfaceElevated)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? colors.accent.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? colors.accent.opacity(0.7) : Color.clear, lineWidth: 1)
        )
        .opacity(action.isEnabled ? 1 : 0.5)
    }

    private var iconColor: Color {
        action.isEnabled ? colors.accent : colors.textSecondary
    }

    private var textColor: Color {
        action.isEnabled ? colors.textPrimary : colors.textSecondary
    }
}

private struct KeyEventMonitorView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(onKeyDown: onKeyDown)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    final class Coordinator {
        var onKeyDown: (NSEvent) -> Bool
        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
        }

        func installMonitor(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.onKeyDown(event) ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

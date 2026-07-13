import SwiftUI

// MARK: - FlowDiffView

struct FlowDiffView: View {
    let flowA: MitmFlow
    let flowB: MitmFlow
    let colors: DesignSystem.ColorPalette
    let onClose: () -> Void

    @State private var selectedSection: DiffSection = .responseBody

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "square.on.square")
                    .font(.system(size: DesignSystem.Metrics.scaled(16), weight: .semibold))
                    .foregroundStyle(colors.accent)
                Text("Compare flows")
                    .font(DesignSystem.Fonts.sans(15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors)) { onClose() }
            }
            .padding(DesignSystem.Spacing.lg)
            .background(colors.surfaceElevated)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(colors.border.opacity(0.7)),
                alignment: .bottom
            )

            // Section picker — wrapped in horizontal scroll so it doesn't clip at narrow widths
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(DiffSection.allCases, id: \.self) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            Text(section.label)
                                .font(DesignSystem.Fonts.sans(12, weight: selectedSection == section ? .semibold : .medium))
                                .foregroundStyle(selectedSection == section ? colors.textPrimary : colors.textSecondary)
                                .padding(.horizontal, DesignSystem.Spacing.md)
                                .padding(.vertical, DesignSystem.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                                        .fill(selectedSection == section ? colors.surfaceElevated : colors.surface.opacity(0.4))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                                        .stroke(
                                            selectedSection == section ? colors.border.opacity(0.9) : colors.border.opacity(0.4),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(colors.surface)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(colors.border.opacity(0.5)),
                alignment: .bottom
            )

            // Side-by-side diff
            HStack(spacing: 0) {
                DiffColumn(flowA: flowA, flowB: flowB, section: selectedSection, side: .a, colors: colors)
                    .frame(maxWidth: .infinity)
                Divider()
                    .overlay(colors.border.opacity(0.7))
                DiffColumn(flowA: flowA, flowB: flowB, section: selectedSection, side: .b, colors: colors)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(colors.surface)
    }
}

// MARK: - DiffColumn

private struct DiffColumn: View {
    let flowA: MitmFlow
    let flowB: MitmFlow
    let section: DiffSection
    let side: DiffSide
    let colors: DesignSystem.ColorPalette

    private var flow: MitmFlow { side == .a ? flowA : flowB }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader
            diffContent
        }
    }

    private var columnHeader: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text(side == .a ? "A" : "B")
                .font(DesignSystem.Fonts.mono(11, weight: .bold))
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xxs)
                .background(Capsule().fill(colors.accent.opacity(0.15)))
                .foregroundStyle(colors.accent)
            if let method = flow.request?.method {
                Text(method.uppercased())
                    .font(DesignSystem.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.methodColor(method, palette: colors))
            }
            Text(flow.host + flow.path)
                .font(DesignSystem.Fonts.mono(11))
                .foregroundStyle(colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceElevated)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(colors.border.opacity(0.5)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var diffContent: some View {
        let linesA = sectionContent(flow: flowA).components(separatedBy: "\n")
        let linesB = sectionContent(flow: flowB).components(separatedBy: "\n")
        // Show only this side's column from DiffLinesView
        DiffColumnContent(
            linesA: linesA,
            linesB: linesB,
            side: side,
            colors: colors
        )
    }

    private func sectionContent(flow: MitmFlow) -> String {
        switch section {
        case .requestBody:  return prettyPrint(flow.request?.body ?? "")
        case .responseBody: return prettyPrint(flow.response?.body ?? "")
        case .requestHeaders:  return formatted(headers: flow.request?.headers ?? [:])
        case .responseHeaders: return formatted(headers: flow.response?.headers ?? [:])
        }
    }

    /// Pretty-prints JSON so each key/value lands on its own line,
    /// enabling meaningful line-by-line diffs. Falls back to raw text.
    private func prettyPrint(_ text: String) -> String {
        guard !text.isEmpty,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return text }
        return str
    }

    private func formatted(headers: [String: String]) -> String {
        headers.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }
}

// MARK: - DiffColumnContent (single-side rendering)

private struct DiffColumnContent: View {
    let linesA: [String]
    let linesB: [String]
    let side: DiffSide
    let colors: DesignSystem.ColorPalette

    private struct Item: Identifiable {
        let id: Int
        let text: String
        let background: Color
        let prefix: String
        let lineNumber: Int?
    }

    private var items: [Item] {
        let changes = computeDiff(linesA, linesB)
        var result: [Item] = []
        var a = 0, b = 0
        for (idx, change) in changes.enumerated() {
            switch change {
            case .equal(let line):
                a += 1; b += 1
                result.append(Item(id: idx, text: line, background: .clear,
                                   prefix: " ", lineNumber: side == .a ? a : b))
            case .removed(let line):
                a += 1
                if side == .a {
                    result.append(Item(id: idx, text: line,
                                       background: colors.danger.opacity(0.15),
                                       prefix: "-", lineNumber: a))
                } else {
                    result.append(Item(id: idx, text: "", background: .clear,
                                       prefix: " ", lineNumber: nil))
                }
            case .added(let line):
                b += 1
                if side == .b {
                    result.append(Item(id: idx, text: line,
                                       background: colors.success.opacity(0.15),
                                       prefix: "+", lineNumber: b))
                } else {
                    result.append(Item(id: idx, text: "", background: .clear,
                                       prefix: " ", lineNumber: nil))
                }
            }
        }
        return result
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    HStack(spacing: 0) {
                        Text(item.lineNumber.map { String($0) } ?? "")
                            .font(DesignSystem.Fonts.mono(10))
                            .foregroundStyle(colors.textSecondary.opacity(0.45))
                            .frame(width: DesignSystem.Metrics.scaled(32), alignment: .trailing)
                            .padding(.trailing, DesignSystem.Spacing.xs)
                        Text(item.prefix)
                            .font(DesignSystem.Fonts.mono(11, weight: .semibold))
                            .foregroundStyle(
                                item.prefix == "+" ? colors.success
                                : item.prefix == "-" ? colors.danger
                                : Color.clear
                            )
                            .frame(width: DesignSystem.Metrics.scaled(14), alignment: .center)
                        Text(item.text)
                            .font(DesignSystem.Fonts.mono(12))
                            .foregroundStyle(colors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                    }
                    .padding(.vertical, DesignSystem.Metrics.scaled(1))
                    .background(item.background)
                }
            }
        }
    }

    private func computeDiff(_ a: [String], _ b: [String]) -> [DiffChange] {
        LineDiff.compute(a, b)
    }
}

// MARK: - DiffLines — highlighted diff view

struct DiffLinesView: View {
    let linesA: [String]
    let linesB: [String]
    let colors: DesignSystem.ColorPalette

    private struct NumberedChange: Identifiable {
        let id: Int
        let change: DiffChange
        let lineA: Int?
        let lineB: Int?
    }

    private var numberedDiff: [NumberedChange] {
        let changes = computeDiff(linesA, linesB)
        var result: [NumberedChange] = []
        var a = 0, b = 0
        for (idx, change) in changes.enumerated() {
            switch change {
            case .equal:
                a += 1; b += 1
                result.append(NumberedChange(id: idx, change: change, lineA: a, lineB: b))
            case .removed:
                a += 1
                result.append(NumberedChange(id: idx, change: change, lineA: a, lineB: nil))
            case .added:
                b += 1
                result.append(NumberedChange(id: idx, change: change, lineA: nil, lineB: b))
            }
        }
        return result
    }

    var body: some View {
        let diff = numberedDiff
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diff) { item in diffLineView(item: item, side: .a) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diff) { item in diffLineView(item: item, side: .b) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func diffLineView(item: NumberedChange, side: DiffSide) -> some View {
        let (text, background, prefix, lineNum) = lineInfo(item: item, side: side)
        HStack(spacing: 0) {
            // Gutter: line number
            Text(lineNum.map { String($0) } ?? "")
                .font(DesignSystem.Fonts.mono(10))
                .foregroundStyle(colors.textSecondary.opacity(0.45))
                .frame(width: DesignSystem.Metrics.scaled(32), alignment: .trailing)
                .padding(.trailing, DesignSystem.Spacing.xs)
            // +/- indicator
            Text(prefix)
                .font(DesignSystem.Fonts.mono(11, weight: .semibold))
                .foregroundStyle(
                    prefix == "+" ? colors.success
                    : prefix == "-" ? colors.danger
                    : Color.clear
                )
                .frame(width: DesignSystem.Metrics.scaled(14), alignment: .center)
            // Content
            Text(text)
                .font(DesignSystem.Fonts.mono(12))
                .foregroundStyle(colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignSystem.Spacing.sm)
        }
        .padding(.vertical, DesignSystem.Metrics.scaled(1))
        .background(background)
    }

    private func lineInfo(item: NumberedChange, side: DiffSide) -> (String, Color, String, Int?) {
        switch item.change {
        case .equal(let line):
            return (line, Color.clear, " ", side == .a ? item.lineA : item.lineB)
        case .added(let line):
            if side == .b {
                return (line, colors.success.opacity(0.15), "+", item.lineB)
            } else {
                return ("", Color.clear, " ", nil)
            }
        case .removed(let line):
            if side == .a {
                return (line, colors.danger.opacity(0.15), "-", item.lineA)
            } else {
                return ("", Color.clear, " ", nil)
            }
        }
    }

    private func computeDiff(_ a: [String], _ b: [String]) -> [DiffChange] {
        LineDiff.compute(a, b)
    }
}

// MARK: - Supporting types

private enum DiffSide { case a, b }

enum DiffSection: CaseIterable {
    case requestBody, responseBody, requestHeaders, responseHeaders

    var label: String {
        switch self {
        case .requestBody:     return "Request Body"
        case .responseBody:    return "Response Body"
        case .requestHeaders:  return "Request Headers"
        case .responseHeaders: return "Response Headers"
        }
    }
}


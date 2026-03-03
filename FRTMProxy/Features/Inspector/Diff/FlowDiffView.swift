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
            HStack(spacing: DesignSystem.Metrics.scaled(12)) {
                Image(systemName: "square.on.square")
                    .font(.system(size: DesignSystem.Metrics.scaled(16), weight: .semibold))
                    .foregroundStyle(colors.accent)
                Text("Compare flows")
                    .font(DesignSystem.Fonts.sans(15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors)) { onClose() }
            }
            .padding(DesignSystem.Metrics.scaled(16))
            .background(colors.surfaceElevated)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(colors.border.opacity(0.7)),
                alignment: .bottom
            )

            // Section picker
            HStack(spacing: DesignSystem.Metrics.scaled(8)) {
                ForEach(DiffSection.allCases, id: \.self) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Text(section.label)
                            .font(DesignSystem.Fonts.sans(12, weight: selectedSection == section ? .semibold : .medium))
                            .foregroundStyle(selectedSection == section ? colors.textPrimary : colors.textSecondary)
                            .padding(.horizontal, DesignSystem.Metrics.scaled(12))
                            .padding(.vertical, DesignSystem.Metrics.scaled(6))
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                                    .fill(selectedSection == section ? colors.surfaceElevated : colors.surface.opacity(0.4))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                                    .stroke(
                                        selectedSection == section ? colors.border.opacity(0.9) : colors.border.opacity(0.4),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Metrics.scaled(16))
            .padding(.vertical, DesignSystem.Metrics.scaled(10))
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
        HStack(spacing: DesignSystem.Metrics.scaled(8)) {
            Text(side == .a ? "A" : "B")
                .font(DesignSystem.Fonts.mono(11, weight: .bold))
                .padding(.horizontal, DesignSystem.Metrics.scaled(6))
                .padding(.vertical, DesignSystem.Metrics.scaled(2))
                .background(Capsule().fill(colors.accent.opacity(0.15)))
                .foregroundStyle(colors.accent)
            if let method = flow.request?.method {
                Text(method.uppercased())
                    .font(DesignSystem.Fonts.mono(11, weight: .bold))
                    .foregroundStyle(methodColor(method))
            }
            Text(flow.host + flow.path)
                .font(DesignSystem.Fonts.mono(11))
                .foregroundStyle(colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, DesignSystem.Metrics.scaled(12))
        .padding(.vertical, DesignSystem.Metrics.scaled(8))
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
        case .requestBody: return flow.request?.body ?? ""
        case .responseBody: return flow.response?.body ?? ""
        case .requestHeaders: return formatted(headers: flow.request?.headers ?? [:])
        case .responseHeaders: return formatted(headers: flow.response?.headers ?? [:])
        }
    }

    private func formatted(headers: [String: String]) -> String {
        headers.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    private func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return .green
        case "POST": return .blue
        case "PUT": return .orange
        case "PATCH": return .purple
        case "DELETE": return .red
        default: return colors.textPrimary
        }
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
                            .padding(.trailing, DesignSystem.Metrics.scaled(4))
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
                            .padding(.horizontal, DesignSystem.Metrics.scaled(6))
                    }
                    .padding(.vertical, DesignSystem.Metrics.scaled(1))
                    .background(item.background)
                }
            }
        }
    }

    private func computeDiff(_ a: [String], _ b: [String]) -> [DiffChange] {
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(1, m) {
            for j in 1...max(1, n) {
                if i <= m, j <= n {
                    dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1]+1 : max(dp[i-1][j], dp[i][j-1])
                }
            }
        }
        var result: [DiffChange] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i-1] == b[j-1] {
                result.append(.equal(a[i-1])); i -= 1; j -= 1
            } else if j > 0, (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                result.append(.added(b[j-1])); j -= 1
            } else if i > 0 {
                result.append(.removed(a[i-1])); i -= 1
            } else { break }
        }
        return result.reversed()
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
                .padding(.trailing, DesignSystem.Metrics.scaled(4))
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
                .padding(.horizontal, DesignSystem.Metrics.scaled(6))
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
        // LCS-based diff
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(1, m) {
            for j in 1...max(1, n) {
                if i <= m, j <= n {
                    dp[i][j] = a[i - 1] == b[j - 1] ? dp[i - 1][j - 1] + 1 : max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [DiffChange] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i - 1] == b[j - 1] {
                result.append(.equal(a[i - 1]))
                i -= 1; j -= 1
            } else if j > 0, (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                result.append(.added(b[j - 1]))
                j -= 1
            } else if i > 0 {
                result.append(.removed(a[i - 1]))
                i -= 1
            } else {
                break
            }
        }
        return result.reversed()
    }
}

// MARK: - Supporting types

private enum DiffSide { case a, b }

enum DiffSection: CaseIterable {
    case requestBody, responseBody, requestHeaders, responseHeaders

    var label: String {
        switch self {
        case .requestBody: return "Request Body"
        case .responseBody: return "Response Body"
        case .requestHeaders: return "Request Headers"
        case .responseHeaders: return "Response Headers"
        }
    }
}

enum DiffChange {
    case equal(String)
    case added(String)
    case removed(String)
}

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let text: String
    let size: CGFloat

    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                        .stroke(colors.border.opacity(0.9), lineWidth: 1)
                )

            if let image = makeImage(from: text), !text.isEmpty {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    // Keep the QR quiet zone opaque for cameras in every theme.
                    .padding(DesignSystem.Spacing.sm)
                    .background(Color.white)
                    .padding(DesignSystem.Spacing.lg)
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "qrcode")
                        .font(DesignSystem.Fonts.sans(36))
                    Text("QR code unavailable")
                        .font(DesignSystem.Fonts.label)
                }
                .foregroundStyle(colors.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.isEmpty ? "QR code unavailable" : "Device pairing QR code")
        .accessibilityValue(text)
    }

    private func makeImage(from text: String) -> NSImage? {
        guard !text.isEmpty else { return nil }
        let data = Data(text.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }

        let scaleX = size / outputImage.extent.size.width
        let scaleY = size / outputImage.extent.size.height
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}

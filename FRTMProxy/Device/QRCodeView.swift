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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(colors.border.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)

            if let image = makeImage(from: text), !text.isEmpty {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(24)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 36, weight: .regular))
                    Text("QR non disponibile")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                }
                .foregroundStyle(colors.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text("QR code"))
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

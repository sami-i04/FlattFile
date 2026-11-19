import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

final class Box<T>: ObservableObject {
    @Published var v: T
    init(_ v: T) { self.v = v }
}

extension Color {
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.11)
    static let amberDeep = Color(red: 0.80, green: 0.53, blue: 0.0)
    static let amberText = Color(red: 0.55, green: 0.36, blue: 0.0)
    static let okGreen = Color(red: 0.13, green: 0.55, blue: 0.27)
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black.opacity(enabled ? 0.85 : 0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(enabled ? Color.amber.opacity(configuration.isPressed ? 0.75 : 1) : Color.gray.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.black.opacity(enabled ? 0.08 : 0), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.4).foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

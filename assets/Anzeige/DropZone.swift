import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

struct DropZone: View {
    let targeted: Bool
    let onPick: () -> Void
    @StateObject private var hover = Box(false)

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.amber.opacity(targeted ? 0.30 : 0.16)).frame(width: 104, height: 104)
                Image(systemName: targeted ? "arrow.down.doc.fill" : "doc.badge.arrow.up.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(Color.amberDeep)
            }
            .padding(.bottom, 4)
            Text(targeted ? String(localized: "Loslassen zum Hinzufügen") : String(localized: "Dateien hierher ziehen"))
                .font(.system(size: 20, weight: .semibold))
            Text("oder").foregroundStyle(.secondary)
            Button("Dateien auswählen…", action: onPick)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(targeted ? Color.amber.opacity(0.07) : Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(targeted ? Color.amber : Color.black.opacity(hover.v ? 0.28 : 0.18),
                          style: StrokeStyle(lineWidth: targeted ? 2.5 : 1.5, dash: targeted ? [] : [8, 6])))
        .contentShape(Rectangle())
        .onTapGesture(perform: onPick)
        .onHover { hover.v = $0 }
        .padding(20)
        .animation(.easeOut(duration: 0.15), value: targeted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Ablagebereich. Dateien hierher ziehen oder klicken, um Dateien auszuwählen."))
    }
}

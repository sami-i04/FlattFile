import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

struct FileRow: View {
    let item: Item
    let onInfo: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            thumb
            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(item.kind.label)
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Color.amber.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Color.amberText)
                    Text(bytes(item.size) + (item.info.isEmpty ? "" : "  ·  " + item.info))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .lineLimit(1)
            }
            .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
            status
                .frame(minWidth: 110, maxWidth: 200, alignment: .trailing)
                .layoutPriority(1)
            HStack(spacing: 0) {
                iconButton("info.circle", String(localized: "Metadaten anzeigen"), onInfo)
                if let out = item.outURL {
                    iconButton("magnifyingglass", String(localized: "Im Finder zeigen")) { NSWorkspace.shared.activateFileViewerSelecting([out]) }
                }
                iconButton("xmark", String(localized: "Aus Liste entfernen"), onRemove).disabled(item.status == .working)
            }
            .fixedSize()
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button("Original öffnen") { NSWorkspace.shared.open(item.url) }
            if let out = item.outURL {
                Button("Ergebnis öffnen") { NSWorkspace.shared.open(out) }
                Button("Ergebnis im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([out]) }
            }
            Button("Metadaten anzeigen…", action: onInfo)
            Divider()
            Button("Aus Liste entfernen", action: onRemove)
        }
    }

    func iconButton(_ sym: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sym).font(.system(size: 13)).frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder var thumb: some View {
        Group {
            if let t = item.thumb {
                Image(nsImage: t).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().padding(2)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(0.08)))
    }

    @ViewBuilder var status: some View {
        switch item.status {
        case .pending:
            Text(item.kind.methodHint).font(.caption).foregroundStyle(.tertiary)
        case .working:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Wird bearbeitet…").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        case let .done(n, note):
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Text(bytes(n)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    let pct = item.size > 0 ? Int((Double(item.size - n) / Double(item.size) * 100).rounded()) : 0
                    if pct != 0 {
                        Text(pct > 0 ? "−\(pct) %" : "+\(-pct) %")
                            .font(.system(size: 11, weight: .bold)).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background((pct > 0 ? Color.okGreen : Color.orange).opacity(0.13), in: Capsule())
                            .foregroundStyle(pct > 0 ? Color.okGreen : Color.orange)
                    }
                }
                .fixedSize()
                if let note { Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
        case let .skipped(m):
            Text(m).font(.caption).foregroundStyle(Color.amberText)
                .multilineTextAlignment(.trailing).lineLimit(2).help(m)
        case let .failed(m):
            Label(m, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(2).help(m)
        }
    }
}


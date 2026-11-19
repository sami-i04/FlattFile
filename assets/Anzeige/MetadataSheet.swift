import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

struct MetadataSheet: View {
    @ObservedObject var model: AppModel
    let id: UUID
    @Environment(\.dismiss) var dismiss
    @StateObject private var sections = Box<[MetaSection]>([])
    @StateObject private var gps = Box(false)
    @StateObject private var loading = Box(true)
    @StateObject private var filter = Box("")
    @StateObject private var result = Box<String?>(nil)
    @StateObject private var error = Box<String?>(nil)
    @StateObject private var working = Box(false)

    var item: Item? { model.item(id) }

    var filtered: [MetaSection] {
        guard !filter.v.isEmpty else { return sections.v }
        return sections.v.compactMap { s in
            var c = s
            c.rows = s.rows.filter { $0.0.localizedCaseInsensitiveContains(filter.v) || $0.1.localizedCaseInsensitiveContains(filter.v) }
            return c.rows.isEmpty ? nil : c
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let it = item {
                HStack(spacing: 12) {
                    Image(nsImage: it.thumb ?? NSWorkspace.shared.icon(forFile: it.url.path))
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Metadaten").font(.headline)
                        Text(it.url.lastPathComponent).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Filtern", text: $filter.v).textFieldStyle(.plain).frame(width: 130)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                }
                .padding(16)

                if gps.v {
                    Label("Diese Datei enthält GPS-Standortdaten.", systemImage: "location.fill")
                        .font(.callout).foregroundStyle(Color.amberText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.amber.opacity(0.14))
                }
                Divider()

                if loading.v {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filtered) { s in
                            Section(s.title) {
                                ForEach(Array(s.rows.enumerated()).map { ("\(s.title)#\($0.offset)", $0.element) }, id: \.0) { _, r in
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(r.0).foregroundStyle(.secondary)
                                            .frame(width: 170, alignment: .leading)
                                        Text(r.1).textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .font(.system(size: 12))
                                }
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
                Divider()
                HStack(spacing: 10) {
                    if let result = result.v {
                        Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(Color.okGreen)
                            .font(.callout).lineLimit(1).truncationMode(.middle)
                    } else if let error = error.v {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            .font(.callout).lineLimit(2)
                    } else if !it.kind.canStripMeta {
                        Text(it.kind == .raw ? String(localized: "RAW: Metadaten werden beim Umwandeln entfernt (Schalter „Metadaten entfernen“).")
                                             : String(localized: "BMP enthält keine entfernbaren Metadaten."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if it.kind.canStripMeta {
                        Button {
                            working.v = true; error.v = nil
                            model.stripMeta(id) { r in
                                working.v = false
                                switch r {
                                case let .success(u): result.v = String(localized: "Gespeichert als \(u.lastPathComponent)")
                                case let .failure(e): error.v = e.localizedDescription
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if working.v { ProgressView().controlSize(.small) }
                                Text("Metadaten entfernen")
                            }
                        }
                        .disabled(working.v || result.v != nil)
                        .help("Speichert eine Kopie ohne Metadaten – das Original bleibt unverändert")
                    }
                    Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
                }
                .padding(16)
            }
        }
        .frame(width: 600, height: 560)
        .task {
            guard let it = item else { return }
            let (s, g) = await Task.detached { Meta.read(it.url, it.kind) }.value
            sections.v = s; gps.v = g; loading.v = false
        }
    }
}

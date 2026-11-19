import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

struct SettingsPanel: View {
    @ObservedObject var model: AppModel

    static let presets: [Double] = [0.4, 0.6, 0.8]
    static let sizes: [(Int, String)] = [(0, String(localized: "Original beibehalten")), (3840, String(localized: "3840 px (4K)")), (2560, "2560 px"),
                                         (1920, String(localized: "1920 px (Full HD)")), (1280, "1280 px")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    section(String(localized: "Qualität")) {
                        FlexSegments(options: [String(localized: "Klein"), String(localized: "Ausgewogen"), String(localized: "Hoch")],
                                     selected: Self.presets.firstIndex(of: model.quality)) { model.quality = Self.presets[$0] }
                        HStack(spacing: 8) {
                            Slider(value: $model.quality, in: 0.1...1.0, step: 0.05)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .accessibilityLabel(String(localized: "Qualität"))
                            Text("\(Int((model.quality * 100).rounded())) %")
                                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                .lineLimit(1)
                                .frame(width: 42, alignment: .trailing)
                        }
                        HStack(spacing: 4) {
                            Text("Kleinere Datei").lineLimit(1)
                            Spacer(minLength: 4)
                            Text("Bessere Qualität").lineLimit(1)
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                        .minimumScaleFactor(0.8)
                        .padding(.trailing, 50)
                    }

                    section(String(localized: "Maximale Bildgröße")) {
                        FlexDropdown(title: Self.sizes.first { $0.0 == model.maxDim }?.1 ?? String(localized: "Original beibehalten")) {
                            Self.sizes.map { s in MenuEntry(title: s.1, checked: s.0 == model.maxDim) { model.maxDim = s.0 } }
                        }
                    }

                    section(String(localized: "Datenschutz")) {
                        HStack(spacing: 8) {
                            Text("Metadaten entfernen").lineLimit(1).truncationMode(.tail)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            Toggle("Metadaten entfernen", isOn: $model.strip)
                                .toggleStyle(.switch).labelsHidden()
                        }
                    }

                    if model.items.contains(where: { $0.kind == .raw }) {
                        section(String(localized: "RAW umwandeln in")) {
                            FlexSegments(options: ["JPEG", "HEIC"], selected: model.rawOut == .jpeg ? 0 : 1) {
                                model.rawOut = $0 == 0 ? .jpeg : .heic
                            }
                        }
                    }

                    section(String(localized: "Speichern unter")) {
                        FlexDropdown(title: model.folder?.lastPathComponent ?? String(localized: "Neben dem Original"),
                                     icon: model.folder == nil ? "doc.on.doc" : "folder") {
                            var e = [MenuEntry(title: String(localized: "Neben dem Original"), checked: model.folder == nil) { model.folder = nil }]
                            if let f = model.folder { e.append(MenuEntry(title: f.path, checked: true, enabled: false)) }
                            e.append(.divider)
                            e.append(MenuEntry(title: String(localized: "Ordner wählen…")) { model.chooseFolder() })
                            return e
                        }
                    }
                }
                .padding(20)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
                .padding(20)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title)
            content()
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder var footer: some View {
        let t = model.totals
        VStack(alignment: .leading, spacing: 12) {
            if t.count > 0 {
                let saved = t.before - t.after
                let pct = t.before > 0 ? Int((Double(saved) / Double(t.before) * 100).rounded()) : 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Ersparnis").foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(saved >= 0 ? "−\(pct) %" : "+\(-pct) %").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(saved >= 0 ? Color.okGreen : Color.orange)
                            .lineLimit(1)
                    }
                    Text("\(bytes(t.before)) → \(bytes(t.after))")
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .font(.callout)
            }
            Button(action: model.compressAll) {
                HStack(spacing: 8) {
                    if model.isRunning { ProgressView().controlSize(.small) }
                    Text(model.isRunning ? String(localized: "Wird komprimiert…") : String(localized: "Komprimieren")).lineLimit(1)
                }
            }
            .buttonStyle(PrimaryButton())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.items.isEmpty || model.isRunning)
            .help("Alle Dateien komprimieren (⌘↩)")
        }
    }
}

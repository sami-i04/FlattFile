import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

struct LeftPane: View {
    @ObservedObject var model: AppModel
    @StateObject private var selection = Box(Set<UUID>())

    var body: some View {
        ZStack {
            if model.items.isEmpty {
                DropZone(targeted: model.dropTargeted, onPick: model.openPanel)
            } else {
                fileList
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .background(Color(nsColor: .textBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            let g = DispatchGroup()
            var urls: [URL] = []
            let lock = NSLock()
            for p in providers {
                g.enter()
                _ = p.loadObject(ofClass: URL.self) { u, _ in
                    if let u { lock.lock(); urls.append(u); lock.unlock() }
                    g.leave()
                }
            }
            g.notify(queue: .main) { model.add(urls) }
            return true
        }
        .overlay(alignment: .top) {
            if let n = model.notice {
                Label(n, systemImage: "info.circle.fill")
                    .font(.callout)
                    .lineLimit(2)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.08)))
                    .padding(.top, 12).padding(.horizontal, 16)
                    .onTapGesture { model.notice = nil }
            }
        }
        .sheet(item: $model.metaTarget) { t in MetadataSheet(model: model, id: t.id) }
        .alert(model.unsupported?.count == 1 ? String(localized: "Datei wird nicht unterstützt") : String(localized: "Dateien werden nicht unterstützt"),
               isPresented: Binding(get: { model.unsupported != nil }, set: { if !$0 { model.unsupported = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            let list = model.unsupported ?? []
            let names = list.prefix(5).joined(separator: "\n") + (list.count > 5 ? String(localized: "\n… und \(list.count - 5) weitere") : "")
            Text("\(names)\n\nUnterstützt: PDF, JPEG, PNG, HEIC, TIFF, BMP, RAW.\nWebP und GIF: nur Metadaten anzeigen und entfernen.")
        }
    }

    var fileList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(model.items.count == 1 ? String(localized: "1 Datei") : String(localized: "\(model.items.count) Dateien")).font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button { model.openPanel() } label: { Label("Hinzufügen…", systemImage: "plus") }
                Button("Liste leeren") { model.clear(); selection.v.removeAll() }
                    .disabled(model.isRunning)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            List(selection: $selection.v) {
                ForEach(model.items) { it in
                    FileRow(item: it,
                            onInfo: { model.metaTarget = MetaTarget(id: it.id) },
                            onRemove: { model.remove([it.id]); selection.v.remove(it.id) })
                        .tag(it.id)
                }
            }
            .listStyle(.inset)
            .onDeleteCommand { model.remove(selection.v); selection.v.removeAll() }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            if model.dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.amber, lineWidth: 3)
                    .background(Color.amber.opacity(0.06))
                    .overlay(Label("Loslassen zum Hinzufügen", systemImage: "plus.circle.fill")
                        .font(.headline).foregroundStyle(Color.amberText)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule()))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}

final class PaneContainer: NSView {
    init(_ content: NSView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

func hosting<V: View>(_ v: V) -> NSHostingView<V> {
    let h = NSHostingView(rootView: v)
    h.sizingOptions = []
    return h
}

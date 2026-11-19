import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

enum Status: Equatable {
    case pending, working
    case done(Int64, String?)
    case skipped(String)
    case failed(String)
}

struct Item: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let kind: Kind
    let size: Int64
    var info = ""
    var thumb: NSImage? = nil
    var status: Status = .pending
    var outURL: URL? = nil
}

struct MetaTarget: Identifiable { let id: UUID }

final class AppModel: ObservableObject {
    private let ud = UserDefaults.standard

    @Published var items: [Item] = []
    @Published var isRunning = false
    @Published var notice: String? = nil
    @Published var metaTarget: MetaTarget? = nil
    @Published var unsupported: [String]? = nil
    @Published var dropTargeted = false

    @Published var quality: Double { didSet { ud.set(quality, forKey: "quality100") } }
    @Published var maxDim: Int { didSet { ud.set(maxDim, forKey: "maxDim") } }
    @Published var strip: Bool { didSet { ud.set(strip, forKey: "strip") } }
    @Published var rawOut: RawOut { didSet { ud.set(rawOut.rawValue, forKey: "rawOut") } }
    @Published var folder: URL? { didSet { ud.set(folder?.path, forKey: "folder") } }

    private var queue: OperationQueue?
    private var noticeWork: DispatchWorkItem?

    init() {
        quality = ud.object(forKey: "quality100") as? Double ?? 1.0
        maxDim = ud.integer(forKey: "maxDim")
        strip = ud.object(forKey: "strip") as? Bool ?? true
        rawOut = RawOut(rawValue: ud.string(forKey: "rawOut") ?? "") ?? .jpeg
        folder = ud.string(forKey: "folder").map { URL(fileURLWithPath: $0) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    var settings: Settings { Settings(quality: quality, maxDim: maxDim, strip: strip, rawOut: rawOut, folder: folder) }

    func item(_ id: UUID) -> Item? { items.first { $0.id == id } }

    func update(_ id: UUID, _ f: (inout Item) -> Void) {
        if let i = items.firstIndex(where: { $0.id == id }) { f(&items[i]) }
    }

    func show(_ text: String) {
        notice = text
        noticeWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: w)
    }

    func add(_ urls: [URL]) {
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [(URL, Kind, Int64)] = []
            var rejected: [String] = []
            let fm = FileManager.default
            func consider(_ u: URL, direct: Bool) {
                guard let k = Kind.detect(u) else {
                    if direct { rejected.append(u.lastPathComponent) }
                    return
                }
                let s = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init) ?? 0
                found.append((u, k, s))
            }
            for u in urls {
                var dir: ObjCBool = false
                guard fm.fileExists(atPath: u.path, isDirectory: &dir) else { continue }
                if dir.boolValue && Kind.detect(u) == nil {
                    let e = fm.enumerator(at: u, includingPropertiesForKeys: [.isRegularFileKey],
                                          options: [.skipsHiddenFiles, .skipsPackageDescendants])
                    while let f = e?.nextObject() as? URL {
                        if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { consider(f, direct: false) }
                    }
                } else { consider(u, direct: true) }
            }
            DispatchQueue.main.async {
                let have = Set(self.items.map { $0.url.standardizedFileURL.path })
                var added: [Item] = []
                for (u, k, s) in found where !have.contains(u.standardizedFileURL.path) {
                    added.append(Item(url: u, kind: k, size: s))
                }
                self.items.append(contentsOf: added)
                if !rejected.isEmpty {
                    self.unsupported = rejected
                } else if found.isEmpty && !urls.isEmpty {
                    self.show(String(localized: "Keine unterstützten Dateien gefunden"))
                }
                for it in added {
                    DispatchQueue.global(qos: .utility).async {
                        let (img, info) = Engine.preview(it.url, it.kind)
                        DispatchQueue.main.async { self.update(it.id) { $0.thumb = img; $0.info = info } }
                    }
                }
            }
        }
    }

    func remove(_ ids: Set<UUID>) { items.removeAll { ids.contains($0.id) && $0.status != .working } }
    func clear() { items.removeAll { $0.status != .working } }

    func openPanel() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.prompt = String(localized: "Hinzufügen")
        p.message = String(localized: "Dateien oder Ordner zum Komprimieren auswählen")
        if p.runModal() == .OK { add(p.urls) }
    }

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = String(localized: "Auswählen")
        p.message = String(localized: "Ordner für komprimierte Dateien")
        if p.runModal() == .OK { folder = p.url }
    }

    func compressAll() {
        guard !isRunning, !items.isEmpty else { return }
        isRunning = true
        let s = settings
        let jobs = items
        for j in jobs { update(j.id) { $0.status = .working } }
        let q = OperationQueue()
        q.maxConcurrentOperationCount = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))
        q.qualityOfService = .userInitiated
        for j in jobs {
            q.addOperation {
                autoreleasepool {
                    var st: Status, out: URL? = nil
                    do {
                        switch try Engine.process(url: j.url, kind: j.kind, size: j.size, s: s, reuse: j.outURL) {
                        case let .written(u, n, note): st = .done(n, note); out = u
                        case let .skipped(m): st = .skipped(m)
                        }
                    } catch { st = .failed(error.localizedDescription) }
                    DispatchQueue.main.async { self.update(j.id) { $0.status = st; if let out { $0.outURL = out } } }
                }
            }
        }
        q.addBarrierBlock { DispatchQueue.main.async { self.isRunning = false; self.queue = nil } }
        queue = q
    }

    func stripMeta(_ id: UUID, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let it = item(id) else { return }
        let folder = folder
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try Engine.stripOnly(url: it.url, kind: it.kind, folder: folder, reuse: it.outURL) }
            DispatchQueue.main.async {
                if case let .success((u, n)) = r {
                    self.update(id) { $0.outURL = u; $0.status = .done(n, String(localized: "Metadaten entfernt")) }
                }
                completion(r.map { $0.0 })
            }
        }
    }

    var totals: (before: Int64, after: Int64, count: Int) {
        var b: Int64 = 0, a: Int64 = 0, c = 0
        for it in items { if case let .done(n, _) = it.status { b += it.size; a += n; c += 1 } }
        return (b, a, c)
    }
}

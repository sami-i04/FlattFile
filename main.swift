import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

let args = CommandLine.arguments
if let ci = args.firstIndex(of: "--cli") {
    var s = Settings(quality: 0.6, maxDim: 0, strip: true, rawOut: .jpeg, folder: nil)
    var files: [String] = [], meta = false, stripOnly = false
    var i = ci + 1
    while i < args.count {
        switch args[i] {
        case "--q": i += 1; s.quality = Double(args[i]) ?? 0.75
        case "--max": i += 1; s.maxDim = Int(args[i]) ?? 0
        case "--keep": s.strip = false
        case "--heic": s.rawOut = .heic
        case "--meta": meta = true
        case "--strip": stripOnly = true
        default: files.append(args[i])
        }
        i += 1
    }
    for f in files {
        let u = URL(fileURLWithPath: f)
        guard let k = Kind.detect(u) else { print("✗ \(f): nicht unterstützt"); continue }
        let size = (try? FileManager.default.attributesOfItem(atPath: f)[.size] as? Int64) ?? 0
        if meta {
            let (secs, gps) = Meta.read(u, k)
            print("── \(u.lastPathComponent)  GPS: \(gps)")
            for sec in secs { print("[\(sec.title)]"); for r in sec.rows { print("  \(r.0): \(r.1)") } }
            continue
        }
        let t0 = Date()
        do {
            if stripOnly {
                let (o, n) = try Engine.stripOnly(url: u, kind: k, folder: nil, reuse: nil)
                print("✓ \(u.lastPathComponent): \(bytes(size)) → \(bytes(n))  [\(o.lastPathComponent)]")
            } else {
                switch try Engine.process(url: u, kind: k, size: size, s: s, reuse: nil) {
                case let .written(o, n, _):
                    print(String(format: "✓ %@: %@ → %@ (−%.0f %%) %.2fs  [%@]", u.lastPathComponent, bytes(size), bytes(n),
                                 Double(size - n) / Double(max(size, 1)) * 100, Date().timeIntervalSince(t0), o.lastPathComponent))
                case let .skipped(m): print("– \(u.lastPathComponent): \(m)")
                }
            }
        } catch { print("✗ \(u.lastPathComponent): \(error.localizedDescription)") }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

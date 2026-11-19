import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

enum Engine {

    static func outputURL(for src: URL, ext: String, folder: URL?, reuse: URL?) -> URL {
        if let r = reuse, r.pathExtension.lowercased() == ext.lowercased(),
           (folder == nil || r.deletingLastPathComponent().standardizedFileURL == folder!.standardizedFileURL) {
            return r
        }
        let dir = folder ?? src.deletingLastPathComponent()
        let base = src.deletingPathExtension().lastPathComponent + "_flatt"
        var u = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext); n += 1
        }
        return u
    }

    static func process(url: URL, kind: Kind, size: Int64, s: Settings, reuse: URL?) throws -> Outcome {
        var ext = url.pathExtension
        var force = false
        var note: String? = nil
        let data: Data
        switch kind {
        case .jpeg: data = try reencode(url, type: .jpeg, s)
        case .heic: data = try reencode(url, type: .heic, s)
        case .raw:
            data = try convertRAW(url, s)
            ext = s.rawOut == .jpeg ? "jpg" : "heic"
            force = true
            note = String(localized: "Umgewandelt in \(s.rawOut == .jpeg ? "JPEG" : "HEIC")")
        case .tiff: data = try tiff(url, s)
        case .png: data = try png(url, s)
        case .bmp: data = try png(url, s); ext = "png"; note = String(localized: "Umgewandelt in PNG")
        case .pdf: data = try pdf(url, s)
        case .gif, .webp:
            guard s.strip else { return .skipped(String(localized: "Nur Metadaten – Schalter aktivieren")) }
            let raw = try Data(contentsOf: url)
            let (d, removed) = kind == .gif ? try stripGIF(raw) : try stripWebP(raw)
            if removed.isEmpty { return .skipped(String(localized: "Keine Metadaten enthalten")) }
            data = d
            note = String(localized: "Metadaten entfernt")
            force = true
        }
        if !force && Double(data.count) >= Double(size) * 0.99 {
            return .skipped(String(localized: "Bereits optimal"))
        }
        let out = outputURL(for: url, ext: ext, folder: s.folder, reuse: reuse)
        try data.write(to: out, options: .atomic)
        return .written(out, Int64(data.count), note)
    }

    static func source(_ url: URL) throws -> CGImageSource {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0 else { throw FFError(String(localized: "Datei konnte nicht gelesen werden")) }
        return src
    }

    static func props(_ src: CGImageSource, _ i: Int = 0) -> [CFString: Any] {
        CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] ?? [:]
    }

    static func loadOriented(_ src: CGImageSource, maxDim: Int) throws -> CGImage {
        let p = props(src)
        let w = p[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = p[kCGImagePropertyPixelHeight] as? Int ?? 0
        let full = max(w, h)
        guard full > 0 else { throw FFError(String(localized: "Bildgröße unbekannt")) }
        let target = maxDim > 0 ? min(maxDim, full) : full
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw FFError(String(localized: "Bild konnte nicht dekodiert werden"))
        }
        return img
    }

    static func outputProps(_ src: [CFString: Any], strip: Bool) -> [CFString: Any] {
        var p: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        guard !strip else { return p }
        for k in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
                  kCGImagePropertyTIFFDictionary, kCGImagePropertyExifAuxDictionary] {
            guard var d = src[k] as? [CFString: Any] else { continue }
            if k == kCGImagePropertyTIFFDictionary { d[kCGImagePropertyTIFFOrientation] = 1 }
            if k == kCGImagePropertyExifDictionary {
                d.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
                d.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            }
            p[k] = d
        }
        return p
    }

    static func encode(_ imgs: [CGImage], type: UTType, quality: Double?, props: [[CFString: Any]]) throws -> Data {
        let data = NSMutableData()
        guard let d = CGImageDestinationCreateWithData(data, type.identifier as CFString, imgs.count, nil) else {
            throw FFError(String(localized: "Ausgabeformat nicht verfügbar"))
        }
        for (i, img) in imgs.enumerated() {
            var p = props[i]
            if let q = quality { p[kCGImageDestinationLossyCompressionQuality] = q }
            CGImageDestinationAddImage(d, img, p as CFDictionary)
        }
        guard CGImageDestinationFinalize(d) else { throw FFError(String(localized: "Schreiben fehlgeschlagen")) }
        return data as Data
    }

    static func reencode(_ url: URL, type: UTType, _ s: Settings) throws -> Data {
        let src = try source(url)
        let img = try loadOriented(src, maxDim: s.maxDim)
        return try encode([img], type: type, quality: s.quality, props: [outputProps(props(src), strip: s.strip)])
    }

    static func convertRAW(_ url: URL, _ s: Settings) throws -> Data {
        let src = try source(url)
        var img: CGImage? = nil
        if let f = CIRAWFilter(imageURL: url) {
            let n = f.nativeSize
            let full = max(n.width, n.height)
            if s.maxDim > 0, full > CGFloat(s.maxDim) { f.scaleFactor = Float(CGFloat(s.maxDim) / full) }
            if let ci = f.outputImage {
                let ctx = CIContext(options: [.cacheIntermediates: false])
                img = ctx.createCGImage(ci, from: ci.extent, format: .RGBA8,
                                        colorSpace: CGColorSpace(name: CGColorSpace.displayP3))
            }
        }
        if img == nil { img = try loadOriented(src, maxDim: s.maxDim) }
        guard let img else { throw FFError(String(localized: "RAW konnte nicht entwickelt werden")) }
        let type: UTType = s.rawOut == .jpeg ? .jpeg : .heic
        return try encode([img], type: type, quality: s.quality, props: [outputProps(props(src), strip: s.strip)])
    }

    static func tiff(_ url: URL, _ s: Settings) throws -> Data {
        let src = try source(url)
        let count = CGImageSourceGetCount(src)
        var imgs: [CGImage] = [], ps: [[CFString: Any]] = []
        for i in 0..<count {
            let img: CGImage
            if count == 1 { img = try loadOriented(src, maxDim: s.maxDim) }
            else {
                guard let im = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
                img = im
            }
            var p = count == 1 ? outputProps(props(src, i), strip: s.strip) : (s.strip ? [:] : props(src, i))
            var t = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            t[kCGImagePropertyTIFFCompression] = 5
            p[kCGImagePropertyTIFFDictionary] = t
            imgs.append(img); ps.append(p)
        }
        guard !imgs.isEmpty else { throw FFError(String(localized: "TIFF enthält keine lesbaren Seiten")) }
        return try encode(imgs, type: .tiff, quality: nil, props: ps)
    }

    static func png(_ url: URL, _ s: Settings) throws -> Data {
        let src = try source(url)
        let img = try loadOriented(src, maxDim: s.maxDim)
        let px = PNGKit.rgba(img)
        var cands: [Data] = []

        let flat = px.opaque ? (PNGKit.opaqueCopy(img) ?? img) : img
        if let d = try? encode([flat], type: .png, quality: nil, props: [outputProps(props(src), strip: s.strip)]) {
            cands.append(d)
        }
        if let (pal, idx) = PNGKit.exactPalette(px) {
            cands.append(PNGKit.writeIndexed(w: px.w, h: px.h, palette: pal, indices: idx))
        } else if s.quality < 0.9 {
            let k = s.quality >= 0.6 ? 256 : s.quality >= 0.4 ? 128 : s.quality >= 0.25 ? 64 : 32
            let pal = Quant.palette(px, colors: k)
            let idx = Quant.remap(px, palette: pal)
            let (sorted, mapped) = PNGKit.sortByAlpha(pal, idx)
            cands.append(PNGKit.writeIndexed(w: px.w, h: px.h, palette: sorted, indices: mapped))
        }
        guard let best = cands.min(by: { $0.count < $1.count }) else { throw FFError(String(localized: "PNG konnte nicht erzeugt werden")) }
        return best
    }

    static func pdf(_ url: URL, _ s: Settings) throws -> Data {
        guard let doc = PDFDocument(url: url) else { throw FFError(String(localized: "PDF konnte nicht gelesen werden")) }
        if doc.isLocked { throw FFError(String(localized: "PDF ist passwortgeschützt")) }
        if s.strip { doc.documentAttributes = [:] }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("flatt-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dpi = s.quality >= 0.85 ? 300 : s.quality >= 0.6 ? 200 : s.quality >= 0.35 ? 150 : 110
        let filterDict: [String: Any] = [
            "Domains": ["Applications": true, "Printing": true],
            "FilterData": ["ColorSettings": ["ImageSettings": [
                "Compression Quality": s.quality,
                "ImageCompression": "ImageJPEGCompress",
                "ImageScaleSettings": [
                    "ImageResolution": dpi,
                    "ImageScaleInterpolate": true,
                    "ImageSizeMax": s.maxDim > 0 ? s.maxDim : 20000,
                    "ImageSizeMin": 0,
                ],
            ]]],
            "FilterType": 1,
            "Name": "FlattFile",
        ]
        let fURL = tmp.appendingPathComponent("flatt.qfilter")
        try PropertyListSerialization.data(fromPropertyList: filterDict, format: .xml, options: 0).write(to: fURL)

        var results: [Data] = []
        if let filter = QuartzFilter(url: fURL) {
            let o = tmp.appendingPathComponent("a.pdf")
            if doc.write(to: o, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]),
               let d = try? Data(contentsOf: o) { results.append(d) }
        }
        if s.quality < 0.5 {
            let o = tmp.appendingPathComponent("b.pdf")
            if doc.write(to: o, withOptions: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]),
               let d = try? Data(contentsOf: o) { results.append(d) }
        }
        let o = tmp.appendingPathComponent("c.pdf")
        if doc.write(to: o), let d = try? Data(contentsOf: o) { results.append(d) }

        guard let best = results.filter({ PDFDocument(data: $0)?.pageCount == doc.pageCount })
            .min(by: { $0.count < $1.count }) else { throw FFError(String(localized: "PDF konnte nicht geschrieben werden")) }
        return best
    }

    static func stripOnly(url: URL, kind: Kind, folder: URL?, reuse: URL?) throws -> (URL, Int64) {
        let data: Data
        switch kind {
        case .webp:
            let (d, r) = try stripWebP(try Data(contentsOf: url))
            if r.isEmpty { throw FFError(String(localized: "Keine Metadaten zum Entfernen gefunden")) }
            data = d
        case .gif:
            let (d, r) = try stripGIF(try Data(contentsOf: url))
            if r.isEmpty { throw FFError(String(localized: "Keine Metadaten zum Entfernen gefunden")) }
            data = d
        case .pdf:
            guard let doc = PDFDocument(url: url) else { throw FFError(String(localized: "PDF konnte nicht gelesen werden")) }
            if doc.isLocked { throw FFError(String(localized: "PDF ist passwortgeschützt")) }
            doc.documentAttributes = [:]
            guard let d = doc.dataRepresentation() else { throw FFError(String(localized: "PDF konnte nicht geschrieben werden")) }
            data = d
        case .jpeg, .png, .heic, .tiff:
            data = try stripImageLossless(url)
        case .bmp: throw FFError(String(localized: "BMP enthält keine entfernbaren Metadaten"))
        case .raw: throw FFError(String(localized: "RAW kann nicht neu geschrieben werden – beim Umwandeln werden Metadaten entfernt"))
        }
        let out = outputURL(for: url, ext: url.pathExtension, folder: folder, reuse: reuse)
        try data.write(to: out, options: .atomic)
        return (out, Int64(data.count))
    }

    static func stripImageLossless(_ url: URL) throws -> Data {
        let src = try source(url)
        guard let type = CGImageSourceGetType(src) else { throw FFError(String(localized: "Format unbekannt")) }
        let p = props(src)
        let orient = p[kCGImagePropertyOrientation] as? Int ?? 1
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type, CGImageSourceGetCount(src), nil) else {
            throw FFError(String(localized: "Format kann nicht geschrieben werden"))
        }
        let meta = CGImageMetadataCreateMutable()
        if orient != 1 {
            CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary,
                                                         kCGImagePropertyTIFFOrientation, orient as CFNumber)
        }
        let opts: [CFString: Any] = [
            kCGImageDestinationMetadata: meta,
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeXMP: true,
            kCGImageMetadataShouldExcludeGPS: true,
        ]
        if CGImageDestinationCopyImageSource(dest, src, opts as CFDictionary, nil) { return data as Data }

        let out = NSMutableData()
        let n = CGImageSourceGetCount(src)
        guard let d2 = CGImageDestinationCreateWithData(out, type, n, nil) else { throw FFError(String(localized: "Schreiben fehlgeschlagen")) }
        for i in 0..<n {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            var ip: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
            if let o = props(src, i)[kCGImagePropertyOrientation] { ip[kCGImagePropertyOrientation] = o }
            CGImageDestinationAddImage(d2, img, ip as CFDictionary)
        }
        guard CGImageDestinationFinalize(d2) else { throw FFError(String(localized: "Schreiben fehlgeschlagen")) }
        return out as Data
    }

    static func stripWebP(_ d: Data) throws -> (Data, [String]) {
        let b = [UInt8](d)
        guard b.count >= 12, b[0..<4].elementsEqual("RIFF".utf8), b[8..<12].elementsEqual("WEBP".utf8) else {
            throw FFError(String(localized: "Keine gültige WebP-Datei"))
        }
        func le32(_ i: Int) -> Int { Int(b[i]) | Int(b[i+1]) << 8 | Int(b[i+2]) << 16 | Int(b[i+3]) << 24 }
        var chunks: [([UInt8], [UInt8])] = []
        var removed: [String] = []
        var i = 12
        while i + 8 <= b.count {
            let cc = Array(b[i..<i+4])
            let size = le32(i + 4)
            let start = i + 8, end = min(start + size, b.count)
            let name = String(bytes: cc, encoding: .ascii) ?? "????"
            if name == "EXIF" || name == "XMP " {
                removed.append(String(localized: "\(name.trimmingCharacters(in: .whitespaces))-Block (\(bytes(Int64(size))))"))
            } else {
                chunks.append((cc, Array(b[start..<end])))
            }
            i = start + size + (size & 1)
        }
        if let v = chunks.firstIndex(where: { $0.0.elementsEqual("VP8X".utf8) }), !chunks[v].1.isEmpty {
            chunks[v].1[0] &= ~UInt8(0x0C)
        }
        func le(_ n: Int) -> [UInt8] { [UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24 & 0xFF)] }
        var body: [UInt8] = Array("WEBP".utf8)
        for (cc, p) in chunks {
            body += cc; body += le(p.count); body += p
            if p.count & 1 == 1 { body.append(0) }
        }
        return (Data(Array("RIFF".utf8) + le(body.count) + body), removed)
    }

    static func stripGIF(_ d: Data) throws -> (Data, [String]) {
        let b = [UInt8](d)
        guard b.count >= 13, b[0..<4].elementsEqual("GIF8".utf8) else { throw FFError(String(localized: "Keine gültige GIF-Datei")) }
        let keep = ["NETSCAPE2.0", "ANIMEXTS1.0", "ICCRGBG1012"]
        var out = Array(b[0..<13])
        var removed: [String] = []
        var i = 13
        if b[10] & 0x80 != 0 {
            let n = 3 * (1 << (Int(b[10] & 7) + 1))
            guard i + n <= b.count else { throw FFError(String(localized: "GIF ist beschädigt")) }
            out += b[i..<i+n]; i += n
        }
        func skipBlocks(_ start: Int) -> Int {
            var j = start
            while j < b.count {
                let s = Int(b[j]); j += 1
                if s == 0 { break }
                j += s
            }
            return min(j, b.count)
        }
        loop: while i < b.count {
            switch b[i] {
            case 0x21:
                guard i + 2 < b.count else { break loop }
                let label = b[i + 1]
                if label == 0xFE {
                    let e = skipBlocks(i + 2); removed.append(String(localized: "Kommentar (\(bytes(Int64(e - i))))")); i = e
                } else if label == 0xFF {
                    let bs = Int(b[i + 2])
                    let idEnd = min(i + 3 + bs, b.count)
                    let id = String(bytes: b[(i + 3)..<idEnd], encoding: .ascii) ?? "?"
                    let e = skipBlocks(idEnd)
                    if keep.contains(where: { id.hasPrefix($0) }) { out += b[i..<e] }
                    else { removed.append(String(localized: "Anwendungsdaten „\(id.trimmingCharacters(in: .whitespaces))“ (\(bytes(Int64(e - i))))")) }
                    i = e
                } else {
                    let e = skipBlocks(i + 2); out += b[i..<e]; i = e
                }
            case 0x2C:
                guard i + 10 <= b.count else { break loop }
                var j = i + 10
                let p = b[i + 9]
                if p & 0x80 != 0 { j += 3 * (1 << (Int(p & 7) + 1)) }
                j += 1
                let e = skipBlocks(j); out += b[i..<e]; i = e
            default:
                break loop
            }
        }
        out.append(0x3B)
        return (Data(out), removed)
    }

    static func preview(_ url: URL, _ kind: Kind) -> (NSImage?, String) {
        if kind == .pdf {
            guard let doc = PDFDocument(url: url) else { return (nil, "") }
            let n = doc.pageCount
            let img = doc.page(at: 0)?.thumbnail(of: CGSize(width: 96, height: 96), for: .cropBox)
            return (img, n == 1 ? String(localized: "1 Seite") : String(localized: "\(n) Seiten"))
        }
        guard let src = try? source(url) else { return (nil, "") }
        let p = props(src)
        var info = ""
        if let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int {
            let o = p[kCGImagePropertyOrientation] as? Int ?? 1
            info = o >= 5 ? "\(h) × \(w)" : "\(w) × \(h)"
        }
        let frames = CGImageSourceGetCount(src)
        if frames > 1 { info += String(localized: " · \(frames) Bilder") }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 96]
        let t = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        return (t.map { NSImage(cgImage: $0, size: .zero) }, info)
    }
}

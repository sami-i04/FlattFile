import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

struct MetaSection: Identifiable {
    let id = UUID()
    let title: String
    var rows: [(String, String)]
}

enum Meta {
    static let labels: [String: String] = [
        "PixelWidth": String(localized: "Breite (px)"), "PixelHeight": String(localized: "Höhe (px)"), "DPIWidth": String(localized: "DPI horizontal"), "DPIHeight": String(localized: "DPI vertikal"),
        "ColorModel": String(localized: "Farbmodell"), "ProfileName": String(localized: "Farbprofil"), "Depth": String(localized: "Bittiefe"), "Orientation": String(localized: "Ausrichtung"),
        "HasAlpha": String(localized: "Transparenz"), "DateTimeOriginal": String(localized: "Aufnahmedatum"), "DateTimeDigitized": String(localized: "Digitalisiert"),
        "DateTime": String(localized: "Datum"), "Make": String(localized: "Hersteller"), "Model": String(localized: "Modell"), "LensModel": String(localized: "Objektiv"), "LensMake": String(localized: "Objektiv-Hersteller"),
        "ExposureTime": String(localized: "Belichtungszeit"), "FNumber": String(localized: "Blende"), "ISOSpeedRatings": "ISO", "FocalLength": String(localized: "Brennweite"),
        "FocalLenIn35mmFilm": String(localized: "Brennweite (KB)"), "Software": String(localized: "Software"), "Artist": String(localized: "Urheber"), "Copyright": String(localized: "Copyright"),
        "Latitude": String(localized: "Breitengrad"), "Longitude": String(localized: "Längengrad"), "Altitude": String(localized: "Höhe über NN"), "LatitudeRef": String(localized: "Breite (N/S)"),
        "LongitudeRef": String(localized: "Länge (E/W)"), "Flash": String(localized: "Blitz"), "WhiteBalance": String(localized: "Weißabgleich"), "ExposureProgram": String(localized: "Belichtungsprogramm"),
        "ImageDescription": String(localized: "Beschreibung"), "HostComputer": String(localized: "Gerät"), "LoopCount": String(localized: "Wiederholungen"),
        "DelayTime": String(localized: "Verzögerung (s)"), "FileSize": String(localized: "Dateigröße (Bytes)"),
    ]
    static let sectionTitles: [String: String] = [
        "{Exif}": String(localized: "EXIF (Kamera)"), "{GPS}": String(localized: "GPS (Standort)"), "{TIFF}": "TIFF", "{IPTC}": "IPTC",
        "{ExifAux}": String(localized: "EXIF Zusatz"), "{MakerApple}": String(localized: "Apple"), "{JFIF}": "JFIF", "{PNG}": "PNG", "{GIF}": "GIF",
        "{WebP}": "WebP", "{HEICS}": "HEIC", "{DNG}": "DNG", "{8BIM}": String(localized: "Photoshop"),
    ]
    static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    static func fmt(_ v: Any) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? String(localized: "Ja") : String(localized: "Nein") }
            let d = n.doubleValue
            if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
            return String(format: "%.4g", d)
        case let a as [Any]: return a.map(fmt).joined(separator: ", ")
        case let d as [AnyHashable: Any]:
            return d.map { "\($0.key): \(fmt($0.value))" }.sorted().joined(separator: "; ")
        case let d as Data: return bytes(Int64(d.count))
        case let d as Date: return dateFmt.string(from: d)
        default: return "\(v)"
        }
    }

    static func rows(_ dict: [String: Any]) -> [(String, String)] {
        dict.map { (labels[$0.key] ?? $0.key, fmt($0.value)) }
            .filter { !$0.1.isEmpty }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    static func read(_ url: URL, _ kind: Kind) -> (sections: [MetaSection], gps: Bool) {
        var general: [(String, String)] = [
            (String(localized: "Name"), url.lastPathComponent),
            (String(localized: "Ordner"), (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath),
            (String(localized: "Format"), kind.label),
        ]
        if let a = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let s = a[.size] as? Int64 { general.append((String(localized: "Größe"), bytes(s))) }
            if let d = a[.creationDate] as? Date { general.append((String(localized: "Erstellt"), dateFmt.string(from: d))) }
            if let d = a[.modificationDate] as? Date { general.append((String(localized: "Geändert"), dateFmt.string(from: d))) }
        }
        var sections: [MetaSection] = []
        var gps = false

        if kind == .pdf {
            if let doc = PDFDocument(url: url) {
                general.append((String(localized: "Seiten"), "\(doc.pageCount)"))
                general.append(("PDF-Version", "\(doc.majorVersion).\(doc.minorVersion)"))
                general.append((String(localized: "Verschlüsselt"), doc.isEncrypted ? String(localized: "Ja") : String(localized: "Nein")))
                if let p = doc.page(at: 0) {
                    let r = p.bounds(for: .mediaBox)
                    general.append((String(localized: "Seitenformat"), String(format: "%.0f × %.0f mm", r.width / 72 * 25.4, r.height / 72 * 25.4)))
                }
                let names: [String: String] = ["Title": String(localized: "Titel"), "Author": String(localized: "Autor"), "Subject": String(localized: "Thema"), "Creator": String(localized: "Erstellt mit"),
                                               "Producer": String(localized: "Erzeugt von"), "CreationDate": String(localized: "Erstellungsdatum"),
                                               "ModDate": String(localized: "Änderungsdatum"), "Keywords": String(localized: "Schlüsselwörter")]
                var r: [(String, String)] = []
                for (k, v) in doc.documentAttributes ?? [:] {
                    let key = "\(k)"
                    r.append((names[key] ?? key, fmt(v)))
                }
                sections.append(MetaSection(title: String(localized: "Dokument-Infos"), rows: r.sorted { $0.0 < $1.0 }))
            }
        } else if let src = try? Engine.source(url) {
            let frames = CGImageSourceGetCount(src)
            if frames > 1 { general.append((String(localized: "Bilder / Frames"), "\(frames)")) }
            if let fp = CGImageSourceCopyProperties(src, nil) as? [String: Any] {
                for (k, v) in fp { if let d = v as? [String: Any], k != "{GIF}" || frames > 0 {
                    sections.append(MetaSection(title: (sectionTitles[k] ?? k.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))) + " (Datei)", rows: rows(d)))
                } }
            }
            let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
            var image: [String: Any] = [:]
            for (k, v) in p {
                if let d = v as? [String: Any] {
                    if k == "{GPS}" { gps = !d.isEmpty }
                    let t = sectionTitles[k] ?? k.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                    sections.append(MetaSection(title: t, rows: rows(d)))
                } else { image[k] = v }
            }
            if !image.isEmpty { sections.insert(MetaSection(title: String(localized: "Bild"), rows: rows(image)), at: 0) }
            if let xmp = CGImageSourceCopyMetadataAtIndex(src, 0, nil), let tags = CGImageMetadataCopyTags(xmp) as? [CGImageMetadataTag] {
                var r: [(String, String)] = []
                for t in tags {
                    let prefix = CGImageMetadataTagCopyPrefix(t) as String? ?? ""
                    guard ["xmp", "dc", "photoshop", "xmpMM", "Iptc4xmpCore", "aux", "xmpRights"].contains(prefix) else { continue }
                    let name = CGImageMetadataTagCopyName(t) as String? ?? "?"
                    let v = CGImageMetadataTagCopyValue(t).map { fmt($0) } ?? ""
                    r.append(("\(prefix):\(name)", v))
                }
                if !r.isEmpty { sections.append(MetaSection(title: "XMP", rows: r.sorted { $0.0 < $1.0 })) }
            }
        }
        if kind.metaOnly, let d = try? Data(contentsOf: url),
           let (_, removed) = try? (kind == .gif ? Engine.stripGIF(d) : Engine.stripWebP(d)) {
            sections.append(MetaSection(title: String(localized: "Entfernbare Blöcke"),
                                        rows: removed.isEmpty ? [("–", String(localized: "Keine gefunden"))] : removed.map { (String(localized: "Block"), $0) }))
        }
        let order = [String(localized: "Bild"), String(localized: "GPS (Standort)"), String(localized: "EXIF (Kamera)"), "TIFF", "IPTC", "XMP"]
        sections.sort { (order.firstIndex(of: $0.title) ?? 99) < (order.firstIndex(of: $1.title) ?? 99) }
        sections.removeAll { $0.rows.isEmpty }
        return ([MetaSection(title: String(localized: "Allgemein"), rows: general)] + sections, gps)
    }
}

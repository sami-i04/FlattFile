import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

enum Kind: String {
    case pdf, jpeg, png, heic, tiff, bmp, webp, gif, raw

    static func detect(_ url: URL) -> Kind? {
        guard let t = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if t.conforms(to: .pdf) { return .pdf }
        if t.conforms(to: .rawImage) { return .raw }
        if t.conforms(to: .jpeg) { return .jpeg }
        if t.conforms(to: .png) { return .png }
        if t.conforms(to: .heic) || t.conforms(to: .heif) { return .heic }
        if t.conforms(to: .tiff) { return .tiff }
        if t.conforms(to: .bmp) { return .bmp }
        if t.conforms(to: .webP) { return .webp }
        if t.conforms(to: .gif) { return .gif }
        return nil
    }

    var label: String {
        switch self {
        case .pdf: "PDF"; case .jpeg: "JPEG"; case .png: "PNG"; case .heic: "HEIC"; case .tiff: "TIFF"
        case .bmp: "BMP"; case .webp: "WebP"; case .gif: "GIF"; case .raw: "RAW"
        }
    }

    var metaOnly: Bool { self == .webp || self == .gif }
    var canStripMeta: Bool { self != .bmp && self != .raw }

    var methodHint: String {
        switch self {
        case .pdf: String(localized: "Bilder werden neu komprimiert")
        case .jpeg, .heic: String(localized: "Neu kodieren")
        case .png: String(localized: "Farbreduktion")
        case .tiff: String(localized: "Verlustfrei (LZW)")
        case .bmp: String(localized: "Umwandeln in PNG")
        case .webp, .gif: String(localized: "Nur Metadaten")
        case .raw: String(localized: "Umwandeln")
        }
    }
}

enum RawOut: String, CaseIterable { case jpeg, heic }

struct Settings {
    var quality: Double
    var maxDim: Int
    var strip: Bool
    var rawOut: RawOut
    var folder: URL?
}

struct FFError: LocalizedError {
    let msg: String
    init(_ m: String) { msg = m }
    var errorDescription: String? { msg }
}

enum Outcome {
    case written(URL, Int64, String?)
    case skipped(String)
}

func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

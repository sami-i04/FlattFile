import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

struct Pixels {
    var data: [UInt8]
    let w: Int, h: Int
    let opaque: Bool
}

enum PNGKit {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    static func rgba(_ img: CGImage) -> Pixels {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { p in
            let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var opaque = true
        buf.withUnsafeMutableBufferPointer { p in
            var i = 0
            while i < p.count {
                let a = Int(p[i + 3])
                if a == 0 { p[i] = 0; p[i+1] = 0; p[i+2] = 0; opaque = false }
                else if a < 255 {
                    opaque = false
                    p[i]   = UInt8(min(255, (Int(p[i])   * 255 + a / 2) / a))
                    p[i+1] = UInt8(min(255, (Int(p[i+1]) * 255 + a / 2) / a))
                    p[i+2] = UInt8(min(255, (Int(p[i+2]) * 255 + a / 2) / a))
                }
                i += 4
            }
        }
        return Pixels(data: buf, w: w, h: h, opaque: opaque)
    }

    static func opaqueCopy(_ img: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: img.colorSpace ?? srgb,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage()
    }

    static func exactPalette(_ px: Pixels) -> ([SIMD4<Float>], [UInt8])? {
        var map: [UInt32: UInt8] = [:]
        var pal: [SIMD4<Float>] = []
        var idx = [UInt8](repeating: 0, count: px.w * px.h)
        var last: UInt32 = 0xFFFF_FFFF, lastI: UInt8 = 0
        let ok: Bool = px.data.withUnsafeBufferPointer { p in
            for n in 0..<(px.w * px.h) {
                let o = n * 4
                let c = UInt32(p[o]) << 24 | UInt32(p[o+1]) << 16 | UInt32(p[o+2]) << 8 | UInt32(p[o+3])
                if c == last { idx[n] = lastI; continue }
                if let i = map[c] { idx[n] = i; last = c; lastI = i; continue }
                if pal.count == 256 { return false }
                let i = UInt8(pal.count)
                map[c] = i
                pal.append(SIMD4(Float(p[o]), Float(p[o+1]), Float(p[o+2]), Float(p[o+3])))
                idx[n] = i; last = c; lastI = i
            }
            return true
        }
        guard ok else { return nil }
        return sortByAlpha(pal, idx)
    }

    static func sortByAlpha(_ pal: [SIMD4<Float>], _ idx: [UInt8]) -> ([SIMD4<Float>], [UInt8]) {
        let order = pal.indices.sorted { pal[$0].w < pal[$1].w }
        var remap = [UInt8](repeating: 0, count: 256)
        for (new, old) in order.enumerated() { remap[old] = UInt8(new) }
        return (order.map { pal[$0] }, idx.map { remap[Int($0)] })
    }

    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc(_ data: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }

    static func zlib(_ src: [UInt8]) -> [UInt8] {
        var dst = [UInt8](repeating: 0, count: src.count + src.count / 8 + 4096)
        let n = src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                compression_encode_buffer(d.baseAddress!, d.count, s.baseAddress!, s.count, nil, COMPRESSION_ZLIB)
            }
        }
        var a: UInt32 = 1, b: UInt32 = 0
        var i = 0
        while i < src.count {
            let end = min(i + 5552, src.count)
            while i < end { a += UInt32(src[i]); b += a; i += 1 }
            a %= 65521; b %= 65521
        }
        return [0x78, 0xDA] + dst[0..<n] + be32(b << 16 | a)
    }

    static func writeIndexed(w: Int, h: Int, palette: [SIMD4<Float>], indices: [UInt8]) -> Data {
        let n = palette.count
        let depth = n <= 2 ? 1 : n <= 4 ? 2 : n <= 16 ? 4 : 8
        let rowBytes = (w * depth + 7) / 8
        var raw = [UInt8](repeating: 0, count: h * (rowBytes + 1))
        raw.withUnsafeMutableBufferPointer { r in
            indices.withUnsafeBufferPointer { ix in
                for y in 0..<h {
                    let o = y * (rowBytes + 1) + 1
                    if depth == 8 {
                        for x in 0..<w { r[o + x] = ix[y * w + x] }
                    } else {
                        for x in 0..<w {
                            let bit = x * depth
                            r[o + bit / 8] |= ix[y * w + x] << UInt8(8 - depth - bit % 8)
                        }
                    }
                }
            }
        }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let t = Array(type.utf8)
            return be32(UInt32(body.count)) + t + body + be32(crc(t + body))
        }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        out += chunk("IHDR", be32(UInt32(w)) + be32(UInt32(h)) + [UInt8(depth), 3, 0, 0, 0])
        out += chunk("sRGB", [0])
        out += chunk("PLTE", palette.flatMap { [UInt8($0.x.rounded()), UInt8($0.y.rounded()), UInt8($0.z.rounded())] })
        let alphas = palette.map { UInt8($0.w.rounded()) }
        if let lastT = alphas.lastIndex(where: { $0 < 255 }) { out += chunk("tRNS", Array(alphas[0...lastT])) }
        out += chunk("IDAT", zlib(raw))
        out += chunk("IEND", [])
        return Data(out)
    }
}

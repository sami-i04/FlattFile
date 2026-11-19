import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

enum Quant {
    @inline(__always) static func dist(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
        let d = a - b
        let am = max(a.w, b.w) * (1 / 255)
        return (d.x * d.x * 0.299 + d.y * d.y * 0.587 + d.z * d.z * 0.114) * am + d.w * d.w * 0.6
    }

    @inline(__always) static func nearest(_ c: SIMD4<Float>, _ pal: [SIMD4<Float>]) -> Int {
        var best = 0, bd = Float.greatestFiniteMagnitude
        for i in 0..<pal.count {
            let d = dist(c, pal[i])
            if d < bd { bd = d; best = i }
        }
        return best
    }

    static func palette(_ px: Pixels, colors k: Int) -> [SIMD4<Float>] {
        let n = px.w * px.h
        let step = max(1, n / 1_000_000)
        let size = 1 << 20
        var cnt = [UInt32](repeating: 0, count: size)
        var sr = cnt, sg = cnt, sb = cnt, sa = cnt
        var hasTransparent = false
        px.data.withUnsafeBufferPointer { p in
            var i = 0
            while i < n {
                let o = i * 4
                let a = p[o + 3]
                if a == 0 { hasTransparent = true }
                else {
                    let key = Int(p[o] >> 3) << 15 | Int(p[o+1] >> 3) << 10 | Int(p[o+2] >> 3) << 5 | Int(a >> 3)
                    cnt[key] += 1
                    sr[key] += UInt32(p[o]); sg[key] += UInt32(p[o+1]); sb[key] += UInt32(p[o+2]); sa[key] += UInt32(a)
                }
                i += step
            }
        }
        var col: [SIMD4<Float>] = [], wt: [Float] = []
        for key in 0..<size where cnt[key] > 0 {
            let c = Float(cnt[key])
            col.append(SIMD4(Float(sr[key]) / c, Float(sg[key]) / c, Float(sb[key]) / c, Float(sa[key]) / c))
            wt.append(c)
        }
        let target = hasTransparent ? k - 1 : k
        var pal: [SIMD4<Float>]
        if col.count <= target {
            pal = col
        } else {
            let chW = SIMD4<Float>(1.0, 1.2, 0.9, 1.4)
            var boxes: [[Int]] = [Array(0..<col.count)]
            while boxes.count < target {
                var bi = -1, bs: Float = 0
                for (j, bx) in boxes.enumerated() where bx.count > 1 {
                    var lo = SIMD4<Float>(repeating: 255), hi = SIMD4<Float>(repeating: 0), ws: Float = 0
                    for e in bx { lo = pointwiseMin(lo, col[e]); hi = pointwiseMax(hi, col[e]); ws += wt[e] }
                    let r = (hi - lo) * chW
                    let score = r.max() * ws.squareRoot()
                    if score > bs { bs = score; bi = j }
                }
                if bi < 0 { break }
                let bx = boxes[bi]
                var lo = SIMD4<Float>(repeating: 255), hi = SIMD4<Float>(repeating: 0)
                for e in bx { lo = pointwiseMin(lo, col[e]); hi = pointwiseMax(hi, col[e]) }
                let r = (hi - lo) * chW
                let axis = r.x >= r.y && r.x >= r.z && r.x >= r.w ? 0 : r.y >= r.z && r.y >= r.w ? 1 : r.z >= r.w ? 2 : 3
                let sorted = bx.sorted { col[$0][axis] < col[$1][axis] }
                let half = sorted.reduce(Float(0)) { $0 + wt[$1] } / 2
                var acc: Float = 0, cut = 1
                for (m, e) in sorted.enumerated() {
                    acc += wt[e]
                    if acc >= half { cut = m + 1; break }
                }
                cut = min(max(cut, 1), sorted.count - 1)
                boxes[bi] = Array(sorted[0..<cut])
                boxes.append(Array(sorted[cut...]))
            }
            pal = boxes.map { bx in
                var s = SIMD4<Float>(repeating: 0), ws: Float = 0
                for e in bx { s += col[e] * wt[e]; ws += wt[e] }
                return s / ws
            }
            for _ in 0..<4 {
                var sums = [SIMD4<Float>](repeating: .zero, count: pal.count)
                var ws = [Float](repeating: 0, count: pal.count)
                for e in 0..<col.count {
                    let j = nearest(col[e], pal)
                    sums[j] += col[e] * wt[e]; ws[j] += wt[e]
                }
                for j in 0..<pal.count where ws[j] > 0 { pal[j] = sums[j] / ws[j] }
            }
        }
        pal = pal.map { pointwiseMin(pointwiseMax($0.rounded(.toNearestOrEven), .zero), SIMD4(repeating: 255)) }
        if hasTransparent { pal.append(.zero) }
        return pal
    }

    static func remap(_ px: Pixels, palette pal: [SIMD4<Float>]) -> [UInt8] {
        let w = px.w, h = px.h
        var out = [UInt8](repeating: 0, count: w * h)
        var cache = [Int16](repeating: -1, count: 1 << 22)
        var cur = [SIMD4<Float>](repeating: .zero, count: w + 2)
        var nxt = cur
        let trans = pal.firstIndex { $0.w == 0 }
        px.data.withUnsafeBufferPointer { p in
            for y in 0..<h {
                for x in 0..<w {
                    let o = (y * w + x) * 4
                    let a = p[o + 3]
                    if a == 0, let t = trans { out[y * w + x] = UInt8(t); continue }
                    var c = SIMD4<Float>(Float(p[o]), Float(p[o+1]), Float(p[o+2]), Float(a)) + cur[x + 1]
                    c = pointwiseMin(pointwiseMax(c, .zero), SIMD4(repeating: 255))
                    let key = (Int(c.x) >> 2) << 16 | (Int(c.y) >> 2) << 10 | (Int(c.z) >> 2) << 4 | Int(c.w) >> 4
                    var j = Int(cache[key])
                    if j < 0 { j = nearest(c, pal); cache[key] = Int16(j) }
                    out[y * w + x] = UInt8(j)
                    var e = (c - pal[j]) * 0.8
                    e.w = 0
                    cur[x + 2] += e * (7 / 16)
                    nxt[x]     += e * (3 / 16)
                    nxt[x + 1] += e * (5 / 16)
                    nxt[x + 2] += e * (1 / 16)
                }
                swap(&cur, &nxt)
                for i in 0..<nxt.count { nxt[i] = .zero }
            }
        }
        return out
    }
}

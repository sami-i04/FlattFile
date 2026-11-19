import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func linear(_ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func rounded(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tile = rounded(tileRect, 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x000000, 0.28))
ctx.addPath(tile); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
ctx.restoreGState()
linear(tile, [rgb(0xFFFFFF), rgb(0xEEF0F3)], from: CGPoint(x: 0, y: 924), to: CGPoint(x: 0, y: 100))
ctx.saveGState()
ctx.addPath(rounded(tileRect.insetBy(dx: 1.5, dy: 1.5), 183.5))
ctx.setStrokeColor(rgb(0x000000, 0.07)); ctx.setLineWidth(3); ctx.strokePath()
ctx.restoreGState()

let L: CGFloat = 214, R: CGFloat = 810, B: CGFloat = 262
let bodyTop: CGFloat = 690, tabTop: CGFloat = 748
let tabRight: CGFloat = 440, rad: CGFloat = 40

let back = CGMutablePath()
back.move(to: CGPoint(x: L + rad, y: B))
back.addLine(to: CGPoint(x: R - rad, y: B))
back.addQuadCurve(to: CGPoint(x: R, y: B + rad), control: CGPoint(x: R, y: B))
back.addLine(to: CGPoint(x: R, y: bodyTop - 30))
back.addQuadCurve(to: CGPoint(x: R - 30, y: bodyTop), control: CGPoint(x: R, y: bodyTop))
back.addLine(to: CGPoint(x: tabRight + 52, y: bodyTop))
back.addCurve(to: CGPoint(x: tabRight - 6, y: tabTop - 14),
              control1: CGPoint(x: tabRight + 22, y: bodyTop),
              control2: CGPoint(x: tabRight + 18, y: tabTop - 14))
back.addQuadCurve(to: CGPoint(x: tabRight - 34, y: tabTop), control: CGPoint(x: tabRight - 20, y: tabTop))
back.addLine(to: CGPoint(x: L + 30, y: tabTop))
back.addQuadCurve(to: CGPoint(x: L, y: tabTop - 30), control: CGPoint(x: L, y: tabTop))
back.addLine(to: CGPoint(x: L, y: B + rad))
back.addQuadCurve(to: CGPoint(x: L + rad, y: B), control: CGPoint(x: L, y: B))
back.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: rgb(0x8A5A00, 0.30))
ctx.addPath(back); ctx.setFillColor(rgb(0xE9A400)); ctx.fillPath()
ctx.restoreGState()
linear(back, [rgb(0xF2B21C), rgb(0xD99400)], from: CGPoint(x: 0, y: tabTop), to: CGPoint(x: 0, y: B))

func sheet(_ r: CGRect, angle: CGFloat, fill: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: r.midX, y: r.midY); ctx.rotate(by: angle * .pi / 180)
    let p = rounded(CGRect(x: -r.width / 2, y: -r.height / 2, width: r.width, height: r.height), 14)
    ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: rgb(0x000000, 0.18))
    ctx.addPath(p); ctx.setFillColor(fill); ctx.fillPath()
    ctx.restoreGState()
}
sheet(CGRect(x: 270, y: 380, width: 470, height: 340), angle: -3.5, fill: rgb(0xE8EBEF))
sheet(CGRect(x: 282, y: 372, width: 462, height: 330), angle: 2.0, fill: rgb(0xFFFFFF))

ctx.saveGState()
ctx.translateBy(x: 513, y: 537); ctx.rotate(by: 2.0 * .pi / 180)
for (i, w) in [300, 250, 280].enumerated() {
    let y = CGFloat(110 - i * 34)
    ctx.addPath(rounded(CGRect(x: -190, y: y, width: CGFloat(w), height: 12), 6))
}
ctx.setFillColor(rgb(0xC9CED6)); ctx.fillPath()
ctx.restoreGState()

let fTop: CGFloat = 612, inset: CGFloat = 0
let front = CGMutablePath()
front.move(to: CGPoint(x: L + rad, y: B))
front.addLine(to: CGPoint(x: R - rad, y: B))
front.addQuadCurve(to: CGPoint(x: R, y: B + rad), control: CGPoint(x: R, y: B))
front.addLine(to: CGPoint(x: R + inset, y: fTop - 26))
front.addQuadCurve(to: CGPoint(x: R + inset - 28, y: fTop), control: CGPoint(x: R + inset, y: fTop))
front.addLine(to: CGPoint(x: L - inset + 28, y: fTop))
front.addQuadCurve(to: CGPoint(x: L - inset, y: fTop - 26), control: CGPoint(x: L - inset, y: fTop))
front.addLine(to: CGPoint(x: L, y: B + rad))
front.addQuadCurve(to: CGPoint(x: L + rad, y: B), control: CGPoint(x: L, y: B))
front.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 18, color: rgb(0x7A4E00, 0.28))
ctx.addPath(front); ctx.setFillColor(rgb(0xFFC51F)); ctx.fillPath()
ctx.restoreGState()
linear(front, [rgb(0xFFDA55), rgb(0xFFC21C), rgb(0xF7B000)],
       from: CGPoint(x: 0, y: fTop), to: CGPoint(x: 0, y: B))

ctx.saveGState()
ctx.addPath(front); ctx.clip()
ctx.addPath(rounded(CGRect(x: L - 10, y: fTop - 7, width: R - L + 20, height: 30), 0))
ctx.setFillColor(rgb(0xFFEC9E, 0.9)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(front); ctx.setStrokeColor(rgb(0xB57A00, 0.35)); ctx.setLineWidth(2); ctx.strokePath()
ctx.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))

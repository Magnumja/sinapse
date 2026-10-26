// Coloca um print de janela sobre um fundo escuro, com cantos arredondados, botões de janela e sombra.
// Uso: swift Tools/frame_screenshot.swift entrada.png saida.png
import AppKit

let args = CommandLine.arguments
let input = NSImage(contentsOfFile: args[1])!
var rect = CGRect(origin: .zero, size: input.size)
let shot = input.cgImage(forProposedRect: &rect, context: nil, hints: nil)!

let w = CGFloat(shot.width), h = CGFloat(shot.height)
let pad: CGFloat = 120
let size = CGSize(width: w + pad * 2, height: h + pad * 2)
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// Fundo
let bg = CGGradient(
    colorsSpace: space,
    colors: [CGColor(gray: 0.20, alpha: 1), CGColor(gray: 0.04, alpha: 1)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])

// Janela com sombra
let window = CGRect(x: pad, y: pad, width: w, height: h)
let path = CGPath(roundedRect: window, cornerWidth: 26, cornerHeight: 26, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 70, color: CGColor(gray: 0, alpha: 0.6))
ctx.addPath(path)
ctx.setFillColor(gray: 0.15, alpha: 1)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path)
ctx.clip()
ctx.draw(shot, in: window)
// Botões da janela (cinza, como numa janela inativa)
for i in 0..<3 {
    let c = CGRect(x: window.minX + 28 + CGFloat(i) * 40, y: window.maxY - 52, width: 24, height: 24)
    ctx.setFillColor(gray: 1, alpha: 0.18)
    ctx.fillEllipse(in: c)
}
ctx.restoreGState()

// Borda fina
ctx.addPath(path)
ctx.setStrokeColor(gray: 1, alpha: 0.12)
ctx.setLineWidth(2)
ctx.strokePath()

let out = URL(fileURLWithPath: args[2])
let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("ok", out.lastPathComponent)

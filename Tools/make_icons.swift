// Gera os ícones a partir do logo (linhas brancas sobre fundo preto).
// Uso: swift Tools/make_icons.swift Assets/logo-source.png Assets
import AppKit
import CoreImage

let args = CommandLine.arguments
let source = CIImage(contentsOf: URL(fileURLWithPath: args[1]))!
let outDir = URL(fileURLWithPath: args[2])
let ci = CIContext()
let W = source.extent.width

func centered(_ fraction: CGFloat) -> CGRect {
    let s = W * fraction
    return CGRect(x: (W - s) / 2, y: (source.extent.height - s) / 2, width: s, height: s)
}

/// Linhas do logo como máscara (branco + alfa), recortadas e escaladas. `thicken` engrossa o traço para tamanhos pequenos.
func mask(px: Int, fraction: CGFloat, thicken: Double) -> CGImage {
    let crop = centered(fraction)
    var img = source
    if thicken > 0 { img = img.applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": thicken]) }
    img = img.cropped(to: crop)
        .applyingFilter("CIMaskToAlpha")
        .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        .applyingFilter("CILanczosScaleTransform", parameters: [
            "inputScale": CGFloat(px) / crop.width, "inputAspectRatio": 1.0,
        ])
    return ci.createCGImage(img, from: CGRect(x: 0, y: 0, width: px, height: px))!
}

func write(_ image: CGImage, _ name: String) {
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("ok", name)
}

// Barra de menu (template 18pt) e marca usada dentro do app.
write(mask(px: 18, fraction: 0.47, thicken: 9), "MenuIcon.png")
write(mask(px: 36, fraction: 0.47, thicken: 9), "MenuIcon@2x.png")
write(mask(px: 256, fraction: 0.47, thicken: 3), "LogoMark.png")

// Ícone do app: quadrado arredondado preto com leve gradiente, sombra e o logo em branco.
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(path)
ctx.setFillColor(gray: 0, alpha: 1)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: space,
    colors: [CGColor(gray: 0.17, alpha: 1), CGColor(gray: 0.02, alpha: 1)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.draw(mask(px: 824, fraction: 0.66, thicken: 1), in: tile)
ctx.addPath(path)
ctx.setStrokeColor(gray: 1, alpha: 0.10)
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

write(ctx.makeImage()!, "AppIcon-1024.png")

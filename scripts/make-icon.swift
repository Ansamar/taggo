// Genera Resources/AppIcon.png (monogramma T!).  Uso: swift scripts/make-icon.swift Resources/AppIcon.png
import AppKit

// Monogramma "T!" ricostruito dallo screenshot: coordinate nel riquadro 256×256 dell'icona.
let size = 1024.0, inset = 100.0, s = (size - 2 * inset) / 256
let blue = CGColor(srgbRed: 0x2F/255, green: 0x6B/255, blue: 0xFF/255, alpha: 1)
let ink = CGColor(srgbRed: 0x12/255, green: 0x14/255, blue: 0x18/255, alpha: 1)

let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)

// Fondo: quadrato arrotondato secondo la griglia delle icone macOS (824 px, raggio ~185).
ctx.addPath(CGPath(roundedRect: CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset),
                   cornerWidth: 185, cornerHeight: 185, transform: nil))
ctx.setFillColor(blue); ctx.fillPath()

ctx.translateBy(x: inset, y: inset); ctx.scaleBy(x: s, y: s)

// T con l'estremità sinistra a forma di cartellino (misure prese dal PDF del logo).
func corner(_ path: CGMutablePath, _ x: CGFloat, _ y: CGFloat, _ nx: CGFloat, _ ny: CGFloat, _ r: CGFloat) {
    path.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: nx, y: ny), radius: r)
}
let t = CGMutablePath()
t.move(to: CGPoint(x: 150, y: 45.3))
corner(t, 216.3, 45.3, 216.3, 98.7, 7)
corner(t, 216.3, 98.7, 161.7, 98.7, 7)
t.addLine(to: CGPoint(x: 161.7, y: 98.7))
corner(t, 161.7, 173.7, 118, 173.7, 3)
corner(t, 118, 173.7, 118, 98.7, 3)
t.addLine(to: CGPoint(x: 118, y: 98.7))
corner(t, 85.5, 98.7, 63.3, 72, 2.5)
corner(t, 63.3, 72, 85.5, 45.3, 2)
corner(t, 85.5, 45.3, 150, 45.3, 2.5)
t.closeSubpath()
ctx.addPath(t); ctx.setFillColor(.white); ctx.fillPath()

// Foro del cartellino e punto esclamativo.
ctx.setFillColor(blue); ctx.fillEllipse(in: CGRect(x: 88 - 7.7, y: 71.9 - 7.7, width: 15.4, height: 15.4))
ctx.setFillColor(ink); ctx.fillEllipse(in: CGRect(x: 139.8 - 21.3, y: 203.8 - 21.3, width: 42.6, height: 42.6))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

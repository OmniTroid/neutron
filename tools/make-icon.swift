// Renders the app icon: swift tools/make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    let inset: CGFloat = 100
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(squircle)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let background = CGGradient(colorsSpace: nil, colors: [
        NSColor(red: 0.105, green: 0.196, blue: 0.318, alpha: 1).cgColor,
        NSColor(red: 0.039, green: 0.059, blue: 0.094, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    let center = CGPoint(x: size / 2, y: size / 2)
    let glow = CGGradient(colorsSpace: nil, colors: [
        NSColor(red: 0.40, green: 0.75, blue: 0.96, alpha: 0.35).cgColor,
        NSColor(red: 0.40, green: 0.75, blue: 0.96, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 360, options: [])

    let orbitColor = NSColor(red: 0.62, green: 0.85, blue: 1.0, alpha: 1).cgColor
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: 28 * .pi / 180)
    let orbit = CGRect(x: -330, y: -120, width: 660, height: 240)
    ctx.setLineWidth(18)
    ctx.setStrokeColor(orbitColor.copy(alpha: 0.9)!)
    ctx.strokeEllipse(in: orbit)
    // electron on the orbit, front-left
    let t = 2.55
    let electron = CGPoint(x: orbit.midX + cos(t) * orbit.width / 2, y: orbit.midY - sin(t) * orbit.height / 2)
    ctx.setShadow(offset: .zero, blur: 30, color: orbitColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: electron.x - 34, y: electron.y - 34, width: 68, height: 68))
    ctx.restoreGState()

    let nucleus = CGGradient(colorsSpace: nil, colors: [
        NSColor.white.cgColor,
        NSColor(red: 0.40, green: 0.75, blue: 0.96, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    let radius: CGFloat = 165
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: NSColor(red: 0.40, green: 0.75, blue: 0.96, alpha: 0.8).cgColor)
    ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ctx.clip()
    ctx.drawRadialGradient(nucleus, startCenter: CGPoint(x: center.x - 60, y: center.y + 60), startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
    ctx.restoreGState()

    // play triangle cut into the core
    let play = CGMutablePath()
    play.move(to: CGPoint(x: center.x - 48, y: center.y - 72))
    play.addLine(to: CGPoint(x: center.x - 48, y: center.y + 72))
    play.addLine(to: CGPoint(x: center.x + 78, y: center.y))
    play.closeSubpath()
    ctx.addPath(play)
    ctx.setFillColor(NSColor(red: 0.067, green: 0.125, blue: 0.204, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    return true
}

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: CommandLine.arguments[1]))

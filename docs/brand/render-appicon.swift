#!/usr/bin/env swift
import AppKit
import Foundation

enum Variant { case full, small }

func drawIcon(in rect: CGRect, variant: Variant) {
    let ctx = NSGraphicsContext.current!.cgContext

    let colors = [
        CGColor(srgbRed: 0x2a / 255, green: 0x31 / 255, blue: 0x42 / 255, alpha: 1),
        CGColor(srgbRed: 0x12 / 255, green: 0x15 / 255, blue: 0x1c / 255, alpha: 1)
    ]
    let spaces = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: spaces, colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    let brass = NSColor(srgbRed: 0xc4 / 255, green: 0xa2 / 255, blue: 0x5a / 255, alpha: 1).cgColor
    let scale = rect.width / 1024

    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * scale, y: rect.maxY - y * scale)
    }

    let stroke: CGFloat = (variant == .full ? 96 : 112) * scale
    ctx.setStrokeColor(brass)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let path = CGMutablePath()

    if variant == .full {
        path.move(to: P(560, 168))
        path.addCurve(to: P(280, 400), control1: P(360, 168), control2: P(280, 260))
        path.addCurve(to: P(560, 640), control1: P(280, 560), control2: P(420, 600))
        path.addCurve(to: P(700, 820), control1: P(660, 680), control2: P(700, 740))
        path.addCurve(to: P(480, 920), control1: P(700, 900), control2: P(580, 920))

        path.move(to: P(560, 168))
        path.addLine(to: P(560, 860))

        path.move(to: P(460, 360))
        path.addLine(to: P(660, 360))
    } else {
        path.move(to: P(560, 150))
        path.addCurve(to: P(260, 400), control1: P(340, 150), control2: P(260, 260))
        path.addCurve(to: P(560, 660), control1: P(260, 560), control2: P(420, 610))
        path.addCurve(to: P(720, 840), control1: P(680, 710), control2: P(720, 760))
        path.addCurve(to: P(460, 930), control1: P(720, 920), control2: P(560, 930))

        path.move(to: P(560, 150))
        path.addLine(to: P(560, 860))
    }

    ctx.addPath(path)
    ctx.strokePath()

    let pommelR = (variant == .full ? 56 : 72) * scale
    let pommel = P(560, variant == .full ? 900 : 910)
    ctx.setFillColor(brass)
    ctx.fillEllipse(in: CGRect(
        x: pommel.x - pommelR,
        y: pommel.y - pommelR,
        width: pommelR * 2,
        height: pommelR * 2
    ))
}

func render(pixels: Int, variant: Variant, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "bitmap"])
    }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    guard let gc = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        throw NSError(domain: "icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "context"])
    }
    NSGraphicsContext.current = gc
    gc.cgContext.setShouldAntialias(true)
    gc.cgContext.setAllowsAntialiasing(true)
    drawIcon(in: CGRect(x: 0, y: 0, width: pixels, height: pixels), variant: variant)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "png"])
    }
    try png.write(to: url)
    fputs("wrote \(url.lastPathComponent) (\(png.count) bytes)\n", stderr)
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath, isDirectory: true)
let brand = root.appendingPathComponent("docs/brand", isDirectory: true)
let iconset = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Clean broken @-named leftovers and test junk
let fm = FileManager.default
if let files = try? fm.contentsOfDirectory(atPath: iconset.path) {
    for name in files where name.contains("@") || name.hasPrefix("test") || name.contains("512b") {
        try? fm.removeItem(at: iconset.appendingPathComponent(name))
    }
}

struct Job { let px: Int; let variant: Variant; let name: String; let dir: URL }

// Use _2x suffix — "@" in filenames is unreliable with Foundation file URLs.
let jobs: [Job] = [
    Job(px: 16, variant: .small, name: "icon_16.png", dir: iconset),
    Job(px: 32, variant: .small, name: "icon_16_2x.png", dir: iconset),
    Job(px: 32, variant: .small, name: "icon_32.png", dir: iconset),
    Job(px: 64, variant: .full, name: "icon_32_2x.png", dir: iconset),
    Job(px: 128, variant: .full, name: "icon_128.png", dir: iconset),
    Job(px: 256, variant: .full, name: "icon_128_2x.png", dir: iconset),
    Job(px: 256, variant: .full, name: "icon_256.png", dir: iconset),
    Job(px: 512, variant: .full, name: "icon_256_2x.png", dir: iconset),
    Job(px: 512, variant: .full, name: "icon_512.png", dir: iconset),
    Job(px: 1024, variant: .full, name: "icon_512_2x.png", dir: iconset),
    Job(px: 1024, variant: .full, name: "symphonia-icon-1024.png", dir: brand),
]

for job in jobs {
    try render(pixels: job.px, variant: job.variant, to: job.dir.appendingPathComponent(job.name))
}

fputs("done (\(jobs.count) files)\n", stderr)

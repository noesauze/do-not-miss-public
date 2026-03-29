#!/usr/bin/env swift

import AppKit
import Foundation

struct IconSpec {
    let filename: String
    let size: Int
}

let specs: [IconSpec] = [
    .init(filename: "icon_16x16.png", size: 16),
    .init(filename: "icon_16x16@2x.png", size: 32),
    .init(filename: "icon_32x32.png", size: 32),
    .init(filename: "icon_32x32@2x.png", size: 64),
    .init(filename: "icon_128x128.png", size: 128),
    .init(filename: "icon_128x128@2x.png", size: 256),
    .init(filename: "icon_256x256.png", size: 256),
    .init(filename: "icon_256x256@2x.png", size: 512),
    .init(filename: "icon_512x512.png", size: 512),
    .init(filename: "icon_512x512@2x.png", size: 1024),
]

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_app_icons.swift <output-directory>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let image = NSImage(size: rect.size)

    image.lockFocus()

    NSGraphicsContext.current?.imageInterpolation = .high

    let radius = size * 0.23
    let inset = size * 0.055
    let baseRect = rect.insetBy(dx: inset, dy: inset)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    basePath.addClip()

    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.40, blue: 0.46, alpha: 1.0),
        NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.26, alpha: 1.0),
    ])!
    background.draw(in: baseRect, angle: -90)

    let glowRect = NSRect(x: baseRect.minX, y: baseRect.midY, width: baseRect.width, height: baseRect.height * 0.9)
    let glow = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.10),
        NSColor(calibratedWhite: 1.0, alpha: 0.0),
    ])!
    glow.draw(in: glowRect, angle: 90)

    NSGraphicsContext.restoreGraphicsState()

    let calendarInsetX = size * 0.18
    let calendarInsetTop = size * 0.18
    let calendarWidth = size - calendarInsetX * 2
    let calendarHeight = size * 0.50
    let calendarRect = NSRect(
        x: calendarInsetX,
        y: size - calendarInsetTop - calendarHeight,
        width: calendarWidth,
        height: calendarHeight
    )

    let calendarPath = NSBezierPath(roundedRect: calendarRect, xRadius: size * 0.08, yRadius: size * 0.08)
    NSColor(calibratedWhite: 1.0, alpha: 0.97).setFill()
    calendarPath.fill()

    let topBandHeight = calendarHeight * 0.27
    let topBandRect = NSRect(x: calendarRect.minX, y: calendarRect.maxY - topBandHeight, width: calendarRect.width, height: topBandHeight)
    let topBandPath = NSBezierPath(roundedRect: topBandRect, xRadius: size * 0.08, yRadius: size * 0.08)
    NSColor(calibratedRed: 0.82, green: 0.85, blue: 0.89, alpha: 1.0).setFill()
    topBandPath.fill()

    let ringWidth = size * 0.045
    let ringHeight = size * 0.11
    for xFactor in [0.3, 0.7] {
        let ringRect = NSRect(
            x: calendarRect.minX + calendarRect.width * CGFloat(xFactor) - ringWidth / 2,
            y: topBandRect.maxY - ringHeight * 0.45,
            width: ringWidth,
            height: ringHeight
        )
        let ringPath = NSBezierPath(roundedRect: ringRect, xRadius: ringWidth / 2, yRadius: ringWidth / 2)
        NSColor(calibratedRed: 0.32, green: 0.35, blue: 0.39, alpha: 1.0).setFill()
        ringPath.fill()
    }

    let lineColor = NSColor(calibratedRed: 0.78, green: 0.82, blue: 0.88, alpha: 1.0)
    let lineLeft = calendarRect.minX + size * 0.10
    let lineRight = calendarRect.maxX - size * 0.10
    let lineHeight = size * 0.032
    for yFactor in [0.58, 0.46, 0.34] {
        let lineRect = NSRect(
            x: lineLeft,
            y: size * CGFloat(yFactor),
            width: lineRight - lineLeft,
            height: lineHeight
        )
        let linePath = NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2)
        lineColor.setFill()
        linePath.fill()
    }

    let dotSize = size * 0.13
    let dotRect = NSRect(
        x: calendarRect.maxX - dotSize - size * 0.08,
        y: calendarRect.minY + size * 0.06,
        width: dotSize,
        height: dotSize
    )
    let dotPath = NSBezierPath(ovalIn: dotRect)
    NSColor(calibratedRed: 0.36, green: 0.58, blue: 0.84, alpha: 1.0).setFill()
    dotPath.fill()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.12)
    shadow.shadowBlurRadius = size * 0.04
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    NSColor(calibratedWhite: 1.0, alpha: 0.08).setStroke()
    basePath.lineWidth = max(1, size * 0.01)
    basePath.stroke()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation else {
        throw NSError(domain: "GenerateAppIcons", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }

    guard let sourceRep = NSBitmapImageRep(data: tiffData) else {
        throw NSError(domain: "GenerateAppIcons", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create source bitmap"])
    }

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(image.size.width),
        pixelsHigh: Int(image.size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )

    guard let targetRep = bitmap else {
        throw NSError(domain: "GenerateAppIcons", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to create target bitmap"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: targetRep)
    NSGraphicsContext.current?.imageInterpolation = .high
    sourceRep.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = targetRep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateAppIcons", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to create PNG data"])
    }

    try pngData.write(to: url)
}

for spec in specs {
    let image = drawIcon(size: CGFloat(spec.size))
    try writePNG(image, to: outputDirectory.appendingPathComponent(spec.filename))
    print("Generated \(spec.filename)")
}

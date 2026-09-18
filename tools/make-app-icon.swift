// Draws TodApp's app icon: the app's dark ground, a pink glow, and a short
// waveform running from the accent pink into gold -- the same colours the
// player's waveform plays in. 1024 x 1024, no transparency, square corners
// (iOS rounds them itself).
//
//     swift tools/make-app-icon.swift TodApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha)
}

// Brand tokens (docs/superpowers/specs/brand-spec.md).
let background = color(0x121014)
let surface = color(0x1c1a20)
let accent = color(0xb3527a)
let gold = color(0xe0b64a)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("no context") }

let size = CGFloat(side)
let full = CGRect(x: 0, y: 0, width: size, height: size)

// Ground: a faint lift at the top, the app's background below.
let ground = CGGradient(colorsSpace: space, colors: [surface, background] as CFArray, locations: [0, 1])!
context.drawLinearGradient(
    ground, start: CGPoint(x: size / 2, y: size), end: CGPoint(x: size / 2, y: 0), options: [])

// The glow behind the waveform.
let glow = CGGradient(
    colorsSpace: space, colors: [color(0xb3527a, 0.55), color(0xb3527a, 0)] as CFArray,
    locations: [0, 1])!
let centre = CGPoint(x: size / 2, y: size * 0.48)
context.drawRadialGradient(
    glow, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: size * 0.52, options: [])

// The waveform: seven bars, tallest in the middle.
let heights: [CGFloat] = [0.26, 0.46, 0.72, 1.0, 0.78, 0.5, 0.3]
let barWidth: CGFloat = 76
let gap: CGFloat = 40
let tallest: CGFloat = 560
let rowWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
let left = (size - rowWidth) / 2

let bars = CGMutablePath()
for (index, height) in heights.enumerated() {
    let h = tallest * height
    let rect = CGRect(
        x: left + CGFloat(index) * (barWidth + gap), y: centre.y - h / 2, width: barWidth, height: h)
    bars.addRoundedRect(in: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2)
}

context.saveGState()
context.addPath(bars)
context.clip()
let fill = CGGradient(colorsSpace: space, colors: [accent, gold] as CFArray, locations: [0.1, 0.9])!
context.drawLinearGradient(
    fill, start: CGPoint(x: left, y: 0), end: CGPoint(x: left + rowWidth, y: 0), options: [])
context.restoreGState()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("cannot write \(output)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("cannot finish \(output)") }
print("wrote \(output)")

#!/usr/bin/env swift
// Generates the app icon: the station circle at 3 oktas with a stiff
// south-westerly (25 kn — two full barbs and a half). Same geometry as
// weather_circle.py / StationPlot, drawn with CoreGraphics.
//
//   swift scripts/make_icon.swift /tmp/icon-1024.png
//
// Then copy the PNG into
// WeatherCircles/Assets.xcassets/AppIcon.appiconset/icon-1024.png.

import CoreGraphics
import Foundation
import ImageIO

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon-1024.png"
let size = 1024

// noneSkipLast: opaque RGB — App Store validation rejects 1024 icons
// that carry an alpha channel.
let context = CGContext(data: nil, width: size, height: size,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)                      // y-down, like the SVG space

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let background = rgb(0xF5F4EF)                    // warm paper, e-ink-ish
let ink = rgb(0x1A1A2E)

context.setFillColor(background)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// ── Original 260-space geometry, scaled and optically centred ─────────
// Content (circle + SW barb) is biased down-left, so shift up-right.
let scale = 3.35
context.translateBy(x: (CGFloat(size) - 260 * scale) / 2 + 62,
                    y: (CGFloat(size) - 260 * scale) / 2 - 58)
context.scaleBy(x: scale, y: scale)

let cx = 130.0, cy = 130.0, r = 64.0, stroke = 7.0, barbLen = 50.0
context.setStrokeColor(ink)
context.setFillColor(ink)
context.setLineCap(.round)

func pt(_ radius: Double, _ degFromTop: Double) -> CGPoint {
    let a = degFromTop * .pi / 180
    return CGPoint(x: cx + radius * sin(a), y: cy - radius * cos(a))
}
func line(_ a: CGPoint, _ b: CGPoint, width: Double) {
    context.setLineWidth(width)
    context.move(to: a)
    context.addLine(to: b)
    context.strokePath()
}

// Station circle
context.setLineWidth(stroke)
context.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))

// 3 oktas: 90° wedge from 12 o'clock + vertical line
context.move(to: CGPoint(x: cx, y: cy))
context.addLine(to: pt(r, 0))
context.addArc(center: CGPoint(x: cx, y: cy), radius: r,
               startAngle: -.pi / 2, endAngle: 0, clockwise: false)
context.closePath()
context.fillPath()
line(CGPoint(x: cx, y: cy - r), CGPoint(x: cx, y: cy + r), width: stroke)

// Wind barb: from 225° (SW) at 35 kn -> three full barbs + one half
let dir = 225.0 * .pi / 180
let ux = sin(dir), uy = -cos(dir)                 // outward unit vector
let px = -uy, py = ux                             // perpendicular (barb side)
func at(_ f: Double) -> CGPoint {
    let d = r + barbLen * f
    return CGPoint(x: cx + ux * d, y: cy + uy * d)
}
line(at(0), at(1), width: 7)                      // shaft
let step = 13.0 / barbLen, fb = 24.0, hb = 13.0
var t = 1.0
for _ in 0..<3 {                                  // full barbs
    let b = at(t)
    line(b, CGPoint(x: b.x + px * fb + ux * 6, y: b.y + py * fb + uy * 6), width: 7)
    t -= step
}
let b = at(t)                                     // half barb
line(b, CGPoint(x: b.x + px * hb + ux * 3, y: b.y + py * hb + uy * 3), width: 7)

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outputPath) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("wrote \(outputPath)")

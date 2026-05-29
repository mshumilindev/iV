#!/usr/bin/env swift
// Exports macOS AppIcon PNGs from the bundled brand SVG (geometry only).
// macOS requires raster slots in AppIcon.appiconset; this script does not draw a custom mark.
// Run from repo root: swift Scripts/generate_app_icon.swift

import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
let logoURL = repoRoot.appendingPathComponent("iV/Resources/Brand/iVLeavesLogo.svg")
let outDir = repoRoot.appendingPathComponent("iV/Assets.xcassets/AppIcon.appiconset")

let forestDeep = NSColor(red: 0x0F / 255.0, green: 0x1F / 255.0, blue: 0x18 / 255.0, alpha: 1)
let ivyHex = "#64C080"

struct IconSlot {
  let filename: String
  let pointSize: Int
  let scale: Int
  var pixelSize: Int { pointSize * scale }
}

let slots: [IconSlot] = [
  IconSlot(filename: "icon_16.png", pointSize: 16, scale: 1),
  IconSlot(filename: "icon_16@2x.png", pointSize: 16, scale: 2),
  IconSlot(filename: "icon_32.png", pointSize: 32, scale: 1),
  IconSlot(filename: "icon_32@2x.png", pointSize: 32, scale: 2),
  IconSlot(filename: "icon_128.png", pointSize: 128, scale: 1),
  IconSlot(filename: "icon_128@2x.png", pointSize: 128, scale: 2),
  IconSlot(filename: "icon_256.png", pointSize: 256, scale: 1),
  IconSlot(filename: "icon_256@2x.png", pointSize: 256, scale: 2),
  IconSlot(filename: "icon_512.png", pointSize: 512, scale: 1),
  IconSlot(filename: "icon_512@2x.png", pointSize: 512, scale: 2)
]

/// Same ivy tint as `IVLogoView` / `IVColor.ivySoft` — SVG source uses fill="#000000".
func loadIvyLogo(from url: URL) throws -> NSImage {
  var svg = try String(contentsOf: url, encoding: .utf8)
  for old in ["#000000", "#000", "black"] {
    svg = svg.replacingOccurrences(of: "fill=\"\(old)\"", with: "fill=\"\(ivyHex)\"")
  }
  guard let data = svg.data(using: .utf8), let image = NSImage(data: data) else {
    throw NSError(domain: "AppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not rasterize tinted SVG"])
  }
  return image
}

func renderIcon(pixelSize: Int, logo: NSImage) -> NSImage {
  let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
  image.lockFocus()

  let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
  let corner = CGFloat(pixelSize) * 0.2237
  NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).addClip()

  forestDeep.setFill()
  rect.fill()

  let logoSize = CGFloat(pixelSize) * 0.58
  let logoRect = NSRect(
    x: (CGFloat(pixelSize) - logoSize) / 2,
    y: (CGFloat(pixelSize) - logoSize) / 2,
    width: logoSize,
    height: logoSize
  )
  logo.draw(in: logoRect)

  image.unlockFocus()
  return image
}

func writePNG(_ image: NSImage, pixelSize: Int, to url: URL) throws {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )!
  rep.size = NSSize(width: pixelSize, height: pixelSize)

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
  NSGraphicsContext.restoreGraphicsState()

  guard let png = rep.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
  }
  try png.write(to: url)
}

let logo = try loadIvyLogo(from: logoURL)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for slot in slots {
  let url = outDir.appendingPathComponent(slot.filename)
  let img = renderIcon(pixelSize: slot.pixelSize, logo: logo)
  try writePNG(img, pixelSize: slot.pixelSize, to: url)
  print("Wrote \(slot.filename) (\(slot.pixelSize)×\(slot.pixelSize) px)")
}

let contents: [String: Any] = [
  "images": slots.map { slot in
    [
      "filename": slot.filename,
      "idiom": "mac",
      "scale": "\(slot.scale)x",
      "size": "\(slot.pointSize)x\(slot.pointSize)"
    ] as [String: Any]
  },
  "info": ["author": "iV", "version": 1]
]

let jsonData = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try jsonData.write(to: outDir.appendingPathComponent("Contents.json"))
print("Source: \(logoURL.lastPathComponent) (fill \(ivyHex)) → AppIcon.appiconset")

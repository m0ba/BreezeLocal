#!/usr/bin/env swift
// 生成 AppIcon.icns：圆角渐变底 + 声波柱
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let full = NSRect(x: 0, y: 0, width: size, height: size)
let squircle = NSBezierPath(roundedRect: full.insetBy(dx: 40, dy: 40), xRadius: 210, yRadius: 210)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.16, green: 0.47, blue: 0.93, alpha: 1),
    NSColor(srgbRed: 0.10, green: 0.78, blue: 0.70, alpha: 1)
])!
gradient.draw(in: squircle, angle: -55)

// 声波柱
let heights: [CGFloat] = [0.20, 0.34, 0.52, 0.70, 0.52, 0.34, 0.20]
let barWidth: CGFloat = 62
let gap: CGFloat = 34
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = (size - total) / 2
let centerY = size / 2
NSColor.white.setFill()
for h in heights {
    let barHeight = 520 * h + 60
    let rect = NSRect(x: x, y: centerY - barHeight / 2, width: barWidth, height: barHeight)
    NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    x += barWidth + gap
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("无法渲染图标")
}
let master = root.appendingPathComponent("Resources/AppIcon-1024.png")
try png.write(to: master)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, px) in variants {
    let target = iconset.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", target.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()

print("已生成 Resources/AppIcon.icns")

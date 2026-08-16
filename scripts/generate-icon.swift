#!/usr/bin/swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sources/A-la-Kart/Assets.xcassets/AppIcon.appiconset")
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = repository.appendingPathComponent("Design/AppIconSource.png")

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    throw NSError(domain: "Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to load \(sourceURL.path)"])
}

func cleanedExteriorImage(_ image: CGImage) throws -> CGImage {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](image.dataProvider!.data! as Data)
    var exterior = [Bool](repeating: false, count: width * height)
    var queue: [Int] = []

    func luminance(_ index: Int) -> Int {
        let offset = index * 4
        return (299 * Int(pixels[offset]) + 587 * Int(pixels[offset + 1]) + 114 * Int(pixels[offset + 2])) / 1000
    }
    // The black silhouette is about 13/255; this admits its white and gray
    // antialiasing while remaining safely below any silhouette pixel.
    func isExteriorWhite(_ index: Int) -> Bool { luminance(index) >= 32 }
    func enqueue(_ index: Int) {
        guard !exterior[index], isExteriorWhite(index) else { return }
        exterior[index] = true
        queue.append(index)
    }
    for x in 0..<width {
        enqueue(x)
        enqueue((height - 1) * width + x)
    }
    for y in 0..<height {
        enqueue(y * width)
        enqueue(y * width + width - 1)
    }
    var cursor = 0
    while cursor < queue.count {
        let index = queue[cursor]; cursor += 1
        let x = index % width
        let y = index / width
        if x > 0 { enqueue(index - 1) }
        if x + 1 < width { enqueue(index + 1) }
        if y > 0 { enqueue(index - width) }
        if y + 1 < height { enqueue(index + width) }
    }

    for index in queue {
        let offset = index * 4
        let value = luminance(index)
        // Replace the white matte with black premultiplied by the silhouette
        // coverage. Pure exterior white becomes fully transparent.
        let alpha = value >= 240 ? 0 : min(255, max(0, (255 - value) * 255 / 223))
        pixels[offset] = 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = UInt8(alpha)
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
        throw NSError(domain: "Icon", code: 2)
    }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true,
                   intent: .defaultIntent)!
}

let cleanedSourceImage = try cleanedExteriorImage(sourceImage)

func renderIcon(pixelSize: Int, to destinationURL: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: pixelSize, height: pixelSize,
                                  bitsPerComponent: 8, bytesPerRow: pixelSize * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "Icon", code: 2)
    }

    context.interpolationQuality = .high
    context.draw(cleanedSourceImage, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "Icon", code: 3)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "Icon", code: 4) }
}

for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = scale == 1 ? "icon_\(pointSize)x\(pointSize).png" : "icon_\(pointSize)x\(pointSize)@2x.png"
        try renderIcon(pixelSize: pointSize * scale, to: output.appendingPathComponent(filename))
    }
}

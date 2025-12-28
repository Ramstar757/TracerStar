//
//  ArtEngine.swift
//  TracerStar
//
//  All paint + coloring + fill + mask code lives here.
//  Created by Ramses Suarez
//

import UIKit
import CoreImage

// =====================================================
//  SECTION A: BOUNDARY MASK (Shared Type)
// =====================================================

struct BoundaryMask {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: [UInt8]  // 1 = boundary, 0 = not boundary

    init(size: CGSize, bytesPerRow: Int, data: [UInt8]) {
        self.width = Int(size.width)
        self.height = Int(size.height)
        self.bytesPerRow = bytesPerRow
        self.data = data
    }

    var size: CGSize { CGSize(width: width, height: height) }

    func isBoundary(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return true }
        return data[y * width + x] != 0
    }
}

// =====================================================
//  SECTION B: IMAGE PROCESSING (Coloring Page Generator)
// =====================================================

struct ImageProcessing {

    struct ColoringResult {
        let image: UIImage
        let mask: BoundaryMask
        let size: CGSize
    }

    static func makeColoringPage(from image: UIImage, maxDimension: CGFloat) -> ColoringResult {

        // 0) Normalize orientation + scale
        let normalized = image.normalizedOrientation()
        let scaled = normalized.scaledToMaxDimension(maxDimension)

        guard let ciIn = CIImage(image: scaled) else {
            let fallbackMask = BoundaryMask(size: scaled.size, bytesPerRow: Int(scaled.size.width), data: [])
            return ColoringResult(image: scaled, mask: fallbackMask, size: scaled.size)
        }

        let context = CIContext(options: [.useSoftwareRenderer: false])

        // 1) Soft base (so the final looks like a “coloring page”)
        let softBase = ciIn.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.15,
            kCIInputContrastKey: 1.05,
            kCIInputBrightnessKey: 0.05
        ])

        // 2) Grayscale
        let gray = ciIn.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.15
        ])

        // 3) Edges (IMPORTANT: this is what we build the boundary mask from)
        // CIEdges typically outputs BRIGHT edges on dark background.
        let edges = gray.applyingFilter("CIEdges", parameters: [
            kCIInputIntensityKey: 2.6
        ])

        // 4) For display: convert edges into “ink lines” and blend over base
        let edgeInkForDisplay = edges
            .applyingFilter("CIColorInvert")
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 2.2,
                kCIInputBrightnessKey: -0.05
            ])

        let blended = edgeInkForDisplay.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: softBase
        ])

        let outCG = context.createCGImage(blended, from: blended.extent)
        let outImage = outCG.map { UIImage(cgImage: $0) } ?? scaled

        // ✅ FIX: build boundary mask from the RAW edges (bright edges)
        let edgesCG = context.createCGImage(edges, from: edges.extent)
        let edgesUIImage = edgesCG.map { UIImage(cgImage: $0) } ?? outImage

        let mask = buildBoundaryMaskFromBrightEdges(edgesUIImage)

        return ColoringResult(
            image: outImage,
            mask: mask,
            size: CGSize(width: mask.width, height: mask.height)
        )
    }

    // MARK: Mask builder for BRIGHT edge maps (edges are high luminance)
    private static func buildBoundaryMaskFromBrightEdges(_ image: UIImage) -> BoundaryMask {
        guard let cg = image.cgImage else {
            return BoundaryMask(size: .zero, bytesPerRow: 0, data: [])
        }

        let w = cg.width
        let h = cg.height
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var raw = [UInt8](repeating: 0, count: h * bytesPerRow)

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &raw,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return BoundaryMask(size: .zero, bytesPerRow: 0, data: [])
        }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // ✅ For CIEdges: edges are typically BRIGHT.
        // Higher threshold = fewer boundaries, lower threshold = more boundaries.
        // Tune this if needed: 45–85 is a good range.
        let threshold: UInt8 = 65

        var maskData = [UInt8](repeating: 0, count: w * h)

        for y in 0..<h {
            for x in 0..<w {
                let i = y * bytesPerRow + x * 4
                let r = raw[i]
                let g = raw[i + 1]
                let b = raw[i + 2]

                // luminance approx
                let lum = UInt8((UInt16(r) * 30 + UInt16(g) * 59 + UInt16(b) * 11) / 100)

                // ✅ boundary if bright edge pixel
                if lum > threshold {
                    maskData[y * w + x] = 1
                }
            }
        }

        // Thicken edges so bucket doesn’t “leak” through 1px gaps
        let thick = thicken(maskData, w: w, h: h, radius: 2)
        return BoundaryMask(size: CGSize(width: w, height: h), bytesPerRow: w, data: thick)
    }

    private static func thicken(_ mask: [UInt8], w: Int, h: Int, radius: Int) -> [UInt8] {
        guard radius > 0 else { return mask }
        var out = mask

        for y in 0..<h {
            for x in 0..<w {
                if mask[y*w + x] == 0 { continue }
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx
                        let ny = y + dy
                        if nx >= 0, ny >= 0, nx < w, ny < h {
                            out[ny*w + nx] = 1
                        }
                    }
                }
            }
        }
        return out
    }
}

// =====================================================
//  SECTION C: FLOOD FILL (Bucket Tool)
// =====================================================

struct FloodFill {

    static func fill(
        overlay: UIImage?,
        boundaryMask: BoundaryMask,
        start: CGPoint,
        fillColor: UIColor,
        canvasSize: CGSize
    ) -> UIImage? {

        let w = boundaryMask.width
        let h = boundaryMask.height
        guard w > 0, h > 0 else { return overlay }

        let sx = Int(start.x.rounded())
        let sy = Int(start.y.rounded())
        guard sx >= 0, sy >= 0, sx < w, sy < h else { return overlay }

        // If user taps a boundary line, do nothing
        if boundaryMask.isBoundary(x: sx, y: sy) { return overlay }

        // Overlay pixels (RGBA)
        var rgba = overlayRGBA(image: overlay, width: w, height: h)

        let startIndex = (sy * w + sx) * 4
        let target = (r: rgba[startIndex], g: rgba[startIndex+1], b: rgba[startIndex+2], a: rgba[startIndex+3])

        let fill = fillColor.rgbaBytes()

        // If already “same-ish” color, skip
        if closeColor(target, fill) { return overlay }

        // Use an explicit stack (fast, no recursion)
        var stack: [(Int, Int)] = [(sx, sy)]
        stack.reserveCapacity(60_000)

        var visited = [UInt8](repeating: 0, count: w * h)

        func matchesTarget(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            let cur = (r: rgba[i], g: rgba[i+1], b: rgba[i+2], a: rgba[i+3])
            return closeColor(cur, target)
        }

        while let (x, y) = stack.popLast() {
            let vIndex = y * w + x
            if visited[vIndex] != 0 { continue }
            visited[vIndex] = 1

            if boundaryMask.isBoundary(x: x, y: y) { continue }
            if !matchesTarget(x, y) { continue }

            let i = vIndex * 4
            rgba[i]   = fill.r
            rgba[i+1] = fill.g
            rgba[i+2] = fill.b
            rgba[i+3] = fill.a

            if x > 0   { stack.append((x-1, y)) }
            if x < w-1 { stack.append((x+1, y)) }
            if y > 0   { stack.append((x, y-1)) }
            if y < h-1 { stack.append((x, y+1)) }

            // safety cap for worst-case taps
            if stack.count > 300_000 { break }
        }

        return imageFromRGBA(rgba: rgba, width: w, height: h)
    }

    private static func overlayRGBA(image: UIImage?, width: Int, height: Int) -> [UInt8] {
        let bytesPerRow = width * 4
        var raw = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let img = image?.cgImage else { return raw }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return raw }

        // Draw scaled into our pixel buffer
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        return raw
    }

    private static func imageFromRGBA(rgba: [UInt8], width: Int, height: Int) -> UIImage? {
        let bytesPerRow = width * 4
        let cs = CGColorSpaceCreateDeviceRGB()

        var copy = rgba
        guard let ctx = CGContext(
            data: &copy,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func closeColor(
        _ a: (r: UInt8,g: UInt8,b: UInt8,a: UInt8),
        _ b: (r: UInt8,g: UInt8,b: UInt8,a: UInt8)
    ) -> Bool {
        // Bucket needs a tighter tolerance or it “bleeds” through partially colored regions.
        let t: Int = 14
        return abs(Int(a.r) - Int(b.r)) <= t &&
               abs(Int(a.g) - Int(b.g)) <= t &&
               abs(Int(a.b) - Int(b.b)) <= t &&
               abs(Int(a.a) - Int(b.a)) <= t
    }
}

// =====================================================
//  SECTION D: BRUSH (Line Painter)
//  NOTE: You said remove color removal → we are NOT doing erase/clear here.
// =====================================================

struct ImagePainter {

    static func drawLine(
        on overlay: UIImage?,
        from: CGPoint,
        to: CGPoint,
        color: UIColor,
        width: CGFloat,
        canvasSize: CGSize
    ) -> UIImage? {

        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        overlay?.draw(in: CGRect(origin: .zero, size: canvasSize))

        guard let ctx = UIGraphicsGetCurrentContext() else { return overlay }

        ctx.setBlendMode(.normal)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(width)
        ctx.setStrokeColor(color.cgColor)

        ctx.beginPath()
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()

        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// =====================================================
//  SECTION E: TEXT TOOL (Add Text to Overlay)
// =====================================================

struct TextPainter {

    static func drawText(
        on overlay: UIImage?,
        text: String,
        at point: CGPoint,              // in canvas pixel space
        font: UIFont,
        color: UIColor,
        canvasSize: CGSize
    ) -> UIImage? {

        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        overlay?.draw(in: CGRect(origin: .zero, size: canvasSize))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        // Draw with baseline starting at point
        (text as NSString).draw(at: point, withAttributes: attrs)

        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// =====================================================
//  SECTION F: EXTENSIONS
// =====================================================

extension UIImage {

    // Fixes rotated camera images, etc.
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func scaledToMaxDimension(_ maxDimension: CGFloat) -> UIImage {
        guard maxDimension > 0 else { return self }

        let w = size.width
        let h = size.height
        let maxSide = max(w, h)

        if maxSide <= maxDimension { return self }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: w * scale, height: h * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// ✅ NOT private anymore so you can reuse it across files without duplication.
extension UIColor {
    func adultRGBABytes() -> (r: UInt8,g: UInt8,b: UInt8,a: UInt8) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255), UInt8(a * 255))
    }
}

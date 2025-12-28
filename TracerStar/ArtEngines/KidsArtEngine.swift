//
//  KidsArtEngine.swift
//  TracerStar
//
//  All kid paint tools live here (NO extra Swift files for kid tools).
//  Created by Ramses Suarez on 12/23/25.
//

import SwiftUI
import UIKit
import CoreGraphics

// =====================================================
//  SECTION A: ENUMS + MODELS
// =====================================================
//  A1) Tools the kid can pick
//  A2) Config structs for fill safety + boundary behavior
// =====================================================

enum KidsTool {
    case bucket
    case brush
    case watercolor
    case rainbow
    case eraser
    // later: case sticker
}

// =====================================================
//  SECTION B: CORE ENGINE (UIKit drawing + pixel ops)
// =====================================================
//  B1) Color helpers (rainbow)
//  B2) Stroke tools (brush / eraser / watercolor / rainbow)
//  B3) Bucket fill tool (flood fill with boundary stop)
//  B4) Internal pixel utilities (RGBA buffers)
// =====================================================

struct KidsPaintEngine {

    // =====================================================
    //  SECTION B0: CONFIG
    // =====================================================

    struct BucketConfig {
        var boundaryTolerance: Int = 40   // how close a pixel must be to boundaryColor to be treated as boundary
        var maxPixels: Int = 450_000      // safety cap
        var edgeShrinkRadius: Int = 1     // avoids painting right next to boundary -> reduces halos
    }

    // =====================================================
    //  SECTION B1: COLOR HELPERS
    // =====================================================

    /// Rainbow color (hue wheel)
    static func rainbowColor(at t: CGFloat, alpha: CGFloat = 1) -> UIColor {
        let hue = t.truncatingRemainder(dividingBy: 1)
        return UIColor(hue: hue, saturation: 1, brightness: 1, alpha: alpha)
    }

    /// Advance rainbow based on stroke distance (stable across FPS)
    static func advanceRainbowPhase(_ phase: CGFloat, from: CGPoint, to: CGPoint) -> CGFloat {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let dist = sqrt(dx*dx + dy*dy)
        let delta = dist / 260.0
        return (phase + delta).truncatingRemainder(dividingBy: 1)
    }

    // =====================================================
    //  SECTION B2: STROKE TOOLS (DRAW INTO OVERLAY)
    // =====================================================

    // B2.1) Solid brush
    static func brushLine(
        on overlay: UIImage?,
        from: CGPoint,
        to: CGPoint,
        color: UIColor,
        width: CGFloat,
        opacity: CGFloat,
        canvasSize: CGSize
    ) -> UIImage? {
        let a = max(0.05, min(opacity, 1.0))

        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        overlay?.draw(in: CGRect(origin: .zero, size: canvasSize))
        guard let ctx = UIGraphicsGetCurrentContext() else { return overlay }

        ctx.setBlendMode(.normal)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(width)
        ctx.setStrokeColor(color.withAlphaComponent(a).cgColor)

        ctx.beginPath()
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // B2.2) Eraser (true transparent)
    static func eraseLine(
        on overlay: UIImage?,
        from: CGPoint,
        to: CGPoint,
        width: CGFloat,
        canvasSize: CGSize
    ) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        overlay?.draw(in: CGRect(origin: .zero, size: canvasSize))
        guard let ctx = UIGraphicsGetCurrentContext() else { return overlay }

        ctx.setBlendMode(.clear)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(width)
        ctx.setStrokeColor(UIColor.clear.cgColor)

        ctx.beginPath()
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // B2.3) Watercolor (FLAT, NO-LAYER, NO-OVERLAP BUILDUP)
    static func watercolorLine(
        on overlay: UIImage?,
        from: CGPoint,
        to: CGPoint,
        color: UIColor,
        width: CGFloat,
        opacity: CGFloat,
        canvasSize: CGSize
    ) -> UIImage? {

        let a = max(0.05, min(opacity, 1.0))

        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        // Draw existing overlay first (so we keep everything already painted)
        overlay?.draw(in: CGRect(origin: .zero, size: canvasSize))
        guard let ctx = UIGraphicsGetCurrentContext() else { return overlay }

        // ✅ KEY: .copy prevents "darkening" when the stroke overlaps itself.
        // It overwrites stroke pixels with the same RGBA every time.
        ctx.setBlendMode(.copy)

        // No shadow = no halo blobs/circles
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        ctx.setShouldAntialias(true)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(width)

        ctx.setStrokeColor(color.withAlphaComponent(a).cgColor)

        ctx.beginPath()
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // B2.4) Rainbow brush
    static func rainbowLine(
        on overlay: UIImage?,
        from: CGPoint,
        to: CGPoint,
        width: CGFloat,
        canvasSize: CGSize,
        rainbowPhase: CGFloat
    ) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        overlay?.draw(in: CGRect(origin: .zero, size: canvasSize))
        guard let ctx = UIGraphicsGetCurrentContext() else { return overlay }

        ctx.setBlendMode(.normal)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(width)

        let c = rainbowColor(at: rainbowPhase, alpha: 0.88)
        ctx.setStrokeColor(c.cgColor)

        ctx.beginPath()
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()

        // Tiny glow
        ctx.setShadow(offset: .zero, blur: max(2, width * 0.25), color: c.withAlphaComponent(0.30).cgColor)
        ctx.setStrokeColor(c.withAlphaComponent(0.22).cgColor)
        ctx.beginPath()
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // =====================================================
    //  SECTION B3: BUCKET FILL (KID-FRIENDLY)
    // =====================================================

    /// Flood fill that stops at pixels close to `boundaryColor` (usually the black outline).
    /// Uses baseImage only for boundary detection. Paints into overlay buffer.
    static func bucketFill(
        baseImage: UIImage,
        overlay: UIImage?,
        start: CGPoint,
        fillColor: UIColor,
        opacity: CGFloat,
        canvasSize: CGSize,
        boundaryColor: UIColor = .black,
        config: BucketConfig = .init()
    ) -> UIImage? {

        // NOTE: we must have baseCG for boundary reads
        guard let baseCG = baseImage.cgImage else { return overlay }

        let w = Int(canvasSize.width.rounded())
        let h = Int(canvasSize.height.rounded())
        guard w > 2, h > 2 else { return overlay }

        let sx = Int(start.x.rounded())
        let sy = Int(start.y.rounded())
        guard sx >= 0, sy >= 0, sx < w, sy < h else { return overlay }

        guard let baseRGBA = rgbaBytes(from: baseCG, width: w, height: h) else { return overlay }
        var paintRGBA = overlayRGBA(image: overlay, width: w, height: h)

        let boundary = boundaryColor.rgbaBytes()

        // Apply user opacity to alpha
        let a = max(0.05, min(opacity, 1.0))
        var fill = fillColor.rgbaBytes()
        fill.a = UInt8(CGFloat(fill.a) * a)

        // If starting on boundary: do nothing
        if isCloseToBoundary(pixelAtX: sx, y: sy, rgba: baseRGBA, width: w, boundary: boundary, tol: config.boundaryTolerance) {
            return overlay
        }

        // If starting already close to fill: do nothing
        let startI = (sy * w + sx) * 4
        let startPix = (r: paintRGBA[startI], g: paintRGBA[startI+1], b: paintRGBA[startI+2], a: paintRGBA[startI+3])
        if closeColor(startPix, fill, tol: 10) { return overlay }

        // Flood fill stack (DFS)
        var qx: [Int] = [sx]
        var qy: [Int] = [sy]
        qx.reserveCapacity(50_000)
        qy.reserveCapacity(50_000)

        var visited = [UInt8](repeating: 0, count: w * h)
        var paintedCount = 0

        while !qx.isEmpty {
            let x = qx.removeLast()
            let y = qy.removeLast()

            let idx = y * w + x
            if visited[idx] != 0 { continue }
            visited[idx] = 1

            // Boundary stop (base)
            if isCloseToBoundary(pixelAtX: x, y: y, rgba: baseRGBA, width: w, boundary: boundary, tol: config.boundaryTolerance) {
                continue
            }

            // Optional: shrink away from outline to avoid halos
            if config.edgeShrinkRadius > 0 && isNearBoundary(
                x: x, y: y,
                baseRGBA: baseRGBA,
                w: w, h: h,
                boundary: boundary,
                tol: config.boundaryTolerance,
                radius: config.edgeShrinkRadius
            ) {
                continue
            }

            // Paint pixel in overlay
            let i = idx * 4
            paintRGBA[i]   = fill.r
            paintRGBA[i+1] = fill.g
            paintRGBA[i+2] = fill.b
            paintRGBA[i+3] = fill.a

            paintedCount += 1
            if paintedCount > config.maxPixels { break }

            if x > 0   { qx.append(x-1); qy.append(y) }
            if x < w-1 { qx.append(x+1); qy.append(y) }
            if y > 0   { qx.append(x); qy.append(y-1) }
            if y < h-1 { qx.append(x); qy.append(y+1) }
        }

        return imageFromRGBA(rgba: paintRGBA, width: w, height: h)
    }

    private static func isNearBoundary(
        x: Int,
        y: Int,
        baseRGBA: [UInt8],
        w: Int,
        h: Int,
        boundary: (r: UInt8,g: UInt8,b: UInt8,a: UInt8),
        tol: Int,
        radius: Int
    ) -> Bool {
        for dy in -radius...radius {
            for dx in -radius...radius {
                let nx = x + dx
                let ny = y + dy
                if nx < 0 || ny < 0 || nx >= w || ny >= h { continue }
                if isCloseToBoundary(pixelAtX: nx, y: ny, rgba: baseRGBA, width: w, boundary: boundary, tol: tol) {
                    return true
                }
            }
        }
        return false
    }

    // =====================================================
    //  SECTION B4: INTERNAL PIXEL UTILITIES
    // =====================================================

    private static func rgbaBytes(from cg: CGImage, width: Int, height: Int) -> [UInt8]? {
        let bytesPerRow = width * 4
        var raw = [UInt8](repeating: 0, count: height * bytesPerRow)

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return raw
    }

    private static func overlayRGBA(image: UIImage?, width: Int, height: Int) -> [UInt8] {
        let bytesPerRow = width * 4
        var raw = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let img = image?.cgImage else { return raw }

        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

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

    private static func isCloseToBoundary(
        pixelAtX x: Int,
        y: Int,
        rgba: [UInt8],
        width: Int,
        boundary: (r: UInt8,g: UInt8,b: UInt8,a: UInt8),
        tol: Int
    ) -> Bool {
        let i = (y * width + x) * 4
        let p = (r: rgba[i], g: rgba[i+1], b: rgba[i+2], a: rgba[i+3])
        return closeColor(p, boundary, tol: tol)
    }

    private static func closeColor(
        _ a: (r: UInt8,g: UInt8,b: UInt8,a: UInt8),
        _ b: (r: UInt8,g: UInt8,b: UInt8,a: UInt8),
        tol: Int
    ) -> Bool {
        abs(Int(a.r) - Int(b.r)) <= tol &&
        abs(Int(a.g) - Int(b.g)) <= tol &&
        abs(Int(a.b) - Int(b.b)) <= tol &&
        abs(Int(a.a) - Int(b.a)) <= tol
    }
}

// =====================================================
//  SECTION C: UIColor Helpers
// =====================================================

extension UIColor {
    func rgbaBytes() -> (r: UInt8,g: UInt8,b: UInt8,a: UInt8) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255), UInt8(a * 255))
    }
}

// =====================================================
//  SECTION D: UIImage Helpers (Kids-only)
// =====================================================
//  D1) Transparent overlay init
//  D2) Canvas-size source of truth (CGImage pixels)
// =====================================================

private extension UIImage {

    /// Creates an empty transparent RGBA canvas at 1x scale (pixel-perfect).
    static func transparentCanvas(width: Int, height: Int) -> UIImage? {
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Pixel-perfect dimensions for drawing buffers.
    /// IMPORTANT: use CGImage size (pixels), not UIImage.size (points).
    var cgPixelSize: CGSize {
        if let cg = self.cgImage { return CGSize(width: cg.width, height: cg.height) }
        // Fallback: best effort (rare)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

// =====================================================
//  SECTION E: KIDS PAINT UI (SwiftUI)
// =====================================================
//  E1) Screen wrapper (toolbar + controls + canvas)
//  E2) Canvas rendering + gesture -> calls KidsPaintEngine
//  E3) Layout helpers (aspect fit math)
// =====================================================

struct KidsPaintScreen: View {
    
    // E1.1 Inputs
    let baseKey: String                 // template id or "blank"
    let originalImage: UIImage
    let resumeSessionId: String?        // nil for new, id for Resume
    let onBack: () -> Void
    let onExitToPicker: () -> Void
    
    // E1.2 State
    @State private var overlay: UIImage? = nil
    @State private var tool: KidsTool = .brush
    
    @State private var brushColor: Color = .blue
    @State private var brushWidth: CGFloat = 18
    
    // Shared opacity for Brush + Water + Bucket
    @State private var materialOpacity: CGFloat = 1.0   // 0.05 ... 1.0
    
    // Rainbow phase
    @State private var rainbowPhase: CGFloat = 0
    
    // Continuous strokes
    @State private var lastPoint: CGPoint? = nil
    
    // NEW: session + autosave debounce
    @State private var session: KidsPaintSession
    @State private var autosaveWork: DispatchWorkItem? = nil
    
    // =====================================================
    //  E0: UNDO / REDO (Overlay History)
    // =====================================================
    @State private var history: [UIImage?] = [nil]   // snapshot 0 = empty
    @State private var historyIndex: Int = 0
    private let historyLimit: Int = 30
    
    private var canUndo: Bool { historyIndex > 0 }
    private var canRedo: Bool { historyIndex < history.count - 1 }
    
    // =====================================================
    //  E1.0 INIT (required because session is @State)
    // =====================================================
    init(
        baseKey: String,
        originalImage: UIImage,
        resumeSessionId: String? = nil,
        onBack: @escaping () -> Void,
        onExitToPicker: @escaping () -> Void
    ) {
        self.baseKey = baseKey
        self.originalImage = originalImage
        self.resumeSessionId = resumeSessionId
        self.onBack = onBack
        self.onExitToPicker = onExitToPicker
        
        if let id = resumeSessionId,
           let loaded = KidsPaintStore.loadSession(id: id) {
            _session = State(initialValue: loaded)
        } else {
            _session = State(initialValue: KidsPaintStore.makeNewSession(baseKey: baseKey))
        }
    }
    
    // =====================================================
    //  E0.1 HISTORY HELPERS
    // =====================================================
    private func commitHistory(_ snap: UIImage?) {
        // If we undid and then draw again, clear the "future"
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)..<history.count)
        }
        
        // Avoid duplicate commits (common when nothing changed)
        if history.last ?? nil === snap { return }
        
        history.append(snap)
        historyIndex = history.count - 1
        
        // Cap memory
        if history.count > historyLimit {
            let overflow = history.count - historyLimit
            history.removeFirst(overflow)
            historyIndex = max(0, historyIndex - overflow)
        }
    }
    
    private func undo() {
        guard canUndo else { return }
        historyIndex -= 1
        overlay = history[historyIndex]
        scheduleAutoSave() // optional but nice: undo/redo also persists
    }
    
    private func redo() {
        guard canRedo else { return }
        historyIndex += 1
        overlay = history[historyIndex]
        scheduleAutoSave()
    }
    
    // =====================================================
    //  E1.7 SAVE / AUTOSAVE
    // =====================================================
    private func manualSave() {
        session = KidsPaintStore.saveFinal(session: session, overlay: overlay, baseImage: originalImage)
    }
    
    private func scheduleAutoSave() {
        autosaveWork?.cancel()
        let work = DispatchWorkItem {
            session = KidsPaintStore.saveDraft(session: session, overlay: overlay, baseImage: originalImage)
        }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // E1.3 Top bar
                HStack(spacing: 12) {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: undo) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .bold))
                            .opacity(canUndo ? 1.0 : 0.35)
                    }
                    .disabled(!canUndo)
                    .foregroundColor(.white)
                    
                    Text("Kids Paint")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    
                    Button(action: redo) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 16, weight: .bold))
                            .opacity(canRedo ? 1.0 : 0.35)
                    }
                    .disabled(!canRedo)
                    .foregroundColor(.white)
                    
                    Spacer()
                    
                    // NEW: Save button
                    Button(action: manualSave) {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    
                    Button(action: onExitToPicker) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)
                
                // E1.4 Tool row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        toolButton("Brush", .brush, "paintbrush.fill")
                        toolButton("Water", .watercolor, "drop.fill")
                        toolButton("Rainbow", .rainbow, "rainbow")
                        toolButton("Eraser", .eraser, "eraser.fill")
                        toolButton("Bucket", .bucket, "paintbucket.fill")
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                
                // E1.5 Controls
                VStack(spacing: 10) {
                    
                    // Color + Size
                    HStack(spacing: 12) {
                        ColorPicker("", selection: $brushColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 44, height: 30)
                        
                        Slider(value: $brushWidth, in: 6...48, step: 1)
                            .frame(maxWidth: 240)
                        
                        Text("\(Int(brushWidth))")
                            .foregroundColor(.white.opacity(0.85))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, alignment: .trailing)
                        
                        Spacer()
                        
                        Button {
                            overlay = nil
                            commitHistory(overlay)
                            scheduleAutoSave()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                    }
                    
                    // Opacity
                    HStack(spacing: 12) {
                        Text("Opacity")
                            .foregroundColor(.white.opacity(0.85))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 60, alignment: .leading)
                        
                        Slider(value: $materialOpacity, in: 0.05...1.0, step: 0.05)
                            .frame(maxWidth: 240)
                        
                        Text("\(Int(materialOpacity * 100))%")
                            .foregroundColor(.white.opacity(0.85))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 48, alignment: .trailing)
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                
                // E2 Canvas (keep E2 implementation unchanged)
                KidsCanvas(
                    baseImage: originalImage,
                    overlay: $overlay,
                    tool: tool,
                    uiColor: UIColor(brushColor),
                    brushWidth: brushWidth,
                    materialOpacity: materialOpacity,
                    rainbowPhase: $rainbowPhase,
                    lastPoint: $lastPoint,
                    onCommit: { snap in
                        commitHistory(snap)
                        scheduleAutoSave()
                    }
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            // Load overlay if resuming
            if resumeSessionId != nil {
                overlay = KidsPaintStore.loadOverlay(session: session)
                history = [overlay]
                historyIndex = 0
            } else {
                overlay = nil
                history = [nil]
                historyIndex = 0
            }
            
            // Mark last session immediately so Resume can find it
            KidsPaintStore.setLastSessionId(session.id)
        }
    }
    
    // E1.6 Tool button UI
    private func toolButton(_ title: String, _ t: KidsTool, _ sf: String) -> some View {
        Button {
            tool = t
        } label: {
            HStack(spacing: 8) {
                Image(systemName: sf)
                Text(title)
            }
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundColor(.white.opacity(tool == t ? 1.0 : 0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(tool == t ? 0.16 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // =====================================================
    //  SECTION E2: KIDS CANVAS (Zoom + Pan + Draw)
    // =====================================================
    
    private struct KidsCanvas: View {
        
        // Inputs
        let baseImage: UIImage
        
        @Binding var overlay: UIImage?
        let tool: KidsTool
        let uiColor: UIColor
        let brushWidth: CGFloat
        let materialOpacity: CGFloat
        
        @Binding var rainbowPhase: CGFloat
        @Binding var lastPoint: CGPoint?
        
        // commit callback (pushes snapshots into history)
        let onCommit: (UIImage?) -> Void
        
        // -----------------------------------------------------
        // E4 state: zoom + pan
        // -----------------------------------------------------
        @State private var zoomScale: CGFloat = 1.0
        @State private var zoomScaleStart: CGFloat = 1.0
        
        @State private var panOffset: CGSize = .zero
        @State private var panOffsetStart: CGSize = .zero
        
        // Gesture flags to prevent draw while zooming/panning
        @GestureState private var isPinching: Bool = false
        @State private var isTwoFingerPanning: Bool = false
        
        // NEW: bucket should not commit twice (onChanged + onEnded)
        @State private var didCommitBucketThisGesture: Bool = false
        
        var body: some View {
            GeometryReader { geo in
                
                // Fit image inside canvas area (in points)
                let displaySize = aspectFitSize(imageSize: baseImage.size, in: geo.size)
                let origin = CGPoint(
                    x: (geo.size.width - displaySize.width) * 0.5,
                    y: (geo.size.height - displaySize.height) * 0.5
                )
                
                // Clamp pan based on current scale
                let clampedPan = KidsZoom.clampOffset(panOffset, scale: zoomScale, displaySize: displaySize)
                
                ZStack {
                    Color.black.opacity(0.25)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    
                    // ---- Render stack (scaled + panned) inside the display frame ----
                    ZStack {
                        Image(uiImage: baseImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                        
                        if let o = overlay {
                            Image(uiImage: o)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                        }
                    }
                    .frame(width: displaySize.width, height: displaySize.height)
                    .scaleEffect(zoomScale, anchor: .center)
                    .offset(clampedPan)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                
                // ---- Two-finger pan capture overlay (UIKit) ----
                .overlay(
                    TwoFingerPanCapture(
                        onPanChanged: { translation in
                            isTwoFingerPanning = true
                            // Apply translation relative to start snapshot
                            let next = CGSize(
                                width: panOffsetStart.width + translation.x,
                                height: panOffsetStart.height + translation.y
                            )
                            panOffset = KidsZoom.clampOffset(next, scale: zoomScale, displaySize: displaySize)
                        },
                        onPanEnded: {
                            isTwoFingerPanning = false
                            panOffset = KidsZoom.clampOffset(panOffset, scale: zoomScale, displaySize: displaySize)
                            panOffsetStart = panOffset
                        }
                    )
                )
                
                // ---- Pinch zoom (SwiftUI) ----
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($isPinching) { _, s, _ in s = true }
                        .onChanged { value in
                            let next = KidsZoom.clampScale(zoomScaleStart * value)
                            zoomScale = next
                            panOffset = KidsZoom.clampOffset(panOffset, scale: zoomScale, displaySize: displaySize)
                        }
                        .onEnded { _ in
                            zoomScale = KidsZoom.clampScale(zoomScale)
                            zoomScaleStart = zoomScale
                            panOffset = KidsZoom.clampOffset(panOffset, scale: zoomScale, displaySize: displaySize)
                            panOffsetStart = panOffset
                        }
                )
                
                // ---- Double-tap reset ----
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        zoomScale = 1.0
                        zoomScaleStart = 1.0
                        panOffset = .zero
                        panOffsetStart = .zero
                        lastPoint = nil
                    }
                )
                
                // ---- Drawing gesture (1-finger) ----
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            
                            // If user is pinching or 2-finger panning: do NOT draw
                            guard !isPinching && !isTwoFingerPanning else {
                                lastPoint = nil
                                return
                            }
                            
                            let p = value.location
                            
                            // Convert touch to "local inside display frame" BEFORE zoom/pan:
                            // 1) shift to display frame origin
                            // 2) undo pan
                            // 3) undo scale around center
                            let center = CGPoint(
                                x: origin.x + displaySize.width * 0.5,
                                y: origin.y + displaySize.height * 0.5
                            )
                            
                            // Undo pan
                            let unpanned = CGPoint(x: p.x - clampedPan.width, y: p.y - clampedPan.height)
                            
                            // Undo scale around center
                            let lx = (unpanned.x - center.x) / zoomScale + center.x
                            let ly = (unpanned.y - center.y) / zoomScale + center.y
                            
                            // Now check if inside the untransformed display rect
                            let inside =
                            lx >= origin.x && lx <= origin.x + displaySize.width &&
                            ly >= origin.y && ly <= origin.y + displaySize.height
                            guard inside else { return }
                            
                            // Pixel dimensions
                            let px = baseImage.cgPixelSize
                            let canvasW = Int(px.width)
                            let canvasH = Int(px.height)
                            guard canvasW > 0, canvasH > 0 else { return }
                            
                            // Map local point (lx,ly) -> pixel space
                            let ix = (lx - origin.x) / displaySize.width * CGFloat(canvasW)
                            let iy = (ly - origin.y) / displaySize.height * CGFloat(canvasH)
                            let cur = CGPoint(x: ix, y: iy)
                            
                            if overlay == nil {
                                overlay = UIImage.transparentCanvas(width: canvasW, height: canvasH)
                            }
                            
                            let canvasSize = CGSize(width: canvasW, height: canvasH)
                            
                            switch tool {
                                
                            case .bucket:
                                // Bucket should be tap-ish: ignore if the finger is actually dragging
                                // (SwiftUI can report tiny translations, so use a small threshold)
                                let dx = value.translation.width
                                let dy = value.translation.height
                                let moved = sqrt(dx*dx + dy*dy)
                                guard moved < 2.0 else { return }
                                
                                // Only do the fill once per gesture
                                guard didCommitBucketThisGesture == false else { return }
                                didCommitBucketThisGesture = true
                                
                                lastPoint = nil
                                overlay = KidsPaintEngine.bucketFill(
                                    baseImage: baseImage,
                                    overlay: overlay,
                                    start: cur,
                                    fillColor: uiColor,
                                    opacity: materialOpacity,
                                    canvasSize: canvasSize
                                )
                                onCommit(overlay)   // ✅ commit immediately for bucket (one-tap action)
                                
                            case .brush:
                                overlay = KidsPaintEngine.brushLine(
                                    on: overlay,
                                    from: lastPoint ?? cur,
                                    to: cur,
                                    color: uiColor,
                                    width: brushWidth,
                                    opacity: materialOpacity,
                                    canvasSize: canvasSize
                                )
                                lastPoint = cur
                                
                            case .watercolor:
                                overlay = KidsPaintEngine.watercolorLine(
                                    on: overlay,
                                    from: lastPoint ?? cur,
                                    to: cur,
                                    color: uiColor,
                                    width: brushWidth,
                                    opacity: materialOpacity,
                                    canvasSize: canvasSize
                                )
                                lastPoint = cur
                                
                            case .rainbow:
                                if let lp = lastPoint {
                                    rainbowPhase = KidsPaintEngine.advanceRainbowPhase(rainbowPhase, from: lp, to: cur)
                                } else {
                                    rainbowPhase = (rainbowPhase + 0.01).truncatingRemainder(dividingBy: 1)
                                }
                                
                                overlay = KidsPaintEngine.rainbowLine(
                                    on: overlay,
                                    from: lastPoint ?? cur,
                                    to: cur,
                                    width: brushWidth,
                                    canvasSize: canvasSize,
                                    rainbowPhase: rainbowPhase
                                )
                                lastPoint = cur
                                
                            case .eraser:
                                overlay = KidsPaintEngine.eraseLine(
                                    on: overlay,
                                    from: lastPoint ?? cur,
                                    to: cur,
                                    width: brushWidth,
                                    canvasSize: canvasSize
                                )
                                lastPoint = cur
                            }
                        }
                        .onEnded { _ in
                            lastPoint = nil
                            
                            // If bucket already committed during onChanged, do NOT commit again here.
                            if tool == .bucket {
                                didCommitBucketThisGesture = false
                                return
                            }
                            
                            onCommit(overlay) // commit once per stroke
                        }
                )
                
                // Snapshot pan start anytime a new two-finger pan begins
                .onChange(of: isTwoFingerPanning) { v in
                    if v { panOffsetStart = panOffset }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        
        // =====================================================
        //  SECTION E3: LAYOUT HELPER
        // =====================================================
        
        private func aspectFitSize(imageSize: CGSize, in container: CGSize) -> CGSize {
            guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
            let scale = min(container.width / imageSize.width, container.height / imageSize.height)
            return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        }
        
        // =====================================================
        //  SECTION E4: ZOOM + PAN STATE + HELPERS
        // =====================================================
        
        private enum KidsZoom {
            static let minScale: CGFloat = 1.0
            static let maxScale: CGFloat = 5.0
            
            static func clampScale(_ s: CGFloat) -> CGFloat {
                min(max(s, minScale), maxScale)
            }
            
            static func clampOffset(_ offset: CGSize, scale: CGFloat, displaySize: CGSize) -> CGSize {
                let extraW = max(0, (displaySize.width * scale) - displaySize.width)
                let extraH = max(0, (displaySize.height * scale) - displaySize.height)
                
                let maxX = extraW * 0.5
                let maxY = extraH * 0.5
                
                let cx = min(max(offset.width,  -maxX), maxX)
                let cy = min(max(offset.height, -maxY), maxY)
                return CGSize(width: cx, height: cy)
            }
        }
        
        // =====================================================
        //  SECTION E5: TWO-FINGER PAN (UIKit bridge)
        // =====================================================
        
        private struct TwoFingerPanCapture: UIViewRepresentable {
            
            var onPanChanged: (CGPoint) -> Void
            var onPanEnded: () -> Void
            
            func makeUIView(context: Context) -> UIView {
                let v = UIView(frame: .zero)
                v.backgroundColor = .clear
                
                let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
                pan.minimumNumberOfTouches = 2
                pan.maximumNumberOfTouches = 2
                pan.cancelsTouchesInView = true
                v.addGestureRecognizer(pan)
                
                return v
            }
            
            func updateUIView(_ uiView: UIView, context: Context) {}
            
            func makeCoordinator() -> Coordinator {
                Coordinator(onPanChanged: onPanChanged, onPanEnded: onPanEnded)
            }
            
            final class Coordinator: NSObject {
                let onPanChanged: (CGPoint) -> Void
                let onPanEnded: () -> Void
                
                init(onPanChanged: @escaping (CGPoint) -> Void, onPanEnded: @escaping () -> Void) {
                    self.onPanChanged = onPanChanged
                    self.onPanEnded = onPanEnded
                }
                
                @objc func handlePan(_ g: UIPanGestureRecognizer) {
                    let t = g.translation(in: g.view)
                    if g.state == .changed {
                        onPanChanged(t)
                    } else if g.state == .ended || g.state == .cancelled || g.state == .failed {
                        onPanEnded()
                    }
                }
            }
        }
    }
    
    // =====================================================
    //  SECTION E3: LAYOUT HELPER
    // =====================================================
    
    private func aspectFitSize(imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
    
    // =====================================================
    //  SECTION E4: ZOOM + PAN STATE + HELPERS
    // =====================================================
    //  E4.1) Zoom scale + pan offset state
    //  E4.2) Clamp logic so you can’t fling content offscreen
    //  E4.3) Double-tap reset support
    // =====================================================
    
    private enum KidsZoom {
        static let minScale: CGFloat = 1.0
        static let maxScale: CGFloat = 5.0
        
        static func clampScale(_ s: CGFloat) -> CGFloat {
            min(max(s, minScale), maxScale)
        }
        
        /// Clamps offset so scaled content always covers the viewport.
        /// displaySize is the unscaled "fit" size inside the canvas.
        static func clampOffset(_ offset: CGSize, scale: CGFloat, displaySize: CGSize) -> CGSize {
            // When scale == 1, maxOffset == 0 (no panning)
            let extraW = max(0, (displaySize.width * scale) - displaySize.width)
            let extraH = max(0, (displaySize.height * scale) - displaySize.height)
            
            let maxX = extraW * 0.5
            let maxY = extraH * 0.5
            
            let cx = min(max(offset.width,  -maxX), maxX)
            let cy = min(max(offset.height, -maxY), maxY)
            return CGSize(width: cx, height: cy)
        }
    }
    
    // =====================================================
    //  SECTION E5: TWO-FINGER PAN (UIKit bridge)
    // =====================================================
    //  SwiftUI DragGesture doesn’t guarantee 2-finger pan separation on iOS 15.
    //  This view ONLY recognizes 2-finger pan and reports translation.
    // =====================================================
    
    private struct TwoFingerPanCapture: UIViewRepresentable {
        
        var onPanChanged: (CGPoint) -> Void
        var onPanEnded: () -> Void
        
        func makeUIView(context: Context) -> UIView {
            let v = UIView(frame: .zero)
            v.backgroundColor = .clear
            
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.cancelsTouchesInView = true // ensures it doesn't feed touches to drawing
            v.addGestureRecognizer(pan)
            
            return v
        }
        
        func updateUIView(_ uiView: UIView, context: Context) {}
        
        func makeCoordinator() -> Coordinator {
            Coordinator(onPanChanged: onPanChanged, onPanEnded: onPanEnded)
        }
        
        final class Coordinator: NSObject {
            let onPanChanged: (CGPoint) -> Void
            let onPanEnded: () -> Void
            
            init(onPanChanged: @escaping (CGPoint) -> Void, onPanEnded: @escaping () -> Void) {
                self.onPanChanged = onPanChanged
                self.onPanEnded = onPanEnded
            }
            
            @objc func handlePan(_ g: UIPanGestureRecognizer) {
                let t = g.translation(in: g.view)
                if g.state == .changed {
                    onPanChanged(t)
                } else if g.state == .ended || g.state == .cancelled || g.state == .failed {
                    onPanEnded()
                }
            }
        }
    }
}
    // =====================================================
    //  SECTION F: SAVE / AUTOSAVE / RESUME / SAVED ART (Local persistence)
    //  NOTE: MUST BE AT FILE SCOPE (outside KidsPaintScreen)
    // =====================================================
    
    struct KidsPaintSession: Codable, Equatable, Identifiable {
        enum Status: String, Codable { case draft, saved }
        
        var id: String               // UUID string
        var baseKey: String          // template id or "blank" or "gallery:<assetName>"
        var overlayFilename: String? // "<id>-overlay.png"
        var thumbFilename: String?   // "<id>-thumb.jpg"
        var updatedAt: Double
        var createdAt: Double
        
        // Only true after first real edit
        var hasEdits: Bool
        
        // draft = Resume, saved = Saved Art
        var status: Status
    }
    
    enum KidsPaintStore {
        
        private static let lastSessionKey = "kidsPaint.lastSessionId"
        
        private static var docsURL: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        
        private static func sessionJSONURL(_ id: String) -> URL {
            docsURL.appendingPathComponent("\(id)-session.json")
        }
        
        private static func overlayURL(_ filename: String) -> URL {
            docsURL.appendingPathComponent(filename)
        }
        
        private static func thumbURL(_ filename: String) -> URL {
            docsURL.appendingPathComponent(filename)
        }
        
        // ----------------------------
        //  Create
        // ----------------------------
        static func makeNewSession(baseKey: String) -> KidsPaintSession {
            let now = Date().timeIntervalSince1970
            return KidsPaintSession(
                id: UUID().uuidString,
                baseKey: baseKey,
                overlayFilename: nil,
                thumbFilename: nil,
                updatedAt: now,
                createdAt: now,
                hasEdits: false,
                status: .draft
            )
        }
        
        // ----------------------------
        //  Last session
        //  NOTE: Only store "last" if it is meaningful
        // ----------------------------
        static func setLastSessionId(_ id: String?) {
            UserDefaults.standard.setValue(id, forKey: lastSessionKey)
        }
        
        static func getLastSessionId() -> String? {
            UserDefaults.standard.string(forKey: lastSessionKey)
        }
        
        // ----------------------------
        //  Load / Save JSON
        // ----------------------------
        static func loadSession(id: String) -> KidsPaintSession? {
            let url = sessionJSONURL(id)
            guard let data = try? Data(contentsOf: url),
                  let s = try? JSONDecoder().decode(KidsPaintSession.self, from: data) else { return nil }
            return s
        }
        
        private static func writeSessionJSON(_ s: KidsPaintSession) {
            if let json = try? JSONEncoder().encode(s) {
                try? json.write(to: sessionJSONURL(s.id), options: [.atomic])
            }
        }
        
        // ----------------------------
        //  Overlay / Thumb
        // ----------------------------
        static func loadOverlay(session: KidsPaintSession) -> UIImage? {
            guard let name = session.overlayFilename else { return nil }
            let url = overlayURL(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
        
        static func loadThumb(session: KidsPaintSession) -> UIImage? {
            guard let name = session.thumbFilename else { return nil }
            let url = thumbURL(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
        
        // ----------------------------
        //  MAIN: Save as DRAFT (Resume)
        //  - Only persists if hasEdits == true
        // ----------------------------
        static func saveDraft(session: KidsPaintSession, overlay: UIImage?, baseImage: UIImage?) -> KidsPaintSession {
            var s = session
            s.updatedAt = Date().timeIntervalSince1970
            s.status = .draft
            
            // If user hasn't edited: don't create junk sessions.
            // Also don't mark as "last session" because Resume shouldn't reopen empty junk.
            guard s.hasEdits else {
                return s
            }
            
            // Save overlay PNG
            if let overlay, let data = overlay.pngData() {
                let name = "\(s.id)-overlay.png"
                try? data.write(to: overlayURL(name), options: [.atomic])
                s.overlayFilename = name
            }
            
            // Write thumbnail (base+overlay if possible)
            if let preview = makePreview(baseImage: baseImage, overlay: overlay) {
                let thumbName = "\(s.id)-thumb.jpg"
                if let jpg = preview.jpegData(compressionQuality: 0.85) {
                    try? jpg.write(to: thumbURL(thumbName), options: [.atomic])
                    s.thumbFilename = thumbName
                }
            }
            
            writeSessionJSON(s)
            setLastSessionId(s.id)
            return s
        }
        
        // ----------------------------
        //  MAIN: Save as SAVED ART
        // ----------------------------
        static func saveFinal(session: KidsPaintSession, overlay: UIImage?, baseImage: UIImage?) -> KidsPaintSession {
            var s = session
            s.status = .saved
            s.hasEdits = true
            s.updatedAt = Date().timeIntervalSince1970
            
            // Save overlay PNG (can be nil if blank, still allow saved blank)
            if let overlay, let data = overlay.pngData() {
                let name = "\(s.id)-overlay.png"
                try? data.write(to: overlayURL(name), options: [.atomic])
                s.overlayFilename = name
            } else {
                // allow saved blank; remove old overlay if any
                if let old = s.overlayFilename {
                    try? FileManager.default.removeItem(at: overlayURL(old))
                }
                s.overlayFilename = nil
            }
            
            if let preview = makePreview(baseImage: baseImage, overlay: overlay) {
                let thumbName = "\(s.id)-thumb.jpg"
                if let jpg = preview.jpegData(compressionQuality: 0.85) {
                    try? jpg.write(to: thumbURL(thumbName), options: [.atomic])
                    s.thumbFilename = thumbName
                }
            }
            
            writeSessionJSON(s)
            setLastSessionId(s.id)
            return s
        }
        
        // ----------------------------
        //  Lists
        // ----------------------------
        private static func allSessions() -> [KidsPaintSession] {
            let fm = FileManager.default
            let urls = (try? fm.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil)) ?? []
            let sessionFiles = urls.filter { $0.lastPathComponent.hasSuffix("-session.json") }
            
            return sessionFiles.compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let s = try? JSONDecoder().decode(KidsPaintSession.self, from: data) else { return nil }
                return s
            }
        }
        
        static func listDrafts() -> [KidsPaintSession] {
            allSessions()
                .filter { $0.status == .draft && $0.hasEdits }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
        
        static func listSaved() -> [KidsPaintSession] {
            allSessions()
                .filter { $0.status == .saved }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
        
        // ----------------------------
        //  Delete
        // ----------------------------
        static func deleteSession(id: String) {
            if let s = loadSession(id: id) {
                if let o = s.overlayFilename { try? FileManager.default.removeItem(at: overlayURL(o)) }
                if let t = s.thumbFilename { try? FileManager.default.removeItem(at: thumbURL(t)) }
            }
            try? FileManager.default.removeItem(at: sessionJSONURL(id))
            
            if getLastSessionId() == id {
                setLastSessionId(nil)
            }
        }
        
        // ----------------------------
        //  Preview renderer (thumb)
        // ----------------------------
        private static func makePreview(baseImage: UIImage?, overlay: UIImage?) -> UIImage? {
            
            // If we have a base, composite base + overlay. Else use overlay only.
            if let base = baseImage {
                
                // IMPORTANT: use pixel dimensions (cgPixelSize), not points.
                let px = base.cgPixelSize
                let size = CGSize(width: px.width, height: px.height)
                
                UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
                defer { UIGraphicsEndImageContext() }
                
                UIColor.white.setFill()
                UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
                
                base.draw(in: CGRect(origin: .zero, size: size))
                overlay?.draw(in: CGRect(origin: .zero, size: size))
                
                let full = UIGraphicsGetImageFromCurrentImageContext()
                return full?.scaledMaxEdge(420)
            }
            
            if let overlay {
                return overlay.scaledMaxEdge(420)
            }
            
            return nil
        }
    }
    
    // =====================================================
    //  SECTION F1: Thumbnail helper
    //  NOTE: MUST BE FILE SCOPE so KidsPaintStore can see it
    // =====================================================
    
    private extension UIImage {
        func scaledMaxEdge(_ maxEdge: CGFloat) -> UIImage? {
            guard size.width > 0, size.height > 0 else { return nil }
            
            // Scale down only (never upscale)
            let factor = min(1.0, maxEdge / max(size.width, size.height))
            let newSize = CGSize(width: size.width * factor, height: size.height * factor)
            
            UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
            defer { UIGraphicsEndImageContext() }
            
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: newSize)).fill()
            
            draw(in: CGRect(origin: .zero, size: newSize))
            return UIGraphicsGetImageFromCurrentImageContext()
        }
    }
    
    // =====================================================
    //  SECTION G: BLANK CANVAS BASE IMAGE
    //  NOTE: MUST BE AT FILE SCOPE (outside KidsPaintScreen)
    // =====================================================
    
    extension UIImage {
        
        /// Creates a solid-color base image for Kids Paint.
        /// - Uses pixel dimensions directly (NOT points).
        /// - Opaque is fine because this is the "paper" underneath.
        static func kidsBlankBase(
            width: Int = 2048,
            height: Int = 2048,
            background: UIColor = .white
        ) -> UIImage {
            
            let w = max(1, width)
            let h = max(1, height)
            let size = CGSize(width: w, height: h)
            
            UIGraphicsBeginImageContextWithOptions(size, true, 1.0) // opaque base
            defer { UIGraphicsEndImageContext() }
            
            background.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            
            return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        }
    }
    
    // =====================================================
    //  SECTION H: KIDS LIBRARY SCREENS (Resume + Saved Art)
    //  NOTE: MUST BE AT FILE SCOPE (outside KidsPaintScreen)
    //  FIXES:
    //   - Removes dependency on GalacticBackground (was "Cannot find in scope")
    //   - Uses a local background (KidsLibraryBackground) inside this file
    // =====================================================
    
    struct KidsResumeScreen: View {
        let onOpen: (KidsPaintSession) -> Void
        let onBack: () -> Void
        
        @State private var drafts: [KidsPaintSession] = []
        
        var body: some View {
            KidsSessionGridShell(
                title: "Resume",
                subtitle: "Unfinished work (drafts). Tap to continue. Swipe to delete.",
                sessions: drafts,
                onBack: onBack,
                onOpen: onOpen,
                onDelete: { s in
                    KidsPaintStore.deleteSession(id: s.id)
                    refresh()
                }
            )
            .onAppear(perform: refresh)
        }
        
        private func refresh() {
            drafts = KidsPaintStore.listDrafts()
        }
    }
    
    struct KidsSavedArtScreen: View {
        let onOpen: (KidsPaintSession) -> Void
        let onBack: () -> Void
        
        @State private var saved: [KidsPaintSession] = []
        
        var body: some View {
            KidsSessionGridShell(
                title: "Saved Art",
                subtitle: "Your saved masterpieces. Tap to edit anytime. Swipe to delete.",
                sessions: saved,
                onBack: onBack,
                onOpen: onOpen,
                onDelete: { s in
                    KidsPaintStore.deleteSession(id: s.id)
                    refresh()
                }
            )
            .onAppear(perform: refresh)
        }
        
        private func refresh() {
            saved = KidsPaintStore.listSaved()
        }
    }
    
    // =====================================================
    //  H1: SHELL
    // =====================================================
    
    private struct KidsSessionGridShell: View {
        let title: String
        let subtitle: String
        let sessions: [KidsPaintSession]
        let onBack: () -> Void
        let onOpen: (KidsPaintSession) -> Void
        let onDelete: (KidsPaintSession) -> Void
        
        var body: some View {
            ZStack {
                KidsLibraryBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    
                    HStack {
                        Button(action: onBack) {
                            Label("Back", systemImage: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text(title)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Image(systemName: "folder.fill")
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    
                    Text(subtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.80))
                        .padding(.bottom, 6)
                    
                    if sessions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "scribble")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text("Nothing here yet.")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.top, 40)
                        
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(sessions) { s in
                                    KidsSessionCard(session: s)
                                        .onTapGesture { onOpen(s) }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                onDelete(s)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 18)
                        }
                    }
                }
            }
        }
    }
    
    // =====================================================
    //  H2: CARD
    // =====================================================
    
    private struct KidsSessionCard: View {
        let session: KidsPaintSession
        
        var body: some View {
            VStack(spacing: 10) {
                
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    
                    if let img = KidsPaintStore.loadThumb(session: session) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                            Text("No preview")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .frame(height: 140)
                
                Text(session.status == .saved ? "Saved" : "Draft")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
    }
    
    // =====================================================
    //  H3: LOCAL BACKGROUND (replaces GalacticBackground)
    // =====================================================
    
    private struct KidsLibraryBackground: View {
        var body: some View {
            ZStack {
                // Dark base
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.05, green: 0.06, blue: 0.12),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Soft “nebula” blobs (cheap + pretty)
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 520, height: 520)
                    .blur(radius: 40)
                    .offset(x: -180, y: -220)
                
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 460, height: 460)
                    .blur(radius: 44)
                    .offset(x: 200, y: 240)
                
                // A subtle star sprinkle (static)
                KidsStarField(density: 70)
                    .opacity(0.55)
            }
        }
    }
    
    private struct KidsStarField: View {
        let density: Int
        
        var body: some View {
            GeometryReader { geo in
                Canvas { ctx, size in
                    // Deterministic seed so stars don't “jump” each render
                    var rng = SeededRNG(seed: 1337)
                    for _ in 0..<max(0, density) {
                        let x = CGFloat.random(in: 0...size.width, using: &rng)
                        let y = CGFloat.random(in: 0...size.height, using: &rng)
                        let r = CGFloat.random(in: 0.6...1.8, using: &rng)
                        
                        let alpha = Double.random(in: 0.25...0.85, using: &rng)
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                            with: .color(Color.white.opacity(alpha))
                        )
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
    
    // Small deterministic RNG so Canvas background is stable.
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed == 0 ? 0x123456789ABCDEF : seed }
        
        mutating func next() -> UInt64 {
            // xorshift64*
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 2685821657736338717
        }
    }


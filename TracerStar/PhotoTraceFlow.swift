//
//  PhotoTraceFlow.swift
//  TracerStar
//
//  Unified core flow: ContentView + Picker + Onboarding + Volume buttons
//  Created by Ramses Suarez
//

import SwiftUI
import PhotosUI
import AVFoundation
import MediaPlayer
import UIKit

// =====================================================
//  SECTION 0: CONTENT VIEW (MAIN ROUTER)
// =====================================================

struct ContentView: View {

    // =====================================================
    //  SECTION 0A: APP MODES (STATE MACHINE)
//  MENU first. Picker happens only after choosing a mode.
// =====================================================
    enum Mode {
        case menu

        case pickingTrace
        case pickingPaint
        case kidsSavedArt

        case tracing
        case painting

        case kidsGallery
        case kidsPainting
    }

    @State private var kidsBaseKey: String = "blank"
    @State private var kidsResumeSessionId: String? = nil
    
    @State private var mode: Mode = .menu
    @State private var selectedImage: UIImage? = nil

    // Onboarding
    @AppStorage("TracerStar.didFinishOnboarding") private var didFinishOnboarding: Bool = false
    @State private var showOnboarding: Bool = true

    // Volume buttons = universal “exit to menu” (or picker for trace, but you want menu-first UX)
    @StateObject private var volumeHandler = VolumeButtonHandler()

    var body: some View {
        ZStack {

            // =====================================================
            //  SECTION 1: BACKGROUND (GALACTIC THEME)
            // =====================================================
            GalacticBackground().ignoresSafeArea()

            // =====================================================
            //  SECTION 2: SCREEN ROUTER
            // =====================================================
            switch mode {

            case .menu:
                mainMenuScreen

            case .pickingTrace:
                pickerScreen(
                    title: "Pick an Image for Trace",
                    onPicked: { img in
                        selectedImage = img
                        mode = .tracing
                        if !didFinishOnboarding { withAnimation(.easeInOut(duration: 0.2)) { showOnboarding = true } }
                    },
                    onCancel: {
                        mode = .menu
                    }
                )

            case .pickingPaint:
                pickerScreen(
                    title: "Pick an Image for Paint",
                    onPicked: { img in
                        selectedImage = img
                        mode = .painting
                        if !didFinishOnboarding { withAnimation(.easeInOut(duration: 0.2)) { showOnboarding = true } }
                    },
                    onCancel: {
                        mode = .menu
                    }
                )

            case .tracing:
                tracingScreen
                    .allowsHitTesting(false) // lock for tracing

            case .painting:
                if let img = selectedImage {
                    PaintInlineScreen(
                        originalImage: img,
                        onExitToPicker: { goBackToMenu() }
                    )
                } else {
                    Text("No image loaded").foregroundColor(.white)
                }

            case .kidsGallery:
                KidsGalleryScreen(
                    onPick: { image, baseKey, resumeId in
                        selectedImage = image
                        kidsBaseKey = baseKey
                        kidsResumeSessionId = resumeId
                        mode = .kidsPainting
                    },
                    onBack: {
                        mode = .menu
                    },
                    onOpenSavedArt: {
                        mode = .kidsSavedArt
                    }
                )

            case .kidsSavedArt:
                KidsSavedArtScreen(
                    onOpen: { session in
                        // rebuild base image from session.baseKey
                        let base: UIImage =
                            (session.baseKey == "blank")
                            ? UIImage.kidsBlankBase(width: 2048, height: 2048, background: .white)
                            : (UIImage(named: session.baseKey) ?? UIImage.kidsBlankBase(width: 2048, height: 2048, background: .white))

                        selectedImage = base
                        kidsBaseKey = session.baseKey
                        kidsResumeSessionId = session.id   // reuse this as "open session id"
                        mode = .kidsPainting
                    },
                    onBack: {
                        mode = .kidsGallery
                    }
                )

            case .kidsPainting:
                if let img = selectedImage {
                    KidsPaintScreen(
                        baseKey: kidsBaseKey,
                        originalImage: img,
                        resumeSessionId: kidsResumeSessionId,
                        onBack: {
                            mode = .kidsGallery
                        },
                        onExitToPicker: {
                            kidsResumeSessionId = nil
                            kidsBaseKey = "blank"
                            goBackToMenu()
                        }
                    )
                } else {
                    Text("No image loaded").foregroundColor(.white)
                }
            }
            
            // =====================================================
            //  SECTION 3: ONBOARDING OVERLAY
            // =====================================================
            if showOnboarding && !didFinishOnboarding {
                OnboardingOverlay(
                    step: onboardingStep,
                    onSkip: {
                        didFinishOnboarding = true
                        showOnboarding = false
                    }
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            if didFinishOnboarding { showOnboarding = false }

            // Volume buttons exit to MENU (clean + consistent)
            volumeHandler.onVolumeUp = { goBackToMenu() }
            volumeHandler.onVolumeDown = { goBackToMenu() }
            volumeHandler.start()
        }
        .onDisappear { volumeHandler.stop() }
        .onChange(of: mode) { _ in
            if !didFinishOnboarding {
                withAnimation(.easeInOut(duration: 0.2)) { showOnboarding = true }
            }
        }
    }

    // =====================================================
    //  SECTION 4: SCREENS
    // =====================================================

    private var mainMenuScreen: some View {
        VStack(spacing: 14) {

            // ✅ Curved-top / flat-bottom header (blends with the card)
            Image("TracerStarPhoto")
                .resizable()
                .renderingMode(.original)
                .interpolation(.medium)           // iOS 15 safe
                .scaledToFit()
                .frame(maxWidth: .infinity)       // ✅ fill the card width
                .padding(.horizontal, 0)          // ✅ no inset so it feels "built-in"
                .clipShape(TopRoundedCorners(radius: 26)) // ✅ top curved, bottom flat
                .padding(.top, -20)               // ✅ pull UP into the rounded top
                .padding(.bottom, -1)             // ✅ reduce gap before buttons
                // ✨ soft white halo glow
                .shadow(color: Color.white.opacity(0.30), radius: 22, x: 0, y: 0)
                .shadow(color: Color.white.opacity(0.16), radius: 44, x: 0, y: 0)

            // TRACE + PAINT
            HStack(spacing: 14) {

                // TRACE ENGINE -> GREEN glow when pressed
                Button {
                    selectedImage = nil
                    mode = .pickingTrace
                } label: {
                    GalacticModeCard(
                        title: "", // ✅ remove TRACE label
                        subtitle: "", // ignored
                        icon: .asset("TraceStar Trace Engine"),
                        glow: Color(red: 0.20, green: 1.00, blue: 0.35)
                    )
                }
                .buttonStyle(GlowPressStyle(glow: .green))

                // NEBULAR ENGINE -> BLUE glow when pressed
                Button {
                    selectedImage = nil
                    mode = .pickingPaint
                } label: {
                    GalacticModeCard(
                        title: "", // ✅ remove PAINT label
                        subtitle: "", // ignored
                        icon: .asset("Nebular Art Engine"),
                        glow: Color(red: 0.35, green: 0.65, blue: 1.00)
                    )
                }
                .buttonStyle(GlowPressStyle(glow: .blue))
            }
            .padding(.horizontal, 14)

            // KIDS (Nibler Art Engine PNG button) -> YELLOW glow when pressed
            Button {
                selectedImage = nil
                mode = .kidsGallery
            } label: {
                KidsLogoCard()
            }
            .buttonStyle(GlowPressStyle(glow: Color(red: 1.00, green: 0.80, blue: 0.25)))
            .padding(.horizontal, 14)

            Spacer()
        }
        .padding(.vertical, 20)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    /// Menu-controlled picker: no auto-pop unless you want it.
    private func pickerScreen(
        title: String,
        onPicked: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        PhotoPickerView(
            title: title,
            onImagePicked: { img in
                onPicked(img)
            },
            onCancel: {
                onCancel()
            }
        )
    }

    private var tracingScreen: some View {
        ZStack {
            Color.black.opacity(0.88)

            if let img = selectedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.horizontal, 10)

                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.slash.fill")
                            .foregroundColor(.white.opacity(0.85))
                        Text("Tracing Mode • Volume button exits to Menu")
                            .foregroundColor(.white.opacity(0.85))
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .padding(.top, 18)
                    .padding(.horizontal, 14)

                    Spacer()
                }

            } else {
                Text("No image loaded").foregroundColor(.white)
            }
        }
        .ignoresSafeArea()
    }

    // =====================================================
    //  SECTION 5: ONBOARDING STEP
    // =====================================================
    private var onboardingStep: OnboardingOverlay.Step {
        switch mode {

        case .menu,
             .pickingTrace,
             .pickingPaint:
            return .step1

        case .tracing,
             .painting,
             .kidsGallery,
             .kidsPainting,
             .kidsSavedArt:
            return .step2
        }
    }
    
    // =====================================================
    //  SECTION 6: ACTIONS
    // =====================================================
    private func goBackToMenu() {
        selectedImage = nil
        mode = .menu

        if !didFinishOnboarding {
            didFinishOnboarding = true
            withAnimation(.easeInOut(duration: 0.2)) { showOnboarding = false }
        }
    }
}

// =====================================================
//  SECTION 7: PAINT SCREEN (INLINE) - Uses ArtEngine.swift
// =====================================================

private struct PaintInlineScreen: View {
    let originalImage: UIImage
    let onExitToPicker: () -> Void

    // Build coloring page once
    @State private var result: ImageProcessing.ColoringResult? = nil
    @State private var isBuilding: Bool = true

    // Canvas state
    @State private var overlay: UIImage? = nil
    @State private var tool: Tool = .bucket

    // Brush config
    @State private var brushColor: Color = .red
    @State private var brushWidth: CGFloat = 16

    // Touch tracking (for line tool)
    @State private var lastPoint: CGPoint? = nil

    enum Tool { case bucket, brush, eraser }

    var body: some View {
        ZStack {
            Color.black.opacity(0.90).ignoresSafeArea()

            if isBuilding {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing coloring page…")
                        .foregroundColor(.white.opacity(0.85))
                        .font(.system(size: 15, weight: .semibold))
                }
            } else if let r = result {
                VStack(spacing: 0) {

                    // Top bar
                    HStack(spacing: 10) {
                        Button(action: onExitToPicker) {
                            Label("Back", systemImage: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)

                        Spacer()

                        Picker("", selection: $tool) {
                            Text("Bucket").tag(Tool.bucket)
                            Text("Brush").tag(Tool.brush)
                            Text("Eraser").tag(Tool.eraser)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)

                        Spacer()

                        Button {
                            overlay = nil
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    // Controls
                    HStack(spacing: 12) {
                        ColorPicker("", selection: $brushColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 44, height: 28)

                        Slider(value: $brushWidth, in: 4...42, step: 1)
                            .frame(maxWidth: 220)

                        Text("\(Int(brushWidth))")
                            .foregroundColor(.white.opacity(0.85))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, alignment: .trailing)

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                    // Canvas
                    PaintCanvas(
                        baseImage: r.image,
                        overlay: $overlay,
                        mask: r.mask,
                        tool: tool,
                        uiColor: UIColor(brushColor),
                        brushWidth: brushWidth,
                        lastPoint: $lastPoint
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)

                    Spacer(minLength: 0)
                }
            } else {
                Text("Failed to build coloring page")
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            // Build once
            if result == nil {
                isBuilding = true
                DispatchQueue.global(qos: .userInitiated).async {
                    let built = ImageProcessing.makeColoringPage(from: originalImage, maxDimension: 1400)
                    DispatchQueue.main.async {
                        self.result = built
                        self.isBuilding = false
                    }
                }
            }
        }
    }
}
// =====================================================
//  SECTION 7A: PAINT CANVAS VIEW (tap bucket / drag brush)
// =====================================================

private struct PaintCanvas: View {
    let baseImage: UIImage

    @Binding var overlay: UIImage?
    let mask: BoundaryMask
    let tool: PaintInlineScreen.Tool
    let uiColor: UIColor
    let brushWidth: CGFloat

    @Binding var lastPoint: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let displaySize = aspectFitSize(imageSize: baseImage.size, in: geo.size)
            let origin = CGPoint(
                x: (geo.size.width - displaySize.width) * 0.5,
                y: (geo.size.height - displaySize.height) * 0.5
            )

            ZStack {
                Color.black.opacity(0.25)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                .position(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let p = value.location

                        let inside = p.x >= origin.x && p.x <= origin.x + displaySize.width &&
                                     p.y >= origin.y && p.y <= origin.y + displaySize.height
                        guard inside else { return }

                        let ix = (p.x - origin.x) / displaySize.width * CGFloat(mask.width)
                        let iy = (p.y - origin.y) / displaySize.height * CGFloat(mask.height)
                        let imgPoint = CGPoint(x: ix, y: iy)

                        switch tool {

                        case .bucket:
                            if value.translation == .zero {
                                overlay = FloodFill.fill(
                                    overlay: overlay,
                                    boundaryMask: mask,
                                    start: imgPoint,
                                    fillColor: uiColor,
                                    canvasSize: CGSize(width: mask.width, height: mask.height)
                                )
                            }

                        case .brush:
                            let cur = imgPoint
                            let from = lastPoint ?? cur

                            overlay = ImagePainter.drawLine(
                                on: overlay,
                                from: from,
                                to: cur,
                                color: uiColor,
                                width: brushWidth,
                                canvasSize: CGSize(width: mask.width, height: mask.height)
                            )

                            lastPoint = cur

                        case .eraser:
                            // Adult engine: eraser intentionally omitted.
                            break
                        }
                    }
                    .onEnded { _ in
                        lastPoint = nil
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func aspectFitSize(imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

// =====================================================
//  SECTION 7B: KIDS GALLERY (PRE-MADE ART + BLANK + RESUME + SAVED ART ENTRY)
// =====================================================

private struct KidsGalleryScreen: View {

    struct KidArt: Identifiable {
        let id = UUID()
        let assetName: String?        // nil = blank canvas card
        let title: String
        let baseKey: String           // stable key for saving/resume
    }

    // Opens a painting session
    let onPick: (_ image: UIImage, _ baseKey: String, _ resumeSessionId: String?) -> Void

    // Navigation
    let onBack: () -> Void

    // ✅ NEW: opens the Saved Art library screen
    let onOpenSavedArt: () -> Void

    // Grid pages (Assets.xcassets) + Blank Canvas as a grid item
    private let items: [KidArt] = [
        KidArt(assetName: nil,              title: "Blank Canvas", baseKey: "blank"),
        KidArt(assetName: "kids_star_cat",  title: "Star Cat",     baseKey: "kids_star_cat"),
        KidArt(assetName: "kids_candy_ship",title: "Candy Ship",   baseKey: "kids_candy_ship"),
        KidArt(assetName: "kids_planet_pop",title: "Planet Pop",   baseKey: "kids_planet_pop"),
        KidArt(assetName: "kids_ufo_smile", title: "Happy UFO",    baseKey: "kids_ufo_smile"),
        KidArt(assetName: "kids_galaxy_ice",title: "Galaxy Ice",   baseKey: "kids_galaxy_ice")
    ]

    // Resume availability (last session only)
    private var lastSessionId: String? { KidsPaintStore.getLastSessionId() }
    private var canResume: Bool { lastSessionId != nil }

    // Saved Art availability (folder/list screen)
    private var hasSavedArt: Bool { !KidsPaintStore.listSaved().isEmpty }

    var body: some View {
        ZStack {
            GalacticBackground()
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.pink.opacity(0.18),
                            Color.purple.opacity(0.10),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RadialGradient(
                        colors: [
                            Color.yellow.opacity(0.16),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: 420
                    )
                )
                .ignoresSafeArea()

            VStack(spacing: 12) {

                // Header
                HStack {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)

                    Spacer()

                    Text("Tracer Star Kids")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: "sparkles")
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)

                Text("Pick a pre-made picture to trace or paint.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.80))

                // ✅ ACTION ROW: Resume (last session) + Saved Art (folder/list)
                HStack(spacing: 12) {

                    // Resume = last session only
                    Button {
                        guard let id = lastSessionId,
                              let session = KidsPaintStore.loadSession(id: id) else { return }

                        let base: UIImage =
                            (session.baseKey == "blank")
                            ? UIImage.kidsBlankBase(width: 2048, height: 2048, background: .white)
                            : (UIImage(named: session.baseKey)
                               ?? UIImage.kidsBlankBase(width: 2048, height: 2048, background: .white))

                        onPick(base, session.baseKey, session.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Resume")
                        }
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(canResume ? 1.0 : 0.45))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(canResume ? 0.10 : 0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(canResume ? 0.16 : 0.10), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canResume)

                    // Saved Art = library screen (shows all saved sessions)
                    Button {
                        onOpenSavedArt()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                            Text("Saved Art")
                        }
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(hasSavedArt ? 1.0 : 0.45))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(hasSavedArt ? 0.10 : 0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(hasSavedArt ? 0.16 : 0.10), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasSavedArt)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

                // Grid (Blank Canvas is now inside here)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(items) { item in
                            Button {
                                if item.baseKey == "blank" {
                                    let blank = UIImage.kidsBlankBase(width: 2048, height: 2048, background: .white)
                                    onPick(blank, "blank", nil)
                                } else if let name = item.assetName, let img = UIImage(named: name) {
                                    onPick(img, item.baseKey, nil)
                                }
                            } label: {
                                KidsCard(title: item.title, image: item.assetName.flatMap { UIImage(named: $0) }, isBlank: item.baseKey == "blank")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 18)
                }
            }
        }
    }
}

// ✅ Card updated to support Blank Canvas visuals
private struct KidsCard: View {
    let title: String
    let image: UIImage?
    var isBlank: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                if isBlank {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white)
                            .padding(10)

                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(12)

                        Image(systemName: "square.dashed")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white.opacity(0.75))
                    }
                } else if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        Text("Missing asset")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .frame(height: 140)

            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
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
//  SECTION 8: UI - GALACTIC THEME COMPONENTS
// =====================================================

private enum GalacticIcon {
    case system(String)   // SF Symbol
    case asset(String)    // PNG in Assets.xcassets
}

private struct GalacticModeCard: View {
    let title: String
    let subtitle: String   // kept so Section 4 doesn’t break (ignored)
    let icon: GalacticIcon
    let glow: Color

    // ✅ BIGGER icon
    private let iconHeight: CGFloat = 140

    var body: some View {
        VStack(spacing: 14) {
            iconView
                .frame(height: iconHeight)
                // ✅ remove horizontal padding so the PNG can grow
                .shadow(color: glow.opacity(0.75), radius: 22, x: 0, y: 0)

            Text(title)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        // ✅ less vertical padding = more room for the icon
        .padding(.vertical, 12)
        .background(cardBackground)
        .overlay(baseBorder)
        .overlay(glowBorder)
        .shadow(color: glow.opacity(0.22), radius: 16, x: 0, y: 0)
    }

    // MARK: - Subviews (breaks up compiler work)

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)

        case .asset(let name):
            Image(name)
                // ✅ iOS15-safe (fixes your .high errors)
                .interpolation(.medium)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(glow.opacity(0.12))
                    .blur(radius: 12)
            )
    }

    private var baseBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.white.opacity(0.16), lineWidth: 1)
    }

    private var glowBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(glow.opacity(0.42), lineWidth: 1.4)
            .blur(radius: 0.7)
    }
}

// ✅ Kids logo button content (uses your transparent PNG asset)
private struct KidsLogoCard: View {
    private let assetName = "Nibler Art engine"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.10))

            Image(assetName)
                // ✅ iOS15-safe (fixes your .high errors)
                .interpolation(.medium)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

// ✅ glow + press animation (use per-button glow color in Section 4)
private struct GlowPressStyle: ButtonStyle {
    let glow: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .overlay(pressBorder(isPressed: configuration.isPressed))
            .shadow(
                color: glow.opacity(configuration.isPressed ? 0.90 : 0.0),
                radius: configuration.isPressed ? 18 : 0,
                x: 0, y: 0
            )
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    private func pressBorder(isPressed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
                glow.opacity(isPressed ? 0.95 : 0.35),
                lineWidth: isPressed ? 2.5 : 1.2
            )
            .blur(radius: isPressed ? 0.0 : 0.4)
    }
}

private struct GalacticBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.10, blue: 0.22),
                Color(red: 0.02, green: 0.02, blue: 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(StarField().opacity(0.55))
        .overlay(
            RadialGradient(
                colors: [Color.white.opacity(0.12), Color.clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 460
            )
        )
    }
}

private struct StarField: View {
    var body: some View {
        Canvas { ctx, size in
            let starCount = 140
            for i in 0..<starCount {
                let seed = CGFloat(i)
                let x = (seed * 73).truncatingRemainder(dividingBy: size.width)
                let y = (seed * 151).truncatingRemainder(dividingBy: size.height)
                let r = (seed.truncatingRemainder(dividingBy: 3)) + 0.9
                let rect = CGRect(x: x, y: y, width: r, height: r)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.75)))
            }
        }
    }
}
// =====================================================
//  SECTION 9: PHOTO PICKER (SwiftUI + UIKit wrapper)
// =====================================================

struct PhotoPickerView: View {
    let title: String
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var showPicker: Bool = false

    var body: some View {
        ZStack {
            GalacticBackground()

            VStack(spacing: 16) {
                Text("Tracer Star")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Choose a photo from your phone.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.78))

                Button {
                    showPicker = true
                } label: {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(.white)

                Button {
                    onCancel()
                } label: {
                    Text("Back")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.top, 6)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showPicker) {
            UIKitPhotoPicker { image in
                if let image { onImagePicked(image) }
                showPicker = false
            }
        }
    }
}

struct UIKitPhotoPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?) -> Void

        init(onPick: @escaping (UIImage?) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let item = results.first?.itemProvider else {
                onPick(nil)
                return
            }

            if item.canLoadObject(ofClass: UIImage.self) {
                item.loadObject(ofClass: UIImage.self) { object, _ in
                    DispatchQueue.main.async {
                        self.onPick(object as? UIImage)
                    }
                }
            } else {
                onPick(nil)
            }
        }
    }
}
// =====================================================
//  SECTION 10: ONBOARDING OVERLAY
// =====================================================

struct OnboardingOverlay: View {

    enum Step { case step1, step2 }

    let step: Step
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.70)

            VStack(spacing: 14) {
                Text("Quick Tutorial")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text(message)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.90))
                    .padding(.horizontal, 18)

                Button(action: onSkip) {
                    Text("Skip Tutorial")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(.white)
                .padding(.top, 6)
            }
            .padding(22)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding()
        }
        .ignoresSafeArea()
    }

    private var message: String {
        switch step {
        case .step1:
            return "Step 1:\nSelect an image from Photos.\n\nOnce selected, the image will lock so it’s easy to trace."
        case .step2:
            return "Step 2:\nYour image is locked.\n\nPress Volume Down to go back to photo select.\n(Volume Up also works.)"
        }
    }
}

// =====================================================
//  SECTION 11: VOLUME BUTTON HANDLER
// =====================================================

final class VolumeButtonHandler: ObservableObject {

    var onVolumeUp: (() -> Void)?
    var onVolumeDown: (() -> Void)?

    private let audioSession = AVAudioSession.sharedInstance()
    private var volumeObserver: NSKeyValueObservation?
    private var lastVolume: Float = 0.5

    private let volumeView: MPVolumeView = {
        let v = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 0, height: 0))
        v.isHidden = true
        return v
    }()

    func start() {
        installHiddenVolumeView()

        do {
            try audioSession.setCategory(.ambient, mode: .default, options: [])
            try audioSession.setActive(true, options: [])
        } catch {
            print("VolumeButtonHandler: Audio session error: \(error)")
        }

        lastVolume = audioSession.outputVolume

        volumeObserver = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self else { return }
            guard let newVol = change.newValue else { return }

            if abs(newVol - self.lastVolume) < 0.0001 { return }

            if newVol > self.lastVolume {
                self.onVolumeUp?()
            } else {
                self.onVolumeDown?()
            }

            // Optional: prevent volume drift
            self.setSystemVolume(self.lastVolume)
        }
    }

    func stop() {
        volumeObserver?.invalidate()
        volumeObserver = nil

        do { try audioSession.setActive(false, options: []) }
        catch { /* fine */ }
    }

    private func installHiddenVolumeView() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }

        if volumeView.superview == nil {
            window.addSubview(volumeView)
        }
    }

    private func setSystemVolume(_ value: Float) {
        let slider = volumeView.subviews.compactMap { $0 as? UISlider }.first
        slider?.value = value
    }
}
// =====================================================
//  SHAPES / HELPERS
// =====================================================

private struct TopRoundedCorners: Shape {
    var radius: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

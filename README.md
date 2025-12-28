# TraceStar

TraceStar is an iOS SwiftUI app that lets users import photos and trace directly over them using boundary-aware brushes, region-locked fills, and layered stroke rendering powered by a custom CoreGraphics engine.

## What it does
- Import a photo and trace on top with layered strokes
- Fill regions without bleeding across boundaries (region-locked fill)
- Mask/contain brush strokes so drawing respects edges
- Includes a separate child-friendly engine for simpler interaction

## Tech highlights
- SwiftUI UI layer + UIKit/CoreGraphics drawing engine
- Custom stroke rendering pipeline (real-time feedback)
- Boundary-aware filling + containment logic
- Modular “art engine” design (standard + kids modes)

## Screenshots / Demo
> Add images here once ready:
- `Screenshots/trace_mode.png`
- `Screenshots/fill_mode.png`

## How to run
1. Clone the repo
2. Open `TraceStar.xcodeproj` in Xcode
3. Select an iOS Simulator (or device)
4. Run (⌘R)

## Notes
This project focuses on the drawing/tracing engine and interaction quality. UI polish and export/share features can be expanded later.

<img width="1125" height="2436" alt="IMG_9542" src="https://github.com/user-attachments/assets/07d1827d-d52c-459e-b158-2a9769756fa9" />

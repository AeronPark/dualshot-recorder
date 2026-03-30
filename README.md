# DualShot Recorder

Record portrait (9:16) and landscape (16:9) video simultaneously from your iPhone's dual cameras.

## Features

- **Dual Camera Recording** - Capture from wide and ultra-wide cameras at the same time
- **Single Camera Modes** - Wide, ultra-wide, and front camera options
- **Multiple Resolutions** - 1080p and 4K support
- **Frame Rate Options** - 24, 30, and 60 fps
- **File Formats** - MOV and MP4 export
- **Torch Control** - Built-in flashlight toggle
- **Storage Estimate** - Real-time available space display
- **Privacy First** - No ads, no tracking, no accounts

## Requirements

- iPhone XS or newer (for dual camera mode)
- iOS 17.0+
- Xcode 15.0+

## Installation

1. Clone the repository
2. Install XcodeGen: `brew install xcodegen`
3. Generate project: `xcodegen generate`
4. Open `DualShot.xcodeproj` in Xcode
5. Set your development team
6. Build and run on a physical device

## Usage

1. Grant camera, microphone, and photo library permissions
2. Select recording mode (Dual/Wide/Ultra-wide/Front)
3. Adjust settings (resolution, frame rate, format)
4. Tap the record button
5. Videos are saved directly to your Photos library

## Architecture

```
DualShot/
├── DualShotApp.swift          # App entry point
├── Views/
│   ├── ContentView.swift      # Main camera interface
│   ├── CameraPreviewView.swift # Camera preview layer
│   └── SettingsView.swift     # Settings screen
├── Camera/
│   └── CameraManager.swift    # AVFoundation camera handling
├── Assets.xcassets/           # App icons and colors
└── Info.plist                 # App configuration
```

## License

MIT

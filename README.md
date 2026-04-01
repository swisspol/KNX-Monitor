# KNX Monitor

A macOS, Windows, and iPad application for real-time monitoring of KNX/IP bus traffic. Built with Flutter.

## Requirements

- macOS 10.15 (Catalina) or later, Windows 10+, or iPad (iPadOS 13+)
- Flutter SDK 3.41+ with Dart 3.11+
- A KNX/IP gateway or bridge on the local network

## Building

```bash
flutter pub get
flutter build macos --release    # macOS
flutter build windows --release  # Windows
flutter build ios --release      # iPad
```

The built app will be at:
- **macOS:** `build/macos/Build/Products/Release/KNX Monitor.app`
- **Windows:** `build/windows/x64/runner/Release/`
- **iPad:** `build/ios/iphoneos/Runner.app`

## Development

```bash
flutter run -d macos     # macOS
flutter run -d windows   # Windows
flutter run -d ipad      # iPad
```

## License

Copyright 2026 Pierre-Olivier Latour. All rights reserved.

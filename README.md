# KNX Monitor

A macOS and Windows desktop application for real-time monitoring of KNX/IP bus traffic. Built with Flutter.

## Requirements

- macOS 10.15 (Catalina) or later, or Windows 10+
- Flutter SDK 3.41+ with Dart 3.11+
- A KNX/IP gateway or bridge on the local network

## Building

```bash
flutter pub get
flutter build macos --release    # macOS
flutter build windows --release  # Windows
```

The built app will be at:
- **macOS:** `build/macos/Build/Products/Release/KNX Monitor.app`
- **Windows:** `build/windows/x64/runner/Release/`

## Development

```bash
flutter run -d macos     # macOS
flutter run -d windows   # Windows
```

## License

Copyright 2026 Pierre-Olivier Latour. All rights reserved.

# KNX Monitor

A macOS desktop application for real-time monitoring of KNX/IP bus traffic. Built with Flutter.

## Requirements

- macOS 10.15 (Catalina) or later
- Flutter SDK 3.18+ with Dart 3.11+
- A KNX/IP gateway or bridge on the local network

## Building

```bash
flutter pub get
flutter build macos --release
```

The built app will be at `build/macos/Build/Products/Release/KNX Monitor.app`.

## Development

```bash
flutter run -d macos
```

## License

Copyright 2026 Pierre-Olivier Latour. All rights reserved.

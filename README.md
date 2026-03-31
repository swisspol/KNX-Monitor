# KNX Monitor

A macOS desktop application for real-time monitoring of KNX/IP bus traffic. Built with Flutter.

## Features

- **Auto-discovery** of KNX/IP bridges on the local network via multicast
- **Live event table** showing all bus telegrams with decoded values
- **ETS project import** (.knxproj files) for resolving device names, group addresses, and datapoint types
- **DPT decoding** for common types: boolean, percentage, 16-bit float (temperature, humidity, lux), 32-bit float, strings, and more
- **Search** with full-word matching across device, source, destination, group address, DPT, and value columns
- **Selection and copy** (Cmd+C) exports selected rows as a JSON array
- **Color-coded UI** with semantic colors for direction, APCI type, DPT family, and address bubbles

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

## Usage

1. On launch, the app discovers KNX/IP bridges on the network and connects automatically
2. If multiple bridges are found, a selection dialog is shown
3. Use the folder icon in the toolbar to load an ETS project file (.knxproj) for device and group address name resolution
4. Bus events appear in the table as they arrive, newest first
5. Use the search field to filter events by keyword
6. Click rows to select, Cmd+Click to toggle, Shift+Click for range selection
7. Cmd+C copies selected rows as JSON, Cmd+A selects all

## KNX/IP Protocol

The app implements the KNXnet/IP tunneling protocol:
- Discovery via multicast search (224.0.23.12:3671)
- Tunnel connection with automatic heartbeat
- cEMI frame parsing for group telegrams
- APCI decoding (Read, Write, Response)

## License

Copyright 2026 Pierre-Olivier Latour. All rights reserved.

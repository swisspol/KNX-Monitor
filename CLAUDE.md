# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

```bash
flutter pub get          # Install dependencies
flutter run -d macos     # Run in debug mode
flutter build macos --release  # Production build → build/macos/Build/Products/Release/KNX Monitor.app
flutter analyze          # Static analysis (must pass with no issues)
flutter test             # Run widget tests
```

Always run `flutter analyze` after code changes — it must report zero issues.

## Architecture

This is a **macOS-only** Flutter desktop app that monitors KNX/IP home automation bus traffic in real time.

### Data Flow

```
KnxConnection (UDP sockets) → Stream<KnxEvent> → _KnxMonitorPageState → ListView table
                                                        ↑
                                          EtsProject (ZIP/XML parser)
                                          provides device/GA name resolution
```

### Module Responsibilities

- **`lib/knx_connection.dart`** — KNXnet/IP protocol: multicast bridge discovery, UDP tunnel connection, cEMI frame parsing, heartbeat. Exposes three broadcast streams: `events`, `stateChanges`, `statusMessages`. Has a callback `onMultipleBridges` for UI bridge selection.

- **`lib/knx_types.dart`** — Data models (`KnxEvent`, `GAInfo`, `DeviceInfo`, `KnxBridge`), protocol constants, address formatting, DPT decoding (boolean, percentage, float16, float32, string). `KnxEvent.deviceName` and `groupName` are mutable so they can be updated when an ETS project is loaded after events are already captured.

- **`lib/ets_project.dart`** — Parses `.knxproj` files (ZIP archives containing ETS XML). Extracts device topology from `P-*/0.xml`, group addresses with DPT types, and product catalog from manufacturer `Hardware.xml`/`Catalog.xml` files.

- **`lib/main.dart`** — All UI: `PlatformMenuBar` (macOS-native menus), toolbar with search, responsive table with `Expanded` flex columns (Device/Group Address stretch), row selection model, JSON copy. Search uses diacritic-insensitive full-word matching.

### Key Design Decisions

- **No state management package** — uses `StatefulWidget` with `StreamController` listeners.
- **Newest events first** — events insert at index 0; selected indices shift +1 on each insert.
- **1000 event buffer** — oldest events are dropped without resetting message count or start time.
- **macOS platform menu** — `PlatformMenuBar` is guarded by `defaultTargetPlatform` check (not `Platform.isMacOS`) so tests pass in the Flutter test harness which simulates Android.
- **Sandbox entitlements** — network client/server for KNX UDP, `files.user-selected.read-only` for file picker. CLI path access is not available under sandbox.
- **Test isolation** — `KnxMonitorPage` has `autoConnect` parameter (default true) to prevent network activity in tests.

## macOS Configuration

- App metadata: `macos/Runner/Configs/AppInfo.xcconfig` (name, bundle ID, copyright)
- Entitlements: `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`
- Window sizing: `macos/Runner/MainFlutterWindow.swift` (initial 1300x800, min 1080x400)
- App icon: `macos/Runner/Assets.xcassets/AppIcon.appiconset/` (also copied to `assets/app_icon.png` for About dialog)

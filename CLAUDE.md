# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

```bash
flutter pub get          # Install dependencies
flutter run -d macos     # Run in debug mode (macOS)
flutter run -d windows   # Run in debug mode (Windows)
flutter run -d ipad      # Run in debug mode (iPad)
flutter build macos --release  # Production build → build/macos/Build/Products/Release/KNX Monitor.app
flutter build windows --release  # Production build → build/windows/x64/runner/Release/
flutter build ios --release      # Production build for iPad
flutter analyze          # Static analysis (must pass with no issues)
```

Always run `flutter analyze` after code changes — it must report zero issues.

## Architecture

A **macOS, Windows, and iPad** Flutter app that monitors KNX/IP home automation bus traffic in real time.

### Data Flow

```
KnxConnection (UDP sockets) → Stream<KnxEvent> → _KnxMonitorPageState → ListView table
                                                        ↑
                                          EtsProject (ZIP/XML parser)
                                          provides device/GA name resolution
```

### Module Responsibilities

- **`lib/knx_connection.dart`** — KNXnet/IP protocol: multicast bridge discovery, UDP tunnel connection with automatic NAT mode (uses `0.0.0.0:0` HPAI when bridge is on a different subnet), cEMI frame parsing, heartbeat. Exposes three broadcast streams: `events`, `stateChanges`, `statusMessages`. The `connect()` method takes an explicit host and port; discovery is separate.

- **`lib/knx_types.dart`** — Data models (`KnxEvent`, `GAInfo`, `DeviceInfo`, `KnxBridge`), protocol constants, address formatting, DPT decoding (boolean, dim control, percentage, float16, uint32, float32, string). `KnxEvent.deviceName` and `groupName` are mutable so they can be updated when an ETS project is loaded after events are already captured.

- **`lib/ets_project.dart`** — Parses `.knxproj` files (ZIP archives containing ETS XML). Extracts device topology from `P-*/0.xml`, group addresses with DPT types, and product catalog from manufacturer `Hardware.xml`/`Catalog.xml` files.

- **`lib/app_log.dart`** — Centralized logging setup using the `logging` package. Initializes a root logger at `INFO` level and maintains a 1000-entry `logHistory` ring buffer of `LogRecord`s.

- **`lib/log_window.dart`** — `LogWindow` widget: a scrollable, selectable log viewer opened from the toolbar. Supports row selection (click, Cmd+click, Shift+click), Cmd+C to copy, auto-scroll to bottom, and color-coded severity levels (INFO/WARN/ERROR).

- **`lib/main.dart`** — All UI: `PlatformMenuBar` (macOS-native menus, guarded by `defaultTargetPlatform`), connect dialog with discovery + manual host/port entry, toolbar with search, responsive table with `Expanded` flex columns (Device/Group Address stretch), row selection model, JSON copy via Cmd+C, and log window access. Search uses diacritic-insensitive full-word matching. Initializes logging via `initLogging()` at startup.

### Key Design Decisions

- **No state management package** — uses `StatefulWidget` with `StreamController` listeners.
- **Connect dialog** — always shown on launch and reconnect. Runs bridge discovery in background while user can type host/port. Remembers last successful host/port via `SharedPreferences`. Auto-reopens on connection failure.
- **NAT mode** — automatically uses `0.0.0.0:0` HPAI when bridge is on a different /24 subnet (e.g. VPN/Tailscale).
- **Newest events first** — events insert at index 0; selected indices shift +1 on each insert.
- **1000 event buffer** — oldest events are dropped without resetting message count or start time.
- **Sandbox entitlements (macOS)** — network client/server for KNX UDP, `files.user-selected.read-only` for file picker. CLI path access is not available under sandbox.
- **Color constants** — `_cRed`, `_cGreen`, `_cBlue`, `_cGrey`, `_cText`, `_cTextDim` shared across Dir, APCI, DPT, Value columns. DPT colors are semantic per major number.

## Platform Configuration

### macOS
- App metadata: `macos/Runner/Configs/AppInfo.xcconfig` (name, bundle ID, copyright)
- Entitlements: `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`
- Window sizing: `macos/Runner/MainFlutterWindow.swift` (initial 1300x800, min 1080x400)
- App icon: `macos/Runner/Assets.xcassets/AppIcon.appiconset/` (also copied to `assets/app_icon.png` for About dialog)

### Windows
- Window title and size: `windows/runner/main.cpp` (initial 1300x800)
- Minimum size: `windows/runner/win32_window.cpp` (`WM_GETMINMAXINFO` handler, min 1080x400)

### iOS (iPad only)
- App metadata: `ios/Runner/Info.plist` (display name, orientations, scene config)
- iPad only: `TARGETED_DEVICE_FAMILY = 2` in Xcode project; no iPhone icon entries
- App icon: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (iPad sizes + 1024px marketing)
- Icon generation: `generate_icons.py` generates all platform icons (macOS, iOS, Windows) from `icon.png`

### CI/CD
- `.github/workflows/build_macos.yml` — macOS build, artifact upload, GitHub Release on `v*` tags
- `.github/workflows/build_windows.yml` — Windows build with bundled VC++ runtime DLLs
- Build number: `github.run_number`; git SHA injected via `--dart-define=GIT_SHA`
- Version defined in `pubspec.yaml`; copyright in `AppInfo.xcconfig`

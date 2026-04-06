# Code Review — KNX Monitor

Review of the full codebase (~3100 lines across 6 Dart files).

---

## Bugs

### 1. APDU length calculation is off-by-one (`knx_connection.dart:298-299`)

```dart
final apduLen = dataLen + 1;
if (cemi.length < offset + 7 + apduLen) return;
final apdu = cemi.sublist(offset + 7, offset + 7 + apduLen);
```

The cEMI `dataLen` field already represents the number of APDU data bytes (after the length octet). Adding 1 gives `apduLen = dataLen + 1`, but then the code reads `apduLen` bytes starting at `offset + 7`. According to the KNX specification, the length field at `offset + 6` contains the count of bytes that follow it, so the APDU is `dataLen + 1` octets long (length octet + data). However, the slice begins at `offset + 7`, which is already past the length octet. This means the code reads **one byte too many** — it will silently grab one extra byte from whatever follows the cEMI frame. In practice this usually works because the KNXnet/IP tunnel packet has trailing padding or the next frame, but it can produce garbage in the last byte of long APDUs and corrupt `formatRawHex` / `decodeValue` output.

### 2. `logHistory` ring buffer uses O(n) removal (`app_log.dart:13-14`)

```dart
if (logHistory.length > 1000) {
  logHistory.removeAt(0);
}
```

`removeAt(0)` on a `List` shifts all elements. With a 1000-entry cap this is called on every log record after the buffer fills up, making each log event O(1000). Should use a proper ring buffer (e.g. `dart:collection` `Queue` or manual circular index).

### 3. Sequence counter overflow not handled (`knx_connection.dart:258`)

```dart
_seqSend++;
```

The KNXnet/IP tunnel sequence counter is an unsigned 8-bit value (0–255). The code masks it to `& 0xFF` when building the packet (line 258: `_seqSend & 0xFF`), but `_seqSend` itself grows unbounded. While the masking prevents protocol errors, the integer will eventually overflow Dart's 64-bit int range in extremely long sessions (practically unreachable, but semantically wrong). The counter should be wrapped: `_seqSend = (_seqSend + 1) & 0xFF`.

### 4. `DPT-3` (Dim Control) not decoded in `decodeValue` (`knx_types.dart:285-331`)

`normalizeDPT` maps `DPST-3-*` to `dptDimControl`, but `decodeValue` has no `case dptDimControl:` branch. It falls through to the `default` case, which renders the raw 6-bit value as a decimal integer — losing the direction/step semantics. A dim control value should decode to e.g. "Up 3" / "Down 7" / "Stop".

### 5. `guessDPT` never returns `dptDimControl` or `dptUint32` (`knx_types.dart:200-215`)

When no ETS project is loaded, 1-byte APDUs are guessed as `dptPercent` and 4-byte APDUs as `dptFloat32`. This means dim control telegrams (1-byte) are always misidentified as percentage, and 32-bit unsigned counters are decoded as IEEE 754 floats. Without ETS data the heuristic is inherently lossy, but the 4-byte case could at least check for NaN/Inf to flag likely non-float data.

### 6. Dark mode colors are hardcoded light-theme values (`main.dart:845-851`)

```dart
static const _cText = Color(0xFF2C2C2C);
static const _cTextDim = Color(0xFF757575);
```

These near-black colors are used throughout rows, the send panel, and the sources panel regardless of the current brightness. In dark mode they become nearly invisible against dark backgrounds. All `_c*` constants should be resolved from the `ColorScheme` at build time instead of being compile-time constants.

### 7. Read/Response pair highlighting hardcoded for light theme (`main.dart:1788`)

```dart
bg = const Color(0xFFC8E6C9); // light green
```

This light green background makes text unreadable in dark mode. Same issue as above — should adapt to brightness.

### 8. LogWindow hardcoded light-theme row backgrounds (`log_window.dart:178-179`)

```dart
bg = const Color(0xFFFFCDD2); // light red
bg = const Color(0xFFFFF3E0); // light orange
```

Warning/error row colors will look washed-out and clash in dark mode.

### 9. `_encodeKnxFloat16` precision loss on negative values (`main.dart:1318-1333`)

```dart
if (sign == 1) mant = 2048 - mant;
```

For negative numbers the mantissa is computed as `2048 - mant`. But `mant` has already been right-shifted by dividing by 2 and rounding in the `while` loop. The two's-complement subtraction should be applied to the final mantissa, but rounding errors accumulate — e.g. encoding −0.01 yields a different value than the standard algorithm specifies. The encoding should follow the spec more closely: compute mantissa with sign, then apply two's complement on the 11-bit value.

### 10. Stream subscriptions in `_KnxMonitorPageState.initState` are never cancelled (`main.dart:184-221`)

```dart
_connection.stateChanges.listen((s) { ... });
_connection.statusMessages.listen((_) { ... });
_connection.events.listen((event) { ... });
```

These three `StreamSubscription`s are never stored or cancelled in `dispose()`. Because `_connection` is a broadcast `StreamController`, listeners are only cleaned up when the controller is closed (which happens in `_connection.dispose()`). If `_KnxMonitorPageState` were ever rebuilt without disposing the connection (e.g. a hot reload that recreates the state), the old listeners would leak and the old state would continue receiving events.

---

## Potential Crashes / Robustness Issues

### 11. Heartbeat continues after connection error

If the bridge sends a heartbeat error response (line 152), the code logs the error but does not disconnect or stop the heartbeat timer. The connection enters a zombie state — the UI shows "Connected" but the bridge has dropped the tunnel. The heartbeat error handler should call `disconnect()` and transition to `error` or `disconnected` state.

### 12. No reconnection logic after unexpected disconnect

When the bridge sends a `DISCONNECT_REQUEST` (line 159), the state changes to `disconnected` but the connect dialog is never re-shown. The user must manually click the connect button. The CLAUDE.md says "Auto-reopens on connection failure" but that only applies during the initial connect flow — mid-session disconnects are silent.

### 13. `_showConnectDialog` swallows all exceptions (`main.dart:525-527`)

```dart
} catch (_) {
  // Safety net
}
```

This catches and silently discards any exception from the entire connect dialog flow, including `setState` after unmount, null dereferences, etc. At minimum the error should be logged.

### 14. `discoverBridges` doesn't close socket on error (`knx_connection.dart:333-393`)

If the `ZipDecoder`, `send`, or stream processing throws, the socket opened on line 334 is never closed. Should wrap in try/finally.

### 15. No bounds checking on DIB name extraction (`knx_connection.dart:379-382`)

```dart
final nameStart = dibOffset + 24;
final nameBytes = dg.data.sublist(nameStart, nameStart + 30);
```

If the packet claims `dibLen >= 54` but the actual data is shorter (malformed packet), this will throw a `RangeError`. The existing `dg.data.length >= dibOffset + dibLen` check should prevent this, but trusting the wire length field is fragile.

---

## Design & Code Quality Improvements

### 16. `ConnectionState` name conflicts with Flutter (`knx_connection.dart:10`)

`ConnectionState` clashes with `dart:io`'s `ConnectionState` and is awkwardly imported as `knx.ConnectionState` everywhere. Rename to `KnxConnectionState` to avoid the conflict.

### 17. `main.dart` is 1890 lines — too large

The file contains all UI code: app shell, connect dialog, about dialog, toolbar, event table, send panel, source filter panel, row rendering, selection model, search logic, and time formatting. Extracting these into separate widgets/files would significantly improve maintainability:
- `connect_dialog.dart`
- `send_panel.dart`
- `source_filter_panel.dart`
- `event_table.dart`

### 18. `_RangeFormatter` and `_PortRangeFormatter` are redundant (`main.dart:109-131`)

`_PortRangeFormatter` is just `_RangeFormatter(65535)`. The former should be removed and replaced with the latter.

### 19. Source panel always-true ternary (`main.dart:1630`)

```dart
_addrColor(src) == _addrColor(src)
    ? Container(...) : const SizedBox(),
```

This condition is always `true` (comparing a value to itself). The ternary and the `SizedBox()` branch are dead code.

### 20. `_sendDptTypes` dropdown includes DPTs not in the switch statement (`main.dart:1196-1213`)

The dropdown lists `4.x`, `10.x`, `11.x` DPT types, but these have corresponding `case` branches in `_doSend` that are unreachable because they're not in the `_sendDptTypes` list (actually they're handled, but never tested). More importantly, the DPT dropdown is long and not searchable — consider a searchable dropdown or grouping.

### 21. No unit tests

There are zero test files. The protocol parsing (`decodeAPCI`, `decodeValue`, `decodeKNXFloat16`, `formatGroupAddr`, `_parseCEMI`, `_encodeKnxFloat16`) and ETS project loading are highly testable and deal with binary protocols where off-by-one errors are common. Adding tests for these would catch regressions.

### 22. `_normalize` diacritics table is incomplete (`main.dart:135`)

The table handles common Western European diacritics but misses many others (e.g. Ð, ð, Þ, þ, ß, Ğ, ğ, Ş, ş, etc.). Consider using a proper Unicode normalization library like `diacritic` from pub.dev.

### 23. Keyboard shortcuts use `meta` (Cmd) only — broken on Windows (`log_window.dart:145-146`, `main.dart:74-79`)

```dart
const SingleActivator(LogicalKeyboardKey.keyC, meta: true)
```

`meta: true` maps to the Cmd key on macOS but the Windows/Super key on Windows. Windows users expect Ctrl+C. The app targets Windows too, so shortcuts should adapt per platform or use both `meta` and `control`.

### 24. `EtsProject.loadFromBytes` runs synchronously on the UI thread (`ets_project.dart:35`)

Parsing a ZIP archive and multiple XML files is CPU-intensive. For large ETS projects this will freeze the UI. Should be run in an isolate via `compute()`.

### 25. Missing `dispose` for `_gaMainCtrl`, `_gaMiddleCtrl`, `_gaSubCtrl`, `_valueCtrl` (`main.dart:1189-1191`)

Four `TextEditingController` instances in the send panel are never disposed.

### 26. `hashCode`-based color for addresses is not deterministic across runs (`main.dart:913`)

```dart
final hash = src.hashCode & 0x7FFFFFFF;
```

`String.hashCode` in Dart is not guaranteed to be stable across runs or platforms. The same address could get different colors after restarting the app. Use a simple deterministic hash (e.g. FNV-1a on the code units) for stable coloring.

---

## Security

### 27. No validation of KNXnet/IP protocol version (`knx_types.dart:133-142`)

The `knxHeader` builder always uses protocol version `0x10` (byte 1), but incoming packets never verify bytes 0–1 are `0x06 0x10`. A malformed or spoofed packet could be processed as valid KNX data. This is low-risk on a local network but worth noting.

### 28. File path from `_showAbout` is unsanitized (`main.dart:538-539`)

```dart
final plistPath = '${File(Platform.resolvedExecutable).parent.parent.path}/Info.plist';
```

This constructs a file path from the executable location and reads it. If the executable path contained `..` segments, this could read unexpected files. Low-risk since it reads a plist, but path construction should use `Uri` or `path` package for robustness.

---

## Summary

| Category | Count |
|----------|-------|
| Bugs | 10 |
| Robustness | 5 |
| Design/Quality | 11 |
| Security | 2 |

The codebase is well-structured for its size, with clean separation of protocol handling, data models, and UI. The main areas to address are:

1. **Dark mode support** — hardcoded colors make the app unusable in dark mode (items 6–8)
2. **Protocol correctness** — APDU length, DPT-3 decoding, sequence counter (items 1, 3, 4)
3. **Testability** — no tests for critical binary protocol parsing (item 21)
4. **`main.dart` decomposition** — single 1890-line file should be split (item 17)
5. **Cross-platform keyboard shortcuts** — Cmd-only shortcuts break on Windows (item 23)

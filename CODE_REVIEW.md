# Code Review — KNX Monitor

Review of the full codebase (~3200 lines across 9 Dart files).

---

## Bugs

### 1. `logHistory` ring buffer uses O(n) removal (`app_log.dart:13-14`)

```dart
if (logHistory.length > 1000) {
  logHistory.removeAt(0);
}
```

`removeAt(0)` on a `List` shifts all elements. With a 1000-entry cap this is called on every log record after the buffer fills up, making each log event O(1000). Should use a proper ring buffer (e.g. `dart:collection` `Queue` or manual circular index).

### 2. Sequence counter overflow not handled (`knx_connection.dart:258`)

```dart
_seqSend++;
```

The KNXnet/IP tunnel sequence counter is an unsigned 8-bit value (0–255). The code masks it to `& 0xFF` when building the packet (line 258: `_seqSend & 0xFF`), but `_seqSend` itself grows unbounded. While the masking prevents protocol errors, the integer will eventually overflow Dart's 64-bit int range in extremely long sessions (practically unreachable, but semantically wrong). The counter should be wrapped: `_seqSend = (_seqSend + 1) & 0xFF`.

### 3. `DPT-3` (Dim Control) not decoded in `decodeValue` (`knx_types.dart:285-331`)

`normalizeDPT` maps `DPST-3-*` to `dptDimControl`, but `decodeValue` has no `case dptDimControl:` branch. It falls through to the `default` case, which renders the raw 6-bit value as a decimal integer — losing the direction/step semantics. A dim control value should decode to e.g. "Up 3" / "Down 7" / "Stop".

### 4. `guessDPT` never returns `dptDimControl` or `dptUint32` (`knx_types.dart:200-215`)

When no ETS project is loaded, 1-byte APDUs are guessed as `dptPercent` and 4-byte APDUs as `dptFloat32`. This means dim control telegrams (1-byte) are always misidentified as percentage, and 32-bit unsigned counters are decoded as IEEE 754 floats. Without ETS data the heuristic is inherently lossy, but the 4-byte case could at least check for NaN/Inf to flag likely non-float data.

### 5. Dark mode colors are hardcoded light-theme values (`main.dart:845-851`)

```dart
static const _cText = Color(0xFF2C2C2C);
static const _cTextDim = Color(0xFF757575);
```

These near-black colors are used throughout rows, the send panel, and the sources panel regardless of the current brightness. In dark mode they become nearly invisible against dark backgrounds. All `_c*` constants should be resolved from the `ColorScheme` at build time instead of being compile-time constants.

### 6. Read/Response pair highlighting hardcoded for light theme (`main.dart:1788`)

```dart
bg = const Color(0xFFC8E6C9); // light green
```

This light green background makes text unreadable in dark mode. Same issue as above — should adapt to brightness.

### 7. LogWindow hardcoded light-theme row backgrounds (`log_window.dart:178-179`)

```dart
bg = const Color(0xFFFFCDD2); // light red
bg = const Color(0xFFFFF3E0); // light orange
```

Warning/error row colors will look washed-out and clash in dark mode.

### 8. `_encodeKnxFloat16` precision loss on negative values (`main.dart:1318-1333`)

```dart
if (sign == 1) mant = 2048 - mant;
```

For negative numbers the mantissa is computed as `2048 - mant`. But `mant` has already been right-shifted by dividing by 2 and rounding in the `while` loop. The two's-complement subtraction should be applied to the final mantissa, but rounding errors accumulate — e.g. encoding −0.01 yields a different value than the standard algorithm specifies. The encoding should follow the spec more closely: compute mantissa with sign, then apply two's complement on the 11-bit value.

### 9. Stream subscriptions in `_KnxMonitorPageState.initState` are never cancelled (`main.dart:184-221`)

```dart
_connection.stateChanges.listen((s) { ... });
_connection.statusMessages.listen((_) { ... });
_connection.events.listen((event) { ... });
```

These three `StreamSubscription`s are never stored or cancelled in `dispose()`. Because `_connection` is a broadcast `StreamController`, listeners are only cleaned up when the controller is closed (which happens in `_connection.dispose()`). If `_KnxMonitorPageState` were ever rebuilt without disposing the connection (e.g. a hot reload that recreates the state), the old listeners would leak and the old state would continue receiving events.

---

## Potential Crashes / Robustness Issues

### 10. Heartbeat continues after connection error

If the bridge sends a heartbeat error response (line 152), the code logs the error but does not disconnect or stop the heartbeat timer. The connection enters a zombie state — the UI shows "Connected" but the bridge has dropped the tunnel. The heartbeat error handler should call `disconnect()` and transition to `error` or `disconnected` state.

### 11. No reconnection logic after unexpected disconnect

When the bridge sends a `DISCONNECT_REQUEST` (line 159), the state changes to `disconnected` but the connect dialog is never re-shown. The user must manually click the connect button. The CLAUDE.md says "Auto-reopens on connection failure" but that only applies during the initial connect flow — mid-session disconnects are silent.

### 12. `_showConnectDialog` swallows all exceptions (`main.dart:525-527`)

```dart
} catch (_) {
  // Safety net
}
```

This catches and silently discards any exception from the entire connect dialog flow, including `setState` after unmount, null dereferences, etc. At minimum the error should be logged.

### 13. `discoverBridges` doesn't close socket on error (`knx_connection.dart:333-393`)

If the `ZipDecoder`, `send`, or stream processing throws, the socket opened on line 334 is never closed. Should wrap in try/finally.

### 14. No bounds checking on DIB name extraction (`knx_connection.dart:379-382`)

```dart
final nameStart = dibOffset + 24;
final nameBytes = dg.data.sublist(nameStart, nameStart + 30);
```

If the packet claims `dibLen >= 54` but the actual data is shorter (malformed packet), this will throw a `RangeError`. The existing `dg.data.length >= dibOffset + dibLen` check should prevent this, but trusting the wire length field is fragile.

---

## Design & Code Quality Improvements

### 15. `_sendDptTypes` dropdown includes DPTs not in the switch statement (`send_panel.dart`)

The dropdown lists `4.x`, `10.x`, `11.x` DPT types, but these have corresponding `case` branches in `_doSend` that are unreachable because they're not in the `_sendDptTypes` list (actually they're handled, but never tested). More importantly, the DPT dropdown is long and not searchable — consider a searchable dropdown or grouping.

### 16. `_normalize` diacritics table is incomplete (`main.dart`)

The table handles common Western European diacritics but misses many others (e.g. Ð, ð, Þ, þ, ß, Ğ, ğ, Ş, ş, etc.). Consider using a proper Unicode normalization library like `diacritic` from pub.dev.

### 17. `EtsProject.loadFromBytes` runs synchronously on the UI thread (`ets_project.dart`)

Parsing a ZIP archive and multiple XML files is CPU-intensive. For large ETS projects this will freeze the UI. Should be run in an isolate via `compute()`.

### 18. `hashCode`-based color for addresses is not deterministic across runs (`main.dart`)

```dart
final hash = src.hashCode & 0x7FFFFFFF;
```

`String.hashCode` in Dart is not guaranteed to be stable across runs or platforms. The same address could get different colors after restarting the app. Use a simple deterministic hash (e.g. FNV-1a on the code units) for stable coloring.

---

## Security

### 19. No validation of KNXnet/IP protocol version (`knx_types.dart`)

The `knxHeader` builder always uses protocol version `0x10` (byte 1), but incoming packets never verify bytes 0–1 are `0x06 0x10`. A malformed or spoofed packet could be processed as valid KNX data. This is low-risk on a local network but worth noting.

### 20. File path from `_showAbout` is unsanitized (`main.dart`)

```dart
final plistPath = '${File(Platform.resolvedExecutable).parent.parent.path}/Info.plist';
```

This constructs a file path from the executable location and reads it. If the executable path contained `..` segments, this could read unexpected files. Low-risk since it reads a plist, but path construction should use `Uri` or `path` package for robustness.

---

## Summary

| Category | Count |
|----------|-------|
| Bugs | 9 |
| Robustness | 5 |
| Design/Quality | 4 |
| Security | 2 |

The codebase is well-structured for its size, with clean separation of protocol handling, data models, and UI. The main areas to address are:

1. **Dark mode support** — hardcoded colors make the app unusable in dark mode (items 5–7)
2. **Protocol correctness** — DPT-3 decoding, sequence counter (items 2, 3)
3. **Connection robustness** — heartbeat errors, reconnection logic (items 10, 11)

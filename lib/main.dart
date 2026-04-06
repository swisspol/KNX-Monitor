import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_log.dart';
import 'knx_types.dart';
import 'ets_project.dart';
import 'knx_connection.dart';
import 'connect_dialog.dart';
import 'log_window.dart';
import 'send_panel.dart';
import 'source_filter_panel.dart';

void main() {
  initLogging();
  runApp(const MyApp());
}

final GlobalKey<_KnxMonitorPageState> _pageKey = GlobalKey();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'KNX Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.greenAccent,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.greenAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: KnxMonitorPage(key: _pageKey),
    );

    if (defaultTargetPlatform != TargetPlatform.macOS) return app;

    return PlatformMenuBar(
      menus: [
        PlatformMenu(label: 'KNX Monitor', menus: [
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: 'About KNX Monitor',
              onSelected: () => _pageKey.currentState?._showAbout(),
            ),
          ]),
          PlatformMenuItemGroup(members: [
            const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
            const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
          ]),
          PlatformMenuItemGroup(members: [
            const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ]),
        ]),
        PlatformMenu(label: 'Edit', menus: [
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: 'Copy',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
              onSelected: () => _pageKey.currentState?._copySelection(),
            ),
            PlatformMenuItem(
              label: 'Select All',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
              onSelected: () => _pageKey.currentState?._selectAll(),
            ),
          ]),
        ]),
        PlatformMenu(label: 'Window', menus: [
          PlatformMenuItemGroup(members: [
            const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
            const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
          ]),
          PlatformMenuItemGroup(members: [
            const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.toggleFullScreen),
          ]),
          PlatformMenuItemGroup(members: [
            const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.arrangeWindowsInFront),
          ]),
        ]),
      ],
      child: app,
    );
  }
}

class KnxMonitorPage extends StatefulWidget {
  const KnxMonitorPage({super.key});

  @override
  State<KnxMonitorPage> createState() => _KnxMonitorPageState();
}

/// Strip diacritics for search matching.
String _normalize(String s) {
  const diacritics =  'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÝýÿÑñÇç';
  const replacements = 'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuYyyNnCc';
  final buf = StringBuffer();
  for (final c in s.runes) {
    final ch = String.fromCharCode(c);
    final idx = diacritics.indexOf(ch);
    buf.write(idx >= 0 ? replacements[idx] : ch);
  }
  return buf.toString().toLowerCase();
}

class _KnxMonitorPageState extends State<KnxMonitorPage> {
  final KnxConnection _connection = KnxConnection();
  final List<KnxEvent> _events = [];
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedIndices = {};
  final Map<String, int> _sourceCounts = {};
  final Set<String> _checkedSources = {};
  int? _anchorIndex;

  KnxConnectionState _connState = KnxConnectionState.disconnected;
  bool _paused = false;
  bool _showSourcesPanel = false;
  int _messageNumber = 0;
  DateTime? _startTime;
  String _searchQuery = '';
  List<int>? _filteredIndices;

  static const int _maxEvents = 1000;

  // Fixed column widths
  static const double _colNum = 42;
  static const double _colTime = 82;
  static const double _colDelta = 72;
  static const double _colDir = 46;
  static const double _colSource = 60;
  static const double _colDest = 80;
  static const double _colApci = 72;
  static const double _colDpt = 56;
  static const double _colRaw = 88;
  static const double _colValue = 104;
  static const double _rowHeight = 28.0;
  static const double _headerHeight = 34.0;

  @override
  void initState() {
    super.initState();
    _connection.stateChanges.listen((s) {
      if (mounted) setState(() => _connState = s);
    });
    _connection.statusMessages.listen((_) {
      // Status text is derived from _connState, not from messages
    });
    _connection.events.listen((event) {
      if (_paused) return;
      if (mounted) {
        setState(() {
          _startTime ??= event.time;
          _messageNumber++;

          // Shift selection indices down since we insert at 0
          if (_selectedIndices.isNotEmpty) {
            final shifted = _selectedIndices.map((i) => i + 1).toSet();
            _selectedIndices.clear();
            _selectedIndices.addAll(shifted);
            if (_anchorIndex != null) _anchorIndex = _anchorIndex! + 1;
          }

          _events.insert(0, event);
          _sourceCounts[event.source] =
              (_sourceCounts[event.source] ?? 0) + 1;

          // Drop oldest events beyond limit
          if (_events.length > _maxEvents) {
            _events.removeRange(_maxEvents, _events.length);
            _selectedIndices.removeWhere((i) => i >= _maxEvents);
          }

          // Recompute filter
          if (_hasFilter) {
            _filteredIndices = _computeFiltered();
          }
        });
      }
    });
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  static const _prefLastHost = 'lastHost';
  static const _prefLastPort = 'lastPort';

  /// Shows connect dialog, connects, and re-shows on failure.
  Future<void> _showConnectDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final lastHost = prefs.getString(_prefLastHost) ?? '';
    final lastPort = prefs.getInt(_prefLastPort) ?? knxPort;

    final hostController = TextEditingController(text: lastHost);
    final portController = TextEditingController(
        text: lastPort == knxPort ? '' : lastPort.toString());

    try {
    while (true) {
      // Start discovery in background (not supported on iOS — no multicast entitlement)
      final bridges = <KnxBridge>[];
      var discovering = !Platform.isIOS;
      if (discovering) {
        _connection.discoverBridges().then((found) {
          bridges.addAll(found);
          discovering = false;
        }).catchError((_) {
          discovering = false;
        });
      }

      if (!mounted) return;

      final result = await showKnxConnectDialog(
        context: context,
        hostController: hostController,
        portController: portController,
        bridges: bridges,
        isDiscovering: () => discovering,
      );

      if (result == null) {
        hostController.dispose();
        portController.dispose();
        return; // User cancelled
      }

      final (host, port) = result;

      setState(() {
        _paused = false;
        _events.clear();
        _messageNumber = 0;
        _startTime = null;
        _selectedIndices.clear();
        _searchController.clear();
        _searchQuery = '';
        _filteredIndices = null;
        _sourceCounts.clear();
        _checkedSources.clear();
      });
      _connection.connect(host, port: port);

      // Wait for connection result — use a manual subscription
      // so we can cleanly cancel it
      final connected = Completer<bool>();
      final sub = _connection.stateChanges.listen((state) {
        if (connected.isCompleted) return;
        if (state == KnxConnectionState.connected) {
          connected.complete(true);
        } else if (state == KnxConnectionState.error ||
            state == KnxConnectionState.disconnected) {
          connected.complete(false);
        }
      });

      final success = await connected.future;
      await sub.cancel();

      if (success) {
        await prefs.setString(_prefLastHost, host);
        if (port == knxPort) {
          await prefs.remove(_prefLastPort);
        } else {
          await prefs.setInt(_prefLastPort, port);
        }
        // Don't dispose controllers immediately — let the dialog animation finish
        Future.delayed(const Duration(milliseconds: 500), () {
          hostController.dispose();
          portController.dispose();
        });
        return;
      }

      // Connection failed — loop back to show dialog again
      if (!mounted) {
        hostController.dispose();
        portController.dispose();
        return;
      }
    }
    } catch (_) {
      // Safety net
    }
  }

  static const _gitSha = String.fromEnvironment('GIT_SHA');

  Future<void> _showAbout() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    // Read NSHumanReadableCopyright from Info.plist via the bundle
    String copyright = '';
    try {
      final plistPath = '${File(Platform.resolvedExecutable).parent.parent.path}/Info.plist';
      final plist = await File(plistPath).readAsString();
      final match = RegExp(r'<key>NSHumanReadableCopyright</key>\s*<string>(.*?)</string>')
          .firstMatch(plist);
      if (match != null) copyright = match.group(1)!;
    } catch (_) {}
    if (!mounted) return;
    final version = _gitSha.isNotEmpty
        ? '${info.version} (${info.buildNumber}) · ${_gitSha.substring(0, 7)}'
        : '${info.version} (${info.buildNumber})';
    showAboutDialog(
      context: context,
      applicationName: info.appName,
      applicationVersion: version,
      applicationLegalese: copyright,
      applicationIcon: Image.asset(
        'assets/app_icon.png',
        width: 64,
        height: 64,
      ),
    );
  }

  Future<void> _startup() async {
    _showConnectDialog();
  }

  Future<bool> _loadProjectFile(String path) async {
    try {
      log.info('Loading project: $path');
      final file = File(path);
      final bytes = await file.readAsBytes();
      log.info('Read ${bytes.length} bytes');
      final project = EtsProject.loadFromBytes(bytes);
      _connection.project = project;
      log.info('Project: ${project.devices.length} devices, '
          '${project.groupAddresses.length} GAs');
      // Retranslate existing events with new project data
      setState(() {
        for (final e in _events) {
          e.deviceName = project.lookupDevice(e.source);
          e.groupName = project.lookupGA(e.destination);
        }
        if (_hasFilter) {
          _filteredIndices = _computeFiltered();
        }
      });
      return true;
    } catch (e, st) {
      log.severe('Project load: $e', e, st);
      return false;
    }
  }

  void _openLogWindow() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const SizedBox(
          width: 900,
          height: 500,
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            child: LogWindow(),
          ),
        ),
      ),
    );
  }

  static const _prefLastProjectDir = 'lastProjectDir';

  Future<void> _pickProject() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastDir = prefs.getString(_prefLastProjectDir);
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['knxproj'],
        dialogTitle: 'Open ETS Project\u2026',
        initialDirectory: lastDir,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final success = await _loadProjectFile(path);
        if (success) {
          await prefs.setString(_prefLastProjectDir, File(path).parent.path);
        } else {
          await prefs.remove(_prefLastProjectDir);
        }
      }
    } catch (e) {
      log.severe('Project pick: $e');
    }
  }

  @override
  void dispose() {
    _connection.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _recomputeFilter();
      _selectedIndices.clear();
    });
  }

  bool get _hasFilter =>
      _searchQuery.isNotEmpty || _checkedSources.isNotEmpty;

  void _recomputeFilter() {
    _filteredIndices = _hasFilter ? _computeFiltered() : null;
  }

  List<int> _computeFiltered() {
    final words = _searchQuery.isNotEmpty
        ? _normalize(_searchQuery)
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList()
        : <String>[];
    final result = <int>[];
    for (var i = 0; i < _events.length; i++) {
      final e = _events[i];
      // Source filter: if any sources are checked, only show those
      if (_checkedSources.isNotEmpty && !_checkedSources.contains(e.source)) {
        continue;
      }
      // Search filter
      if (words.isNotEmpty && !_eventMatchesAll(e, words)) continue;
      result.add(i);
    }
    return result;
  }

  /// Returns true if all [words] appear in order within at least one searchable field.
  /// Matching is full-word only (whitespace-separated tokens).
  bool _eventMatchesAll(KnxEvent e, List<String> words) {
    final fields = [
      e.source,
      e.deviceName,
      e.destination,
      e.groupName,
      e.dpt,
      e.value,
    ];
    for (final field in fields) {
      final fieldWords = _normalize(field).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (_matchWordsInOrder(fieldWords, words)) return true;
    }
    return false;
  }

  /// Check if all search [words] match full words in [fieldWords] in order.
  /// Each search word must be equal to a field word, scanning left to right.
  bool _matchWordsInOrder(List<String> fieldWords, List<String> searchWords) {
    var fi = 0;
    for (final sw in searchWords) {
      var found = false;
      while (fi < fieldWords.length) {
        if (fieldWords[fi] == sw) {
          fi++;
          found = true;
          break;
        }
        fi++;
      }
      if (!found) return false;
    }
    return true;
  }

  // --- Selection ---

  void _onRowTap(int index) {
    setState(() {
      // Support both Cmd and Ctrl for toggle (Ctrl+Click on macOS = right-click,
      // but some users expect it to work like Cmd+Click)
      final isToggle = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      final isShift = HardwareKeyboard.instance.isShiftPressed;

      if (isToggle) {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
        } else {
          _selectedIndices.add(index);
        }
        _anchorIndex = index;
      } else if (isShift && _anchorIndex != null) {
        final lo = min(_anchorIndex!, index);
        final hi = max(_anchorIndex!, index);
        _selectedIndices.clear();
        for (var i = lo; i <= hi; i++) {
          _selectedIndices.add(i);
        }
      } else {
        _selectedIndices.clear();
        _selectedIndices.add(index);
        _anchorIndex = index;
      }
    });
    _focusNode.requestFocus();
  }

  void _copySelection() {
    if (_selectedIndices.isEmpty) return;
    final sorted = _selectedIndices.toList()..sort();
    final list = sorted.map((i) {
      final e = _events[i];
      final msgNum = _messageNumber - i;
      return {
        '#': msgNum,
        'time': _fmtRelative(e.time),
        'delta': _fmtDelta(i),
        'dir': e.direction,
        'source': e.source,
        'device': e.deviceName,
        'dest': e.destination,
        'groupAddress': e.groupName,
        'apci': e.apci,
        'dpt': e.dpt,
        'raw': e.raw,
        'value': e.value,
      };
    }).toList();
    final encoder = JsonEncoder.withIndent('  ');
    Clipboard.setData(ClipboardData(text: encoder.convert(list)));
  }

  void _selectAll() {
    setState(() {
      _selectedIndices.clear();
      for (var i = 0; i < _events.length; i++) {
        _selectedIndices.add(i);
      }
    });
  }

  // --- Time formatting ---

  String _fmtRelative(DateTime t) {
    if (_startTime == null) return '--';
    final d = t.difference(_startTime!);
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    final ms = d.inMilliseconds % 1000;
    if (d.inHours > 0) {
      return '${d.inHours}:${mins.remainder(60).toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  String _fmtDelta(int index) {
    if (index >= _events.length - 1) {
      // First (oldest) message — delta is 0
      return '+${(0.0).toStringAsFixed(3)}';
    }
    final cur = _events[index].time;
    final prev = _events[index + 1].time;
    final d = cur.difference(prev);
    final secs = d.inMilliseconds / 1000.0;
    return '+${secs.toStringAsFixed(3)}';
  }

  // --- Read/Response pair detection ---

  /// Returns true if the event at [index] is part of a Read/Response pair
  /// where both events are currently visible (not filtered out).
  bool _isReadResponsePair(int index) {
    final e = _events[index];
    final visible = _filteredIndices;

    if (e.apci == 'Response') {
      for (var i = index + 1; i < _events.length && i <= index + 10; i++) {
        final other = _events[i];
        if (other.destination == e.destination && other.apci == 'Read' &&
            e.time.difference(other.time).inMilliseconds.abs() < 2000) {
          return visible == null || visible.contains(i);
        }
        if (e.time.difference(other.time).inMilliseconds > 2000) break;
      }
    } else if (e.apci == 'Read') {
      for (var i = index - 1; i >= 0 && i >= index - 10; i--) {
        final other = _events[i];
        if (other.destination == e.destination && other.apci == 'Response' &&
            other.time.difference(e.time).inMilliseconds.abs() < 2000) {
          return visible == null || visible.contains(i);
        }
        if (other.time.difference(e.time).inMilliseconds > 2000) break;
      }
    }
    return false;
  }

  // --- Colors ---

  static const _cRed = Color(0xFFC62828);
  static const _cGreen = Color(0xFF2E7D32);
  static const _cBlue = Color(0xFF1565C0);
  static const _cGrey = Color(0xFF757575);
  static const _cText = Color(0xFF2C2C2C);
  static const _cTextDim = Color(0xFF757575);

  Color _apciColor(String apci) {
    switch (apci) {
      case 'Read':
        return _cRed;
      case 'Write':
        return _cGreen;
      case 'Response':
        return _cBlue;
      default:
        return _cGrey;
    }
  }

  Color _dirColor(String dir) {
    switch (dir) {
      case 'IND':
        return _cGreen;
      case 'CON':
        return _cBlue;
      case 'REQ':
        return _cRed;
      default:
        return _cGrey;
    }
  }


  /// Semantic color for DPT based on its major number.
  static const _dptColors = <int, Color>{
    1:   Color(0xFFC62828), // Boolean / switch — red
    2:   Color(0xFFC62828), // Switch control — red
    3:   Color(0xFFE65100), // Dimming control — amber
    4:   Color(0xFF6D4C41), // Character — brown
    5:   Color(0xFF00796B), // Percentage / unsigned — teal
    6:   Color(0xFF00796B), // Percentage / signed — teal
    7:   Color(0xFF37474F), // Counter / time (16-bit) — slate
    8:   Color(0xFF37474F), // Counter / time signed — slate
    9:   Color(0xFF1565C0), // Sensor float (temp, lux) — blue
    10:  Color(0xFF6A1B9A), // Time of day — purple
    11:  Color(0xFF6A1B9A), // Date — purple
    12:  Color(0xFF2E7D32), // 32-bit counter — green
    13:  Color(0xFF2E7D32), // Energy (Wh, kWh) — green
    14:  Color(0xFFEF6C00), // Electrical (V, A, W) — orange
    15:  Color(0xFF546E7A), // Access data — gray
    16:  Color(0xFF6D4C41), // String — brown
    17:  Color(0xFFAD1457), // Scene number — magenta
    18:  Color(0xFFAD1457), // Scene control — magenta
    19:  Color(0xFF6A1B9A), // Date & time — purple
    20:  Color(0xFF283593), // HVAC mode — indigo
    232: Color(0xFFD81B60), // RGB color — pink
  };

  Color _dptColor(String dpt) {
    if (dpt.isEmpty) return _cGrey;
    final major = int.tryParse(dpt.split('.').first) ?? 0;
    return _dptColors[major] ?? _cGrey;
  }

  /// Deterministic color from source physical address.
  /// Same address always gets the same hue for visual grouping.
  Color _addrColor(String src) {
    final hash = src.hashCode & 0x7FFFFFFF;
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.6, 0.45).toColor();
  }

  // --- Status icon ---

  String get _statusLabel {
    switch (_connState) {
      case KnxConnectionState.connected:
        return 'Connected';
      case KnxConnectionState.connecting:
        return 'Connecting\u2026';
      case KnxConnectionState.error:
        return 'Connection Failure';
      case KnxConnectionState.disconnected:
        return 'Disconnected';
    }
  }

  Widget _statusIcon() {
    switch (_connState) {
      case KnxConnectionState.connected:
        return Icon(Icons.circle, size: 10, color: Colors.green.shade400);
      case KnxConnectionState.connecting:
        return Icon(Icons.circle, size: 10, color: Colors.orange.shade400);
      case KnxConnectionState.error:
        return Icon(Icons.circle, size: 10, color: Colors.red.shade400);
      case KnxConnectionState.disconnected:
        return Icon(Icons.circle, size: 10, color: Colors.red.shade400);
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(42),
        child: AppBar(
          toolbarHeight: 42,
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          titleSpacing: 12,
          title: Row(
            children: [
              GestureDetector(
                onTap: _showAbout,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.device_hub, size: 18),
                      SizedBox(width: 8),
                      Text('KNX Monitor',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _statusIcon(),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_statusLabel,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
                    overflow: TextOverflow.ellipsis),
              ),
              const Spacer(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 550),
                child: SizedBox(
                height: 28,
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TextStyle(fontSize: 12, color: cs.onPrimary),
                cursorColor: cs.onPrimary,
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(fontSize: 12, color: cs.onPrimary.withAlpha(120)),
                  prefixIcon: Icon(Icons.search, size: 16, color: cs.onPrimary.withAlpha(150)),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                          child: Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.onPrimary.withAlpha(60),
                            ),
                            child: Icon(Icons.close, size: 12, color: cs.onPrimary),
                          ),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(minWidth: 28),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  filled: true,
                  fillColor: cs.onPrimary.withAlpha(30),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            ),
              const Spacer(),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                _showSourcesPanel ? Icons.filter_list_off : Icons.filter_list,
                size: 18,
              ),
              tooltip: _showSourcesPanel ? 'Hide Source Filter' : 'Show Source Filter',
              onPressed: () => setState(() {
                _showSourcesPanel = !_showSourcesPanel;
                if (!_showSourcesPanel) {
                  _checkedSources.clear();
                  _recomputeFilter();
                }
              }),
              visualDensity: VisualDensity.compact,
            ),
            SizedBox(
              height: 24,
              child: VerticalDivider(
                width: 16,
                thickness: 1,
                color: cs.onPrimary.withAlpha(60),
              ),
            ),
            IconButton(
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause, size: 18),
              tooltip: _paused ? 'Resume' : 'Pause',
              onPressed: _connState == KnxConnectionState.connected
                  ? () => setState(() => _paused = !_paused)
                  : null,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep, size: 18),
              tooltip: 'Clear',
              onPressed: _events.isEmpty ? null : () => setState(() {
                _events.clear();
                _messageNumber = 0;
                _startTime = null;
                _selectedIndices.clear();
                _searchController.clear();
                _searchQuery = '';
                _filteredIndices = null;
                _sourceCounts.clear();
                _checkedSources.clear();
              }),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(
                  _connState == KnxConnectionState.connected
                      ? Icons.link_off
                      : Icons.link,
                  size: 18),
              tooltip: _connState == KnxConnectionState.connected
                  ? 'Disconnect'
                  : 'Connect\u2026',
              onPressed: _connState == KnxConnectionState.connecting
                  ? null
                  : () {
                      if (_connState == KnxConnectionState.connected) {
                        _connection.disconnect();
                      }
                      _showConnectDialog();
                    },
              visualDensity: VisualDensity.compact,
            ),
            SizedBox(
              height: 24,
              child: VerticalDivider(
                width: 16,
                thickness: 1,
                color: cs.onPrimary.withAlpha(60),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.folder_open, size: 18),
              tooltip: 'Load ETS Project\u2026',
              onPressed: _pickProject,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.article_outlined, size: 18),
              tooltip: 'Log',
              onPressed: _openLogWindow,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (_showSourcesPanel) ...[
                    SourceFilterPanel(
                      sourceCounts: _sourceCounts,
                      checkedSources: _checkedSources,
                      project: _connection.project,
                      headerHeight: _headerHeight,
                      width: _sourcesPanelWidth,
                      onFilterChanged: () => setState(() => _recomputeFilter()),
                    ),
                    Container(width: 1, color: cs.outlineVariant.withAlpha(80)),
                  ],
                  Expanded(
                    child: Column(
                      children: [
                        _buildHeader(cs),
                        Container(height: 1, color: cs.outlineVariant.withAlpha(80)),
                        Expanded(
                          child: () {
                            final indices = _filteredIndices;
                            final count = indices?.length ?? _events.length;
                            if (_events.isEmpty || count == 0) {
                              return Center(
                                child: Text(
                                  _events.isEmpty
                                      ? (_connState == KnxConnectionState.connected
                                          ? 'Waiting for messages\u2026'
                                          : 'No KNX/IP Bridge Connected')
                                      : 'No matching events',
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant, fontSize: 13),
                                ),
                              );
                            }
                            return ListView.builder(
                              controller: _scrollController,
                              itemCount: count,
                              itemExtent: _rowHeight,
                              itemBuilder: (context, i) {
                                final eventIndex = indices?[i] ?? i;
                                return _buildRow(eventIndex, cs);
                              },
                            );
                          }(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!Platform.isIOS) ...[
              Container(height: 1, color: cs.outlineVariant.withAlpha(80)),
              SendPanel(
                connection: _connection,
                connectionState: _connState,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const double _sourcesPanelWidth = 250;

  Widget _buildHeader(ColorScheme cs) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: cs.onSurfaceVariant,
      letterSpacing: 0.3,
    );
    return Container(
      height: _headerHeight,
      color: cs.surfaceContainerHighest.withAlpha(120),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _fixedCell('#', _colNum, style, Alignment.centerRight),
          _fixedCell('Time', _colTime, style),
          _fixedCell('\u0394t', _colDelta, style, Alignment.centerRight),
          _fixedCell('Dir', _colDir, style),
          _fixedCell('Source', _colSource, style),
          Expanded(flex: 38, child: _padText('Device', style)),
          _fixedCell('Destination', _colDest, style),
          Expanded(flex: 62, child: _padText('Group Address', style)),
          _fixedCell('APCI', _colApci, style),
          _fixedCell('DPT', _colDpt, style),
          _fixedCell('Raw', _colRaw, style, Alignment.centerRight),
          _fixedCell('Value', _colValue, style),
        ],
      ),
    );
  }

  Widget _fixedCell(String label, double w, TextStyle s,
      [Alignment align = Alignment.centerLeft]) {
    return SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(alignment: align, child: Text(label, style: s)),
      ),
    );
  }

  Widget _padText(String label, TextStyle s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label, style: s, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildRow(int index, ColorScheme cs) {
    final e = _events[index];
    final msgNum = _messageNumber - index;
    final selected = _selectedIndices.contains(index);

    Color bg;
    if (selected) {
      bg = cs.primary.withAlpha(40);
    } else if (_isReadResponsePair(index)) {
      bg = const Color(0xFFC8E6C9); // light green
    } else if (index.isEven) {
      bg = Colors.transparent;
    } else {
      bg = cs.surfaceContainerHighest.withAlpha(100);
    }

    const ts = TextStyle(
        fontSize: 11, fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Courier']);

    return GestureDetector(
      onTap: Platform.isIOS ? null : () => _onRowTap(index),
      child: Container(
        height: _rowHeight,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _dCell('$msgNum', _colNum, ts.copyWith(color: cs.onSurfaceVariant),
                Alignment.centerRight),
            _dCell(_fmtRelative(e.time), _colTime,
                ts.copyWith(color: cs.onSurfaceVariant)),
            _dCell(_fmtDelta(index), _colDelta,
                ts.copyWith(color: _cTextDim, fontSize: 10),
                Alignment.centerRight),
            _bubbleCell(e.direction, _colDir, _dirColor(e.direction), ts),
            _addrCell(e.source, _colSource, ts),
            Expanded(
              flex: 38,
              child: _padData(e.deviceName, ts.copyWith(color: _cText)),
            ),
            _addrCell(e.destination, _colDest, ts),
            Expanded(
              flex: 62,
              child: _padData(e.groupName, ts.copyWith(color: _cText)),
            ),
            _bubbleCell(e.apci, _colApci, _apciColor(e.apci), ts),
            _dptCell(e.dpt, ts),
            _dCell(e.raw, _colRaw,
                ts.copyWith(color: _cTextDim),
                Alignment.centerRight),
            _dCell(e.value, _colValue, ts.copyWith(color: _cText)),
          ],
        ),
      ),
    );
  }

  Widget _dCell(String text, double w, TextStyle s,
      [Alignment align = Alignment.centerLeft]) {
    return SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(
          alignment: align,
          child: Text(text, style: s, overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
      ),
    );
  }

  Widget _addrCell(String addr, double w, TextStyle ts) {
    return _bubbleCell(addr, w, _addrColor(addr), ts);
  }

  Widget _bubbleCell(String text, double w, Color color, TextStyle ts) {
    if (text.isEmpty) return SizedBox(width: w);
    return SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha(35),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(text,
                style: ts.copyWith(color: color, fontSize: 10),
                overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }

  Widget _dptCell(String dpt, TextStyle ts) {
    return _bubbleCell(dpt, _colDpt, _dptColor(dpt), ts);
  }

  Widget _padData(String text, TextStyle s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: s, overflow: TextOverflow.ellipsis, maxLines: 1),
      ),
    );
  }
}

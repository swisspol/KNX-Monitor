import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'app_log.dart';

class LogWindow extends StatefulWidget {
  const LogWindow({super.key});

  @override
  State<LogWindow> createState() => _LogWindowState();
}

class _LogWindowState extends State<LogWindow> {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _selectedIndices = {};
  final FocusNode _focusNode = FocusNode();
  final List<LogRecord> _records = [];
  int? _anchorIndex;
  bool _autoScroll = true;
  late StreamSubscription _sub;

  @override
  void initState() {
    super.initState();
    _records.addAll(logHistory);
    _sub = Logger.root.onRecord.listen((record) {
      if (mounted) {
        setState(() => _records.add(record));
        if (_autoScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController
                  .jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onRowTap(int index) {
    setState(() {
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
    final lines = sorted
        .where((i) => i < _records.length)
        .map((i) {
      final r = _records[i];
      return '${_fmtTime(r.time)}  ${_levelLabel(r.level).padRight(7)}  ${r.message}';
    }).join('\n');
    Clipboard.setData(ClipboardData(text: lines));
  }

  void _selectAll() {
    setState(() {
      _selectedIndices.clear();
      for (var i = 0; i < _records.length; i++) {
        _selectedIndices.add(i);
      }
    });
  }

  String _fmtTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }

  String _levelLabel(Level level) {
    if (level >= Level.SEVERE) return 'ERROR';
    if (level >= Level.WARNING) return 'WARN';
    return 'INFO';
  }

  Color _levelColor(Level level) {
    if (level >= Level.SEVERE) return const Color(0xFFC62828);
    if (level >= Level.WARNING) return const Color(0xFFEF6C00);
    return const Color(0xFF2E7D32);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Application Log', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        toolbarHeight: 36,
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copySelection,
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copySelection,
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _selectAll,
          const SingleActivator(LogicalKeyboardKey.keyA, control: true): _selectAll,
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is UserScrollNotification) {
                final atBottom = _scrollController.position.pixels >=
                    _scrollController.position.maxScrollExtent - 30;
                if (_autoScroll != atBottom) {
                  setState(() => _autoScroll = atBottom);
                }
              }
              return false;
            },
            child: _records.isEmpty
                ? Center(
                    child: Text('No Log Entries',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _records.length,
                    itemExtent: 24,
                    itemBuilder: (context, index) {
                      final r = _records[index];
                      final selected = _selectedIndices.contains(index);
                      Color bg;
                      if (selected) {
                        bg = cs.primary.withAlpha(40);
                      } else if (r.level >= Level.SEVERE) {
                        bg = const Color(0xFFFFCDD2); // light red
                      } else if (r.level >= Level.WARNING) {
                        bg = const Color(0xFFFFF3E0); // light orange
                      } else if (index.isEven) {
                        bg = Colors.transparent;
                      } else {
                        bg = cs.surfaceContainerHighest.withAlpha(50);
                      }
                      final levelCol = _levelColor(r.level);

                      return GestureDetector(
                        onTap: Platform.isIOS ? null : () => _onRowTap(index),
                        child: Container(
                          height: 24,
                          color: bg,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: Text(
                                  _fmtTime(r.time),
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 64,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: levelCol.withAlpha(35),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _levelLabel(r.level),
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: levelCol,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  r.message,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

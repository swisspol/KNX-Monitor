import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'knx_types.dart';

class _RangeFormatter extends TextInputFormatter {
  final int max;
  _RangeFormatter(this.max);
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final v = int.tryParse(newValue.text);
    if (v == null || v > max) return oldValue;
    return newValue;
  }
}

/// Shows the KNX bridge connect dialog.
///
/// Returns a `(host, port)` tuple if the user confirms, or `null` if cancelled.
/// [bridges] and [discovering] are updated externally by the caller while
/// discovery runs in the background.
Future<(String, int)?> showKnxConnectDialog({
  required BuildContext context,
  required TextEditingController hostController,
  required TextEditingController portController,
  required List<KnxBridge> bridges,
  required bool Function() isDiscovering,
}) async {
  final cs = Theme.of(context).colorScheme;

  void doConnect(BuildContext ctx) {
    final host = hostController.text.trim();
    if (host.isEmpty) return;
    final port = int.tryParse(portController.text.trim()) ?? knxPort;
    Navigator.of(ctx).pop((host, port));
  }

  VoidCallback? hostListener;

  final result = await showDialog<(String, int)?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Set up host field listener once
          if (hostListener == null) {
            hostListener = () {
              try {
                if (ctx.mounted) setDialogState(() {});
              } catch (_) {}
            };
            hostController.addListener(hostListener!);
          }

          final discovering = isDiscovering();
          if (discovering) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (ctx.mounted) setDialogState(() {});
            });
          }

          String discoveryLabel;
          if (discovering) {
            discoveryLabel = 'Searching for bridges\u2026';
          } else if (bridges.isEmpty) {
            discoveryLabel = 'No bridges discovered';
          } else {
            discoveryLabel = 'Bridges Discovered:';
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.router, color: cs.onPrimary, size: 20),
                        const SizedBox(width: 10),
                        Text('Connect to KNX/IP Bridge',
                          style: TextStyle(color: cs.onPrimary, fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: hostController,
                            decoration: const InputDecoration(
                              labelText: 'Host / IP Address',
                              hintText: '192.168.1.100',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            onTap: () => hostController.selection = TextSelection(
                                baseOffset: 0, extentOffset: hostController.text.length),
                            onSubmitted: (_) => doConnect(ctx),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: portController,
                            decoration: InputDecoration(
                              labelText: 'Port',
                              hintText: '$knxPort',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              _RangeFormatter(65535),
                            ],
                            onTap: () => portController.selection = TextSelection(
                                baseOffset: 0, extentOffset: portController.text.length),
                            onSubmitted: (_) => doConnect(ctx),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!Platform.isIOS) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Row(
                      children: [
                        Text(discoveryLabel,
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500)),
                        if (discovering) ...[
                          const SizedBox(width: 8),
                          const SizedBox(width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ],
                    ),
                  ),
                  if (!discovering && bridges.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final b in bridges)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                hoverColor: cs.primary.withAlpha(30),
                                splashColor: cs.primary.withAlpha(50),
                                highlightColor: cs.primary.withAlpha(40),
                                onTap: () {
                                  Navigator.of(ctx).pop((b.ip, knxPort));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF9E9E9E),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(b.ip,
                                            style: const TextStyle(
                                              fontFamily: 'monospace', fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(b.name,
                                            style: const TextStyle(fontSize: 13,
                                                color: Color(0xFF2C2C2C)),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(null),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: hostController.text.trim().isEmpty
                              ? null
                              : () => doConnect(ctx),
                          child: const Text('Connect'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  if (hostListener != null) {
    hostController.removeListener(hostListener!);
  }

  return result;
}

import 'package:flutter/material.dart';
import 'ets_project.dart';

/// Deterministic color from a physical address string.
Color _addrColor(String src) {
  final hash = src.hashCode & 0x7FFFFFFF;
  final hue = (hash % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.6, 0.45).toColor();
}

int _comparePhysAddr(String a, String b) {
  final ap = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final bp = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final ai = i < ap.length ? ap[i] : 0;
    final bi = i < bp.length ? bp[i] : 0;
    if (ai != bi) return ai.compareTo(bi);
  }
  return 0;
}

class SourceFilterPanel extends StatelessWidget {
  final Map<String, int> sourceCounts;
  final Set<String> checkedSources;
  final EtsProject? project;
  final double headerHeight;
  final double width;
  final VoidCallback onFilterChanged;

  const SourceFilterPanel({
    super.key,
    required this.sourceCounts,
    required this.checkedSources,
    required this.project,
    required this.headerHeight,
    required this.width,
    required this.onFilterChanged,
  });

  static const _cTextDim = Color(0xFF757575);

  void _toggleSource(String src) {
    if (checkedSources.contains(src)) {
      checkedSources.remove(src);
    } else {
      checkedSources.add(src);
    }
    onFilterChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Sort: checked first, then by count descending, then by address ascending
    final sources = sourceCounts.keys.toList()
      ..sort((a, b) {
        final ac = checkedSources.contains(a);
        final bc = checkedSources.contains(b);
        if (ac != bc) return ac ? -1 : 1;
        final countCmp = (sourceCounts[b] ?? 0).compareTo(sourceCounts[a] ?? 0);
        if (countCmp != 0) return countCmp;
        return _comparePhysAddr(a, b);
      });

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: headerHeight,
            color: cs.surfaceContainerHighest.withAlpha(120),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Source Filter',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  )),
            ),
          ),
          Container(height: 1, color: cs.outlineVariant.withAlpha(80)),
          Expanded(
            child: sources.isEmpty
                ? Center(
                    child: Text('No Sources',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12)),
                  )
                : ListView.builder(
                    itemCount: sources.length,
                    itemExtent: 48,
                    itemBuilder: (context, i) {
                      final src = sources[i];
                      final count = sourceCounts[src] ?? 0;
                      final checked = checkedSources.contains(src);
                      final deviceName =
                          project?.lookupDevice(src) ?? '';
                      return Material(
                        color: checked
                            ? cs.primary.withAlpha(20)
                            : Colors.transparent,
                        child: InkWell(
                          onTap: () => _toggleSource(src),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 5,
                                                      vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: _addrColor(src)
                                                        .withAlpha(35),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(src,
                                                      style: TextStyle(
                                                        fontFamily: 'monospace',
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            _addrColor(src),
                                                      )),
                                                ),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: cs.surfaceContainerHighest,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text('$count',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color:
                                                        cs.onSurfaceVariant)),
                                          ),
                                        ],
                                      ),
                                      if (deviceName.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(deviceName,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: _cTextDim),
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: checked,
                                    onChanged: (_) => _toggleSource(src),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

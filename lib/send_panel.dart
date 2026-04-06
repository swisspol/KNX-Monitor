import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'knx_connection.dart';

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

class SendPanel extends StatefulWidget {
  final KnxConnection connection;
  final KnxConnectionState connectionState;

  const SendPanel({
    super.key,
    required this.connection,
    required this.connectionState,
  });

  @override
  State<SendPanel> createState() => _SendPanelState();
}

class _SendPanelState extends State<SendPanel> {
  final _gaMainCtrl = TextEditingController(text: '0');
  final _gaMiddleCtrl = TextEditingController(text: '0');
  final _gaSubCtrl = TextEditingController(text: '0');
  final _valueCtrl = TextEditingController();
  String _sendMode = 'Read';
  String _sendDptType = _sendDptTypes.first;

  static const _cTextDim = Color(0xFF757575);

  static const _sendDptTypes = [
    '1.x \u2014 Boolean (0-1)',
    '2.x \u2014 Control (0-3)',
    '3.x \u2014 Dim Control (0-15)',
    '5.001 \u2014 Percentage (0-100%)',
    '5.003 \u2014 Angle (0-360\u00b0)',
    '5.x \u2014 Unsigned 8-bit (0-255)',
    '6.x \u2014 Signed 8-bit (-128..127)',
    '7.x \u2014 Unsigned 16-bit (0-65535)',
    '8.x \u2014 Signed 16-bit (-32768..32767)',
    '9.x \u2014 Float 16-bit',
    '12.x \u2014 Unsigned 32-bit',
    '13.x \u2014 Signed 32-bit',
    '14.x \u2014 Float 32-bit',
    '17.x \u2014 Scene Number (0-63)',
    '18.x \u2014 Scene Control (0-255)',
    '20.x \u2014 HVAC Mode (0-255)',
  ];

  @override
  void dispose() {
    _gaMainCtrl.dispose();
    _gaMiddleCtrl.dispose();
    _gaSubCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  void _doSend() {
    final main = int.tryParse(_gaMainCtrl.text);
    final middle = int.tryParse(_gaMiddleCtrl.text);
    final sub = int.tryParse(_gaSubCtrl.text);
    if (main == null || middle == null || sub == null) return;

    if (_sendMode == 'Read') {
      widget.connection.sendGroupTelegram(main, middle, sub, [0x00, 0x00]);
      return;
    }

    // Write mode — encode value based on DPT type
    final valText = _valueCtrl.text.trim();
    if (valText.isEmpty) return;

    List<int>? apdu;
    final dptKey = _sendDptType.split(' ').first;
    switch (dptKey) {
      case '1.x':
        final v = int.tryParse(valText);
        if (v == null || v < 0 || v > 1) return;
        apdu = [0x00, 0x80 | (v & 0x3F)];
      case '2.x':
        final v = int.tryParse(valText);
        if (v == null || v < 0 || v > 3) return;
        apdu = [0x00, 0x80 | (v & 0x3F)];
      case '3.x':
        final v = int.tryParse(valText);
        if (v == null || v < 0 || v > 15) return;
        apdu = [0x00, 0x80 | (v & 0x3F)];
      case '4.x':
        if (valText.isEmpty) return;
        apdu = [0x00, 0x80, valText.codeUnitAt(0) & 0xFF];
      case '5.001':
        final v = double.tryParse(valText);
        if (v == null || v < 0 || v > 100) return;
        apdu = [0x00, 0x80, (v / 100.0 * 255).round().clamp(0, 255)];
      case '5.003':
        final v = double.tryParse(valText);
        if (v == null || v < 0 || v > 360) return;
        apdu = [0x00, 0x80, (v / 360.0 * 255).round().clamp(0, 255)];
      case '5.x':
        final v = int.tryParse(valText);
        if (v == null || v < 0 || v > 255) return;
        apdu = [0x00, 0x80, v & 0xFF];
      case '6.x':
        final v = int.tryParse(valText);
        if (v == null || v < -128 || v > 127) return;
        apdu = [0x00, 0x80, v & 0xFF];
      case '7.x':
        final v = int.tryParse(valText);
        if (v == null || v < 0 || v > 65535) return;
        apdu = [0x00, 0x80, (v >> 8) & 0xFF, v & 0xFF];
      case '8.x':
        final v = int.tryParse(valText);
        if (v == null || v < -32768 || v > 32767) return;
        apdu = [0x00, 0x80, (v >> 8) & 0xFF, v & 0xFF];
      case '9.x':
        final v = double.tryParse(valText);
        if (v == null) return;
        final encoded = _encodeKnxFloat16(v);
        apdu = [0x00, 0x80, (encoded >> 8) & 0xFF, encoded & 0xFF];
      case '10.x':
        final v = int.tryParse(valText);
        if (v == null || v < 0) return;
        apdu = [0x00, 0x80, 0x00, (v ~/ 60) & 0xFF, v % 60];
      case '11.x':
        final v = int.tryParse(valText);
        if (v == null || v < 1 || v > 31) return;
        apdu = [0x00, 0x80, v & 0xFF, 0x01, 0x00];
      case '12.x':
        final v = int.tryParse(valText);
        if (v == null || v < 0) return;
        apdu = [0x00, 0x80,
          (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
      case '13.x':
        final v = int.tryParse(valText);
        if (v == null) return;
        apdu = [0x00, 0x80,
          (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
      case '14.x':
        final v = double.tryParse(valText);
        if (v == null) return;
        final bd = ByteData(4)..setFloat32(0, v, Endian.big);
        apdu = [0x00, 0x80, bd.getUint8(0), bd.getUint8(1), bd.getUint8(2), bd.getUint8(3)];
      case '17.x':
        final v = int.tryParse(valText);
        if (v == null || v < 0 || v > 63) return;
        apdu = [0x00, 0x80, v & 0x3F];
      case '18.x':
        final v = int.tryParse(valText);
        if (v == null || v < 0 || v > 127) return;
        apdu = [0x00, 0x80, v & 0xFF];
      case '20.x':
        final v = int.tryParse(valText);
        if (v == null || v < 0 || v > 255) return;
        apdu = [0x00, 0x80, v & 0xFF];
    }
    if (apdu != null) {
      widget.connection.sendGroupTelegram(main, middle, sub, apdu);
    }
  }

  int _encodeKnxFloat16(double value) {
    // KNX 16-bit float: sign(1) + exponent(4) + mantissa(11)
    // value = 0.01 * mantissa * 2^exponent
    int sign = 0;
    if (value < 0) {
      sign = 1;
      value = -value;
    }
    int exp = 0;
    var mant = (value * 100).round();
    while (mant > 2047 && exp < 15) {
      mant = (mant / 2).round();
      exp++;
    }
    if (sign == 1) mant = 2048 - mant;
    return ((sign & 1) << 15) | ((exp & 0x0F) << 11) | (mant & 0x07FF);
  }

  bool get _canSend {
    if (widget.connectionState != KnxConnectionState.connected) return false;
    if (_gaMainCtrl.text.isEmpty ||
        _gaMiddleCtrl.text.isEmpty ||
        _gaSubCtrl.text.isEmpty) {
      return false;
    }
    if (_sendMode == 'Read') return true;
    return _isValueValid;
  }

  bool get _isValueValid {
    final t = _valueCtrl.text.trim();
    if (t.isEmpty) return false;
    final dptKey = _sendDptType.split(' ').first;
    switch (dptKey) {
      case '1.x':
        final v = int.tryParse(t);
        return v != null && v >= 0 && v <= 1;
      case '2.x':
        final v = int.tryParse(t);
        return v != null && v >= 0 && v <= 3;
      case '3.x':
        final v = int.tryParse(t);
        return v != null && v >= 0 && v <= 15;
      case '4.x':
        return t.length == 1;
      case '5.001':
        final v = double.tryParse(t);
        return v != null && v >= 0 && v <= 100;
      case '5.003':
        final v = double.tryParse(t);
        return v != null && v >= 0 && v <= 360;
      case '5.x':
      case '20.x':
        final v = int.tryParse(t);
        return v != null && v >= 0 && v <= 255;
      case '6.x':
        final v = int.tryParse(t);
        return v != null && v >= -128 && v <= 127;
      case '7.x':
        final v = int.tryParse(t);
        return v != null && v >= 0 && v <= 65535;
      case '8.x':
        final v = int.tryParse(t);
        return v != null && v >= -32768 && v <= 32767;
      case '9.x':
      case '14.x':
        return double.tryParse(t) != null;
      case '10.x':
        final v = int.tryParse(t);
        return v != null && v >= 0 && v <= 1439;
      case '11.x':
        final v = int.tryParse(t);
        return v != null && v >= 1 && v <= 31;
      case '12.x':
        final v = int.tryParse(t);
        return v != null && v >= 0;
      case '13.x':
        return int.tryParse(t) != null;
      case '17.x':
        final v = int.tryParse(t);
        return v != null && v >= 0 && v <= 63;
      case '18.x':
        final v = int.tryParse(t);
        return v != null && v >= 0 && v <= 127;
      default:
        return false;
    }
  }

  static const _sendFieldStyle = TextStyle(fontSize: 12, fontFamily: 'monospace');

  String get _sendGaName {
    final m = _gaMainCtrl.text;
    final mi = _gaMiddleCtrl.text;
    final s = _gaSubCtrl.text;
    if (m.isEmpty || mi.isEmpty || s.isEmpty) return '';
    final addr = '$m/$mi/$s';
    final name = widget.connection.project?.lookupGA(addr) ?? '';
    if (name.isEmpty) return '(No name available)';
    return name;
  }

  Widget _sendInput(TextEditingController ctrl, double width, bool enabled,
      {String? hint, List<TextInputFormatter>? formatters}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        style: _sendFieldStyle,
        keyboardType: TextInputType.number,
        inputFormatters: formatters,
        onTap: () => ctrl.selection = TextSelection(
            baseOffset: 0, extentOffset: ctrl.text.length),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _gaSlash(bool enabled) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text('/',
          style: TextStyle(fontSize: 14,
              color: enabled ? _cTextDim : _cTextDim.withAlpha(80))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.connectionState == KnxConnectionState.connected;
    final writeEnabled = enabled && _sendMode == 'Write';
    final labelStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
        color: enabled ? cs.onSurfaceVariant : cs.onSurfaceVariant.withAlpha(100));
    final sepColor = cs.outlineVariant.withAlpha(120);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: cs.surfaceContainerHighest.withAlpha(80),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // --- Destination ---
          Text('Destination:', style: labelStyle),
          const SizedBox(width: 8),
          _sendInput(_gaMainCtrl, 48, enabled,
              formatters: [FilteringTextInputFormatter.digitsOnly, _RangeFormatter(31)]),
          _gaSlash(enabled),
          _sendInput(_gaMiddleCtrl, 40, enabled,
              formatters: [FilteringTextInputFormatter.digitsOnly, _RangeFormatter(7)]),
          _gaSlash(enabled),
          _sendInput(_gaSubCtrl, 48, enabled,
              formatters: [FilteringTextInputFormatter.digitsOnly, _RangeFormatter(255)]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _sendGaName,
              style: TextStyle(fontSize: 11, color: _cTextDim, fontStyle: FontStyle.italic),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // --- Separator ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(height: 24, child: VerticalDivider(width: 1, color: sepColor)),
          ),
          // --- Direction ---
          Text('Direction:', style: labelStyle),
          const SizedBox(width: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Read', label: Text('Read', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 'Write', label: Text('Write', style: TextStyle(fontSize: 11))),
            ],
            selected: {_sendMode},
            showSelectedIcon: false,
            onSelectionChanged: enabled
                ? (s) => setState(() => _sendMode = s.first)
                : null,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          // --- Separator ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(height: 24, child: VerticalDivider(width: 1, color: sepColor)),
          ),
          // --- Value ---
          Text('Value:', style: labelStyle),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: writeEnabled ? cs.outline : cs.outline.withAlpha(60)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _sendDptType,
                  items: _sendDptTypes
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t, style: const TextStyle(fontSize: 11))))
                      .toList(),
                  onChanged: writeEnabled
                      ? (v) => setState(() => _sendDptType = v!)
                      : null,
                  style: TextStyle(fontSize: 11, color: cs.onSurface),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _sendInput(_valueCtrl, 80, writeEnabled, hint: '0',
              formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _canSend ? _doSend : null,
            child: const Text('Send', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

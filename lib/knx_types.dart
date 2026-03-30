import 'dart:math';
import 'dart:typed_data';

// KNXnet/IP constants
const int knxPort = 3671;
const String knxMulticast = '224.0.23.12';
const int headerSize = 6;
const Duration searchTimeout = Duration(seconds: 3);

// Service types
const int svcSearchRequest = 0x0201;
const int svcSearchResponse = 0x0202;
const int svcConnectRequest = 0x0205;
const int svcConnectResponse = 0x0206;
const int svcConnStateReq = 0x0207;
const int svcConnStateResp = 0x0208;
const int svcDisconnectReq = 0x0209;
const int svcDisconnectResp = 0x020A;
const int svcTunnelRequest = 0x0420;
const int svcTunnelAck = 0x0421;

// DPT type identifiers
const String dptSwitch = 'DPT-1';
const String dptDimControl = 'DPT-3';
const String dptPercent = 'DPT-5';
const String dptFloat16 = 'DPT-9';
const String dptUint32 = 'DPT-12';
const String dptFloat32 = 'DPT-14';
const String dptString = 'DPT-16';
const String dptUnknown = 'unknown';

class KnxBridge {
  final String ip;
  final String name;
  KnxBridge(this.ip, this.name);
}

class KnxEvent {
  final DateTime time;
  final String direction;
  final String source;
  String deviceName;
  final String destination;
  String groupName;
  final String apci;
  final String dpt;
  final String raw;
  final String value;

  KnxEvent({
    required this.time,
    required this.direction,
    required this.source,
    required this.deviceName,
    required this.destination,
    required this.groupName,
    required this.apci,
    required this.dpt,
    required this.raw,
    required this.value,
  });
}

class GAInfo {
  final String name;
  final String dpt;
  final String description;
  final String mainGroup;
  final String middleGroup;

  GAInfo({
    required this.name,
    this.dpt = '',
    this.description = '',
    this.mainGroup = '',
    this.middleGroup = '',
  });
}

class DeviceInfo {
  final String name;
  final String description;
  final String address;
  final String serialNumber;
  final String productName;
  final String orderNumber;
  final String manufacturer;
  final String lineName;
  final String areaName;

  DeviceInfo({
    required this.name,
    this.description = '',
    this.address = '',
    this.serialNumber = '',
    this.productName = '',
    this.orderNumber = '',
    this.manufacturer = '',
    this.lineName = '',
    this.areaName = '',
  });
}

// --- Address formatting ---

String formatPhysAddr(int hi, int lo) {
  final area = (hi >> 4) & 0x0F;
  final line = hi & 0x0F;
  final device = lo;
  return '$area.$line.$device';
}

String formatGroupAddr(int hi, int lo) {
  final main = (hi >> 3) & 0x1F;
  final middle = hi & 0x07;
  final sub = lo;
  return '$main/$middle/$sub';
}

String formatAddr(bool isGroup, int hi, int lo) {
  return isGroup ? formatGroupAddr(hi, lo) : formatPhysAddr(hi, lo);
}

String gaIntToString(int raw) {
  final main = (raw >> 11) & 0x1F;
  final middle = (raw >> 8) & 0x07;
  final sub = raw & 0xFF;
  return '$main/$middle/$sub';
}

// --- KNX header / HPAI builders ---

Uint8List knxHeader(int svcType, int totalLen) {
  final h = Uint8List(6);
  h[0] = 0x06;
  h[1] = 0x10;
  h[2] = (svcType >> 8) & 0xFF;
  h[3] = svcType & 0xFF;
  h[4] = (totalLen >> 8) & 0xFF;
  h[5] = totalLen & 0xFF;
  return h;
}

Uint8List hpai(List<int> ip4, int port) {
  return Uint8List.fromList([
    0x08, 0x01,
    ip4[0], ip4[1], ip4[2], ip4[3],
    (port >> 8) & 0xFF, port & 0xFF,
  ]);
}

// --- Direction decoding ---

String decodeDirection(int msgCode) {
  switch (msgCode) {
    case 0x29:
      return 'IND';
    case 0x2E:
      return 'CON';
    case 0x11:
      return 'REQ';
    default:
      return '0x${msgCode.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }
}

// --- APCI decoding ---

String decodeAPCI(List<int> apdu) {
  if (apdu.length < 2) return '?';
  final apci = (apdu[0] << 8) | apdu[1];
  final apciType = apci & 0x03C0;
  switch (apciType) {
    case 0x0000:
      return 'Read';
    case 0x0040:
      return 'Response';
    case 0x0080:
      return 'Write';
    default:
      return '0x${apci.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  }
}

// --- Raw hex formatting ---

String formatRawHex(List<int> apdu, int apduLen) {
  if (apduLen <= 2 && apdu.length >= 2) {
    return (apdu[1] & 0x3F).toRadixString(16).padLeft(2, '0').toUpperCase();
  }
  if (apdu.length < 3) return '';
  return apdu
      .sublist(2)
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}

// --- DPT functions ---

String guessDPT(int apduLen, List<int> apdu) {
  if (apduLen <= 2) return dptSwitch;
  final dataBytes = apduLen - 2;
  switch (dataBytes) {
    case 1:
      return dptPercent;
    case 2:
      return dptFloat16;
    case 4:
      return dptFloat32;
    case 14:
      return dptString;
    default:
      return dptUnknown;
  }
}

String normalizeDPT(String dpt) {
  if (dpt.startsWith('DPST-')) {
    final parts = dpt.substring(5).split('-');
    if (parts.isNotEmpty) {
      switch (parts[0]) {
        case '1':
          return dptSwitch;
        case '3':
          return dptDimControl;
        case '5':
          return dptPercent;
        case '9':
          return dptFloat16;
        case '12':
          return dptUint32;
        case '14':
          return dptFloat32;
        case '16':
          return dptString;
      }
    }
  }
  return dpt;
}

String dptToNumber(String dpt) {
  if (dpt.startsWith('DPST-')) {
    final parts = dpt.substring(5).split('-');
    if (parts.length == 2) {
      final sub = int.tryParse(parts[1]) ?? 0;
      return '${parts[0]}.${sub.toString().padLeft(3, '0')}';
    }
    return '${parts[0]}.x';
  }
  if (dpt.startsWith('DPT-')) {
    return '${dpt.substring(4)}.x';
  }
  return dpt;
}

String dptUnit(String dpt) {
  const units = {
    'DPST-9-1': ' °C',
    'DPST-9-2': ' K',
    'DPST-9-3': ' K/h',
    'DPST-9-4': ' lux',
    'DPST-9-5': ' m/s',
    'DPST-9-6': ' Pa',
    'DPST-9-7': ' %',
    'DPST-9-8': ' ppm',
    'DPST-9-10': ' s',
    'DPST-9-11': ' s',
    'DPST-9-20': ' mV',
    'DPST-9-21': ' mV',
    'DPST-9-24': ' kW',
    'DPST-9-28': ' km/h',
  };
  return units[dpt] ?? '';
}

double decodeKNXFloat16(int hi, int lo) {
  final sign = hi >> 7;
  final exp = (hi >> 3) & 0x0F;
  var mant = ((hi & 0x07) << 8) | lo;
  if (sign == 1) mant = mant - 2048;
  return 0.01 * mant * pow(2, exp);
}

String decodeValue(List<int> apdu, int apduLen, String dpt) {
  if (apdu.length < 2) return '';

  final ndpt = normalizeDPT(dpt);

  switch (ndpt) {
    case dptSwitch:
      final val = apdu[1] & 0x3F;
      return val == 0 ? 'OFF' : 'ON';

    case dptPercent:
      if (apdu.length < 3) return '';
      final raw = apdu[2];
      final pct = raw / 255.0 * 100.0;
      return '${pct.toStringAsFixed(0)}%';

    case dptFloat16:
      if (apdu.length < 4) return '';
      final f = decodeKNXFloat16(apdu[2], apdu[3]);
      final unit = dptUnit(dpt);
      return '${f.toStringAsFixed(2)}$unit';

    case dptFloat32:
      if (apdu.length < 6) return '';
      final bytes = ByteData(4);
      for (var i = 0; i < 4; i++) {
        bytes.setUint8(i, apdu[2 + i]);
      }
      final f = bytes.getFloat32(0, Endian.big);
      return f.toStringAsFixed(4);

    case dptString:
      if (apdu.length < 3) return '';
      final chars = apdu.sublist(2);
      final s = String.fromCharCodes(chars).replaceAll(RegExp(r'[\x00 ]+$'), '');
      return '"$s"';

    default:
      if (apduLen <= 2) {
        return '${apdu[1] & 0x3F}';
      }
      if (apdu.length < 3) return '';
      return apdu
          .sublist(2)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
  }
}

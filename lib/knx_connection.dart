import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'knx_types.dart';
import 'ets_project.dart';

final _log = Logger('KNX');

enum KnxKnxConnectionState { disconnected, connecting, connected, error }

class KnxConnection {
  RawDatagramSocket? _socket;
  StreamSubscription? _socketSub;
  int _channelId = 0;
  Timer? _heartbeatTimer;
  EtsProject? project;

  String _bridgeIp = '';
  int _bridgePort = knxPort;
  List<int> _localIp = [];
  int _localPort = 0;
  List<int> _hpaiIp = [];
  int _hpaiPort = 0;

  final _eventController = StreamController<KnxEvent>.broadcast();
  final _stateController = StreamController<KnxConnectionState>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  Stream<KnxEvent> get events => _eventController.stream;
  Stream<KnxConnectionState> get stateChanges => _stateController.stream;
  Stream<String> get statusMessages => _statusController.stream;

  KnxConnectionState _state = KnxConnectionState.disconnected;
  KnxConnectionState get state => _state;
  int messageCount = 0;

  void _setState(KnxConnectionState s) {
    _state = s;
    _stateController.add(s);
  }

  void _status(String msg) {
    _log.info(msg);
    _statusController.add(msg);
  }

  Future<void> connect(String host, {int port = knxPort}) async {
    try {
      _bridgePort = port;

      _setState(KnxConnectionState.connecting);
      _status('Connecting\u2026');

      // Resolve hostname to IP if needed
      try {
        final addresses = await InternetAddress.lookup(host);
        _bridgeIp = addresses.first.address;
        if (_bridgeIp != host) {
          _log.info('Resolved $host to $_bridgeIp');
        }
      } catch (e) {
        throw Exception('Cannot resolve hostname: $host');
      }

      _localIp = await _findLocalIp(_bridgeIp);
      _log.info('Local IP: ${_localIp.join('.')}');

      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _localPort = _socket!.port;
      _log.info('Bound to port $_localPort');

      // Use NAT mode (HPAI 0.0.0.0:0) if bridge is on a different subnet
      final useNat = !_isSameSubnet(_localIp, _bridgeIp);
      final hpaiIp = useNat ? [0, 0, 0, 0] : _localIp;
      final hpaiPort = useNat ? 0 : _localPort;
      if (useNat) {
        _log.info('Using NAT mode (bridge on different subnet)');
      }

      final connectPkt = _buildConnectRequest(hpaiIp, hpaiPort);
      _log.info('Sending CONNECT_REQUEST (HPAI ${hpaiIp.join('.')}:$hpaiPort)');
      _socket!.send(connectPkt, InternetAddress(_bridgeIp), _bridgePort);

      final completer = Completer<bool>();
      _socketSub = _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _socket?.receive();
          if (dg == null || dg.data.length < headerSize) return;
          _onData(dg.data, completer);
        }
      });

      Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          _log.info('Connect timeout — no CONNECT_RESPONSE received');
          completer.completeError('Connection timeout');
        }
      });

      await completer.future;

      _setState(KnxConnectionState.connected);
      _status('Connected');

      // Store HPAI for heartbeats
      _hpaiIp = hpaiIp;
      _hpaiPort = hpaiPort;

      _heartbeatTimer = Timer.periodic(const Duration(seconds: 50), (_) {
        _sendHeartbeat();
      });
    } catch (e, st) {
      _log.severe('$e', e, st);
      _setState(KnxConnectionState.error);
      _status('Connection Failure');
    }
  }

  void _onData(Uint8List data, [Completer<bool>? connectCompleter]) {
    final svcType = (data[2] << 8) | data[3];

    switch (svcType) {
      case svcConnectResponse:
        if (data.length < 8) return;
        _channelId = data[6];
        final status = data[7];
        if (connectCompleter != null && !connectCompleter.isCompleted) {
          if (status != 0) {
            _log.info('Connect refused: 0x${status.toRadixString(16)}');
            connectCompleter.completeError(
                'Connect refused: 0x${status.toRadixString(16)}');
          } else {
            _log.info('Connect OK, channel $_channelId');
            connectCompleter.complete(true);
          }
        }
        break;

      case svcTunnelRequest:
        if (data.length < 11) return;
        final seq = data[8];
        _sendTunnelAck(seq);
        _parseCEMI(data.sublist(10));
        break;

      case svcTunnelAck:
        break;

      case svcConnStateResp:
        if (data.length > 7 && data[7] != 0) {
          _log.info('Heartbeat error: 0x${data[7].toRadixString(16)}');
          _log.info('Connection state error: 0x${data[7].toRadixString(16)}');
        } else {
          _log.info('Heartbeat OK');
        }
        break;

      case svcDisconnectReq:
        _log.info('Bridge requested disconnect');
        final pkt = <int>[];
        pkt.addAll(knxHeader(svcDisconnectResp, 10));
        pkt.addAll([_channelId, 0x00, 0x00, 0x00]);
        _socket?.send(
            Uint8List.fromList(pkt), InternetAddress(_bridgeIp), _bridgePort);
        _setState(KnxConnectionState.disconnected);
        break;
    }
  }

  Future<List<int>> _findLocalIp(String bridgeIp) async {
    final interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    _log.info('Interfaces: ${interfaces.map((i) => '${i.name}=${i.addresses.map((a) => a.address).join(',')}').join('; ')}');

    // Try /24 subnet match if bridge address is an IP
    final bridgeParts = bridgeIp.split('.');
    if (bridgeParts.length == 4) {
      final bp = bridgeParts.map((s) => int.tryParse(s)).toList();
      if (bp.every((v) => v != null)) {
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (addr.isLoopback) continue;
            final parts = addr.address.split('.').map(int.parse).toList();
            if (parts[0] == bp[0] && parts[1] == bp[1] && parts[2] == bp[2]) {
              _log.info('Matched ${addr.address} on ${iface.name} (same /24)');
              return parts;
            }
          }
        }
      }
    }

    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) {
          return addr.address.split('.').map(int.parse).toList();
        }
      }
    }

    return [0, 0, 0, 0];
  }

  bool _isSameSubnet(List<int> localIp, String bridgeIp) {
    final parts = bridgeIp.split('.');
    if (parts.length != 4 || localIp.length != 4) return false;
    final bp = parts.map((s) => int.tryParse(s)).toList();
    if (bp.any((v) => v == null)) return false;
    return localIp[0] == bp[0] && localIp[1] == bp[1] && localIp[2] == bp[2];
  }

  Uint8List _buildConnectRequest(List<int> ip, int port) {
    final pkt = <int>[];
    pkt.addAll(knxHeader(svcConnectRequest, 26));
    pkt.addAll(hpai(ip, port));
    pkt.addAll(hpai(ip, port));
    pkt.addAll([0x04, 0x04, 0x02, 0x00]);
    return Uint8List.fromList(pkt);
  }

  void _sendHeartbeat() {
    final pkt = <int>[];
    pkt.addAll(knxHeader(svcConnStateReq, 16));
    pkt.addAll([_channelId, 0x00]);
    pkt.addAll(hpai(_hpaiIp, _hpaiPort));
    _socket?.send(
        Uint8List.fromList(pkt), InternetAddress(_bridgeIp), _bridgePort);
  }

  int _seqSend = 0;

  /// Send a group write or read telegram.
  /// [main], [middle], [sub] are the group address components.
  /// [apdu] is the APDU payload (e.g. [0x00, 0x80, value] for write, [0x00, 0x00] for read).
  void sendGroupTelegram(int main, int middle, int sub, List<int> apdu) {
    if (_state != KnxConnectionState.connected || _socket == null) return;

    final dstHi = ((main & 0x1F) << 3) | (middle & 0x07);
    final dstLo = sub & 0xFF;
    final dataLen = apdu.length - 1;

    // Build cEMI frame: L_Data.req
    final cemi = <int>[
      0x11, // message code: L_Data.req
      0x00, // additional info length
      0xB0, // ctrl1: standard frame, no repeat, broadcast, priority low
      0xE0, // ctrl2: group address destination
      0x00, 0x00, // source (0.0.0 = let bridge fill in)
      dstHi, dstLo,
      dataLen,
      ...apdu,
    ];

    final totalLen = 10 + cemi.length;
    final pkt = <int>[];
    pkt.addAll(knxHeader(svcTunnelRequest, totalLen));
    pkt.addAll([0x04, _channelId, _seqSend & 0xFF, 0x00]);
    pkt.addAll(cemi);

    _socket!.send(
        Uint8List.fromList(pkt), InternetAddress(_bridgeIp), _bridgePort);
    _seqSend++;
    _log.info('Sent ${apdu.length <= 2 ? "read" : "write"} to $main/$middle/$sub');
  }

  void _sendTunnelAck(int seq) {
    final pkt = <int>[];
    pkt.addAll(knxHeader(svcTunnelAck, 10));
    pkt.addAll([0x04, _channelId, seq, 0x00]);
    _socket?.send(
        Uint8List.fromList(pkt), InternetAddress(_bridgeIp), _bridgePort);
  }

  void _parseCEMI(List<int> cemi) {
    if (cemi.length < 2) return;

    final msgCode = cemi[0];
    final addInfoLen = cemi[1];

    if (cemi.length < 2 + addInfoLen + 8) return;

    final offset = 2 + addInfoLen;
    final ctrl2 = cemi[offset + 1];
    final srcHi = cemi[offset + 2];
    final srcLo = cemi[offset + 3];
    final dstHi = cemi[offset + 4];
    final dstLo = cemi[offset + 5];
    final dataLen = cemi[offset + 6];

    final src = formatPhysAddr(srcHi, srcLo);
    final dstIsGroup = (ctrl2 & 0x80) != 0;
    final dst = formatAddr(dstIsGroup, dstHi, dstLo);
    final dir = decodeDirection(msgCode);

    if (cemi.length < offset + 7 + dataLen) return;
    final apduLen = dataLen + 1;
    if (cemi.length < offset + 7 + apduLen) return;
    final apdu = cemi.sublist(offset + 7, offset + 7 + apduLen);

    final apci = decodeAPCI(apdu);
    final rawHex = formatRawHex(apdu, apduLen);

    var dpt = '';
    if (project != null && dstIsGroup) {
      dpt = project!.lookupGADPT(dst);
    }
    if (dpt.isEmpty) {
      dpt = guessDPT(apduLen, apdu);
    }
    final value = decodeValue(apdu, apduLen, dpt);
    final dptDisplay = dptToNumber(dpt);

    messageCount++;

    final deviceName = project?.lookupDevice(src) ?? '';
    final groupName = (dstIsGroup ? project?.lookupGA(dst) : null) ?? '';

    _eventController.add(KnxEvent(
      time: DateTime.now(),
      direction: dir,
      source: src,
      deviceName: deviceName,
      destination: dst,
      groupName: groupName,
      apci: apci,
      dpt: dptDisplay,
      raw: rawHex,
      value: value,
    ));
  }

  Future<List<KnxBridge>> discoverBridges() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final localPort = socket.port;

    final pkt = <int>[];
    pkt.addAll(knxHeader(svcSearchRequest, 14));
    pkt.addAll([
      0x08, 0x01, 0, 0, 0, 0,
      (localPort >> 8) & 0xFF, localPort & 0xFF,
    ]);

    _log.info('Sending SEARCH_REQUEST to $knxMulticast:$knxPort');
    socket.send(
        Uint8List.fromList(pkt), InternetAddress(knxMulticast), knxPort);

    final bridges = <KnxBridge>[];
    final seen = <String>{};

    await for (final event in socket.timeout(searchTimeout, onTimeout: (sink) {
      sink.close();
    })) {
      if (event != RawSocketEvent.read) continue;
      final dg = socket.receive();
      if (dg == null || dg.data.length < 14) continue;

      final svcType = (dg.data[2] << 8) | dg.data[3];
      if (svcType != svcSearchResponse) continue;

      var bridgeIp = InternetAddress.fromRawAddress(
          Uint8List.fromList(dg.data.sublist(8, 12)));
      if (bridgeIp.address == '0.0.0.0') {
        bridgeIp = dg.address;
      }

      final ipStr = bridgeIp.address;
      if (seen.contains(ipStr)) continue;
      seen.add(ipStr);

      var name = '';
      const dibOffset = 14;
      if (dg.data.length >= dibOffset + 2) {
        final dibLen = dg.data[dibOffset];
        final dibType = dg.data[dibOffset + 1];
        if (dibType == 0x01 &&
            dibLen >= 54 &&
            dg.data.length >= dibOffset + dibLen) {
          final nameStart = dibOffset + 24;
          final nameBytes = dg.data.sublist(nameStart, nameStart + 30);
          name = String.fromCharCodes(nameBytes)
              .replaceAll(RegExp(r'[\x00 ]+$'), '');
        }
      }

      _log.info('Found bridge: $ipStr ${name.isNotEmpty ? "($name)" : ""}');
      bridges.add(KnxBridge(ipStr, name));
    }

    socket.close();
    _log.info('Discovery done: ${bridges.length} bridge(s)');
    return bridges;
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socketSub?.cancel();
    _socketSub = null;
    _socket?.close();
    _socket = null;
    _setState(KnxConnectionState.disconnected);
    _status('Disconnected');
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _stateController.close();
    _statusController.close();
  }
}

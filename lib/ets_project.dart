import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'knx_types.dart';

const Map<String, String> manufacturers = {
  'M-0001': 'Siemens',
  'M-0002': 'ABB',
  'M-0004': 'Albrecht Jung',
  'M-0006': 'Busch-Jaeger',
  'M-0007': 'GIRA',
  'M-0008': 'Hager',
  'M-0009': 'Hager/Berker',
  'M-000C': 'Schneider Electric',
  'M-0048': 'Theben',
  'M-0071': 'MDT Technologies',
  'M-0083': 'Weinzierl',
  'M-00B9': 'BMS',
  'M-00C5': 'Intesis/HMS',
  'M-00E8': 'Elsner Elektronik',
  'M-01F5': 'Weinzierl',
};

class EtsProject {
  final Map<String, GAInfo> groupAddresses;
  final Map<String, DeviceInfo> devices;

  EtsProject({required this.groupAddresses, required this.devices});

  String lookupGA(String ga) => groupAddresses[ga]?.name ?? '';
  String lookupGADPT(String ga) => groupAddresses[ga]?.dpt ?? '';
  String lookupDevice(String addr) => devices[addr]?.name ?? '';

  static EtsProject loadFromBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find P-*/0.xml
    ArchiveFile? installFile;
    for (final file in archive) {
      final parts = file.name.split('/');
      if (parts.length == 2 &&
          parts[0].startsWith('P-') &&
          parts[1] == '0.xml') {
        installFile = file;
        break;
      }
    }
    if (installFile == null) {
      throw Exception('No installation XML (P-*/0.xml) found in project');
    }

    final xmlString = utf8.decode(installFile.content as List<int>);
    final doc = XmlDocument.parse(xmlString);

    // Build product catalog
    final productNames = <String, String>{};
    final productOrders = <String, String>{};
    _loadProductCatalog(archive, productNames, productOrders);

    final groupAddresses = <String, GAInfo>{};
    final devices = <String, DeviceInfo>{};

    // Find Installation element
    final installation = doc.findAllElements('Installation').firstOrNull;
    if (installation == null) {
      return EtsProject(groupAddresses: groupAddresses, devices: devices);
    }

    // Parse topology: Area > Line > (Segment >) DeviceInstance
    for (final area in installation.findAllElements('Area')) {
      final areaAddr = int.tryParse(area.getAttribute('Address') ?? '') ?? 0;
      final areaName = (area.getAttribute('Name') ?? '').trim();

      for (final line in area.findElements('Line')) {
        final lineAddr =
            int.tryParse(line.getAttribute('Address') ?? '') ?? 0;
        final lineName = (line.getAttribute('Name') ?? '').trim();

        void addDevice(XmlElement dev) {
          final devAddr =
              int.tryParse(dev.getAttribute('Address') ?? '') ?? 0;
          final physAddr = '$areaAddr.$lineAddr.$devAddr';
          var name = (dev.getAttribute('Description') ?? '').trim();
          if (name.isEmpty) {
            name = (dev.getAttribute('Name') ?? '').trim();
          }

          final productRefId = dev.getAttribute('ProductRefId') ?? '';
          var mfr = '';
          if (productRefId.isNotEmpty) {
            final mfrId = productRefId.split('_').first;
            mfr = manufacturers[mfrId] ?? mfrId;
          }

          devices[physAddr] = DeviceInfo(
            name: name,
            description: (dev.getAttribute('Description') ?? '').trim(),
            address: physAddr,
            serialNumber: dev.getAttribute('SerialNumber') ?? '',
            productName: productNames[productRefId] ?? '',
            orderNumber: productOrders[productRefId] ?? '',
            manufacturer: mfr,
            lineName: lineName,
            areaName: areaName,
          );
        }

        for (final dev in line.findElements('DeviceInstance')) {
          addDevice(dev);
        }
        for (final seg in line.findElements('Segment')) {
          for (final dev in seg.findElements('DeviceInstance')) {
            addDevice(dev);
          }
        }
      }
    }

    // Parse group addresses: GroupRanges > GroupRange (main) > GroupRange (middle) > GroupAddress
    final groupRanges = installation.findAllElements('GroupRanges').firstOrNull;
    if (groupRanges != null) {
      for (final mainRange in groupRanges.findElements('GroupRange')) {
        final mainName = (mainRange.getAttribute('Name') ?? '').trim();

        for (final midRange in mainRange.findElements('GroupRange')) {
          final midName = (midRange.getAttribute('Name') ?? '').trim();

          for (final ga in midRange.findElements('GroupAddress')) {
            final gaName = (ga.getAttribute('Name') ?? '').trim();
            if (gaName.isEmpty) continue;
            final rawAddr =
                int.tryParse(ga.getAttribute('Address') ?? '') ?? 0;
            final addr = gaIntToString(rawAddr);
            groupAddresses[addr] = GAInfo(
              name: '$mainName / $midName / $gaName',
              dpt: ga.getAttribute('DatapointType') ?? '',
              description: (ga.getAttribute('Description') ?? '').trim(),
              mainGroup: mainName,
              middleGroup: midName,
            );
          }
        }

        // GAs directly under main range
        for (final ga in mainRange.findElements('GroupAddress')) {
          final gaName = (ga.getAttribute('Name') ?? '').trim();
          if (gaName.isEmpty) continue;
          final rawAddr =
              int.tryParse(ga.getAttribute('Address') ?? '') ?? 0;
          final addr = gaIntToString(rawAddr);
          groupAddresses[addr] = GAInfo(
            name: '$mainName / $gaName',
            dpt: ga.getAttribute('DatapointType') ?? '',
            description: (ga.getAttribute('Description') ?? '').trim(),
            mainGroup: mainName,
          );
        }
      }
    }

    return EtsProject(groupAddresses: groupAddresses, devices: devices);
  }

  static void _loadProductCatalog(
    Archive archive,
    Map<String, String> names,
    Map<String, String> orders,
  ) {
    for (final file in archive) {
      if (file.name.endsWith('/Catalog.xml')) {
        try {
          final xml = utf8.decode(file.content as List<int>);
          final doc = XmlDocument.parse(xml);
          _collectCatalogItems(doc.findAllElements('CatalogSection'), names);
        } catch (_) {}
      }
      if (file.name.endsWith('/Hardware.xml')) {
        try {
          final xml = utf8.decode(file.content as List<int>);
          final doc = XmlDocument.parse(xml);
          for (final product in doc.findAllElements('Product')) {
            final id = product.getAttribute('Id') ?? '';
            if (id.isEmpty) continue;
            final text = product.getAttribute('Text') ?? '';
            final orderNum = product.getAttribute('OrderNumber') ?? '';
            if (text.isNotEmpty) names[id] = text;
            if (orderNum.isNotEmpty) orders[id] = orderNum;
          }
        } catch (_) {}
      }
    }
  }

  static void _collectCatalogItems(
    Iterable<XmlElement> sections,
    Map<String, String> names,
  ) {
    for (final section in sections) {
      for (final item in section.findElements('CatalogItem')) {
        final refId = item.getAttribute('ProductRefId') ?? '';
        final name = item.getAttribute('Name') ?? '';
        if (refId.isNotEmpty && name.isNotEmpty) {
          names[refId] = name;
        }
      }
      _collectCatalogItems(section.findElements('CatalogSection'), names);
    }
  }
}

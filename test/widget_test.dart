import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/main.dart';

void main() {
  testWidgets('App renders KNX Monitor title', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(home: KnxMonitorPage(autoConnect: false)),
    );
    expect(find.text('KNX Monitor'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/main.dart';

void main() {
  testWidgets('App renders KNX Monitor title', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('KNX Monitor'), findsOneWidget);
  });
}

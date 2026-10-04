import 'package:flutter_test/flutter_test.dart';
import 'package:shapnest_app/main.dart';
import 'package:shapnest_app/services/ble_service.dart';
import 'package:shapnest_app/services/distance_engine.dart';

void main() {
  testWidgets('SHAPNEST App Smoke Test', (WidgetTester tester) async {
    final distanceEngine = DistanceEngine();
    final bleService = BleService(distanceEngine: distanceEngine);

    await tester.pumpWidget(ShapnestApp(bleService: bleService));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify title is rendered
    expect(find.text('SHAPNEST'), findsOneWidget);

    // Cleanly dispose service
    bleService.dispose();
  });
}

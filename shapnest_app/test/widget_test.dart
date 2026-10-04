import 'package:flutter_test/flutter_test.dart';
import 'package:shapnest_app/main.dart';
import 'package:shapnest_app/services/ble_service.dart';
import 'package:shapnest_app/services/distance_engine.dart';
import 'package:shapnest_app/services/theme_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('SHAPNEST App Smoke Test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final distanceEngine = DistanceEngine();
    await distanceEngine.init();

    final themeService = ThemeService();
    await themeService.init();

    final bleService = BleService(distanceEngine: distanceEngine);

    await tester.pumpWidget(ShapnestApp(
      bleService: bleService,
      themeService: themeService,
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify title is rendered
    expect(find.text('SHAPNEST'), findsOneWidget);

    // Cleanly dispose service
    bleService.dispose();
  });
}

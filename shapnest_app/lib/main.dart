import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/ble_service.dart';
import 'services/distance_engine.dart';
import 'services/theme_service.dart';
import 'ui/app_theme.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dynamic status bar navigation styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final distanceEngine = DistanceEngine();
  await distanceEngine.init();

  final themeService = ThemeService();
  await themeService.init();

  final bleService = BleService(distanceEngine: distanceEngine);

  runApp(ShapnestApp(
    bleService: bleService,
    themeService: themeService,
  ));
}

class ShapnestApp extends StatelessWidget {
  final BleService bleService;
  final ThemeService themeService;

  const ShapnestApp({
    super.key,
    required this.bleService,
    required this.themeService,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, child) {
        return MaterialApp(
          title: 'SHAPNEST Distance Engine',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeService.themeMode,
          home: HomeScreen(
            bleService: bleService,
            themeService: themeService,
          ),
        );
      },
    );
  }
}

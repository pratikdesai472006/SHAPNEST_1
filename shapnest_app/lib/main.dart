import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/ble_service.dart';
import 'services/distance_engine.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set immersive dark status bar navigation style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF020617),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final distanceEngine = DistanceEngine();
  await distanceEngine.init();

  final bleService = BleService(distanceEngine: distanceEngine);

  runApp(ShapnestApp(bleService: bleService));
}

class ShapnestApp extends StatelessWidget {
  final BleService bleService;

  const ShapnestApp({super.key, required this.bleService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SHAPNEST Distance Engine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF020617),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFA855F7),
          surface: Color(0xFF0F172A),
          error: Color(0xFFFF5252),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: HomeScreen(bleService: bleService),
    );
  }
}

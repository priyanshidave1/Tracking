import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'package:my_app/services/background_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/auth_provider.dart';
import 'screens/SplashScreen.dart';
import 'utils/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'My App',
      theme: AppTheme.lightTheme, // or however you use AppTheme
      home: const SplashScreen(),
    );
  }
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  await _clearStaleDataOnFreshInstall();
  // ✅ Show app FIRST — Login visible immediately on Vivo!
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const MyApp(),
    ),
  );

  // ✅ Init background service AFTER UI is shown
  _initServicesInBackground();
}

Future<void> _clearStaleDataOnFreshInstall() async {
  final prefs = await SharedPreferences.getInstance();
  final alreadyInitialized = prefs.getBool('_app_initialized') ?? false;
  if (!alreadyInitialized) {
    final storage = FlutterSecureStorage(); // ← 'final' not 'const'
    await storage.deleteAll();
    await prefs.setBool('_app_initialized', true);
    debugPrint('🧹 Fresh install detected — cleared stale secure storage');
  }
}

// ✅ All heavy init runs here — won't block Login page
Future<void> _initServicesInBackground() async {
  // Small delay to let UI fully render first
  await Future.delayed(const Duration(milliseconds: 500));

  if (!_isWeb()) {
    try {
      await initBackgroundService().timeout(
        const Duration(seconds: 10), // ✅ Timeout — won't hang forever
        onTimeout: () {
          debugPrint('⚠️ Background service init timed out (Vivo/aggressive OS)');
        },
      );
    } catch (e) {
      debugPrint('⚠️ Background service init failed: $e');
      // ✅ App still works — just without background service
    }
  }
}

bool _isWeb() {
  try {
    return identical(0, 0.0);
  } catch (_) {
    return false;
  }
}
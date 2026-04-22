import 'package:flutter/material.dart';
import 'package:my_app/screens/SplashScreen.dart';
import 'package:my_app/services/sessionservice.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'services/background_location_service.dart';
import '../utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the background location service (Android foreground service
  // + iOS background mode configuration).
  await initBackgroundService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      // LifecycleWatcher sits above MaterialApp so it receives lifecycle
      // events for the entire app lifetime, including while navigating
      // between screens.
      child: const _LifecycleWatcher(
        child: MyApp(),
      ),
    ),
  );
}

// ── Root app widget ───────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  const MyApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AP Cabinet Staff',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // SplashScreen is the entry point on every cold start.
      // It reads session state and immediately replaces itself with either
      // HomeScreen or LoginScreen — the user never lingers here.
      home: const SplashScreen(),
    );
  }
}

// ── Lifecycle watcher ─────────────────────────────────────────────────────────
//
// A thin StatefulWidget that wraps the entire widget tree and observes
// AppLifecycleState changes.  When the app is paused (goes to background
// or is killed by the OS), it records the current timestamp via
// SessionService so that SplashScreen can later compute how long the
// app was away.

class _LifecycleWatcher extends StatefulWidget {
  final Widget child;

  const _LifecycleWatcher({required this.child});

  @override
  State<_LifecycleWatcher> createState() => _LifecycleWatcherState();
}

class _LifecycleWatcherState extends State<_LifecycleWatcher>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // [paused]   → app sent to background (home button, task switcher, or
    //               about to be killed).  Write the timestamp NOW so that
    //               even if the process is killed immediately after, the
    //               timestamp is already persisted.
    // [resumed]  → no action needed; SplashScreen handles restore on cold
    //               start, and hot-resume is handled by the individual
    //               screen's own didChangeAppLifecycleState observers.
    if (state == AppLifecycleState.paused) {
      SessionService.onAppPaused();
      debugPrint('📱 App paused — background timestamp recorded');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
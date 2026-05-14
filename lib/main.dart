import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/app_state_scope.dart';
import 'firebase_options.dart';
import 'pages/dashboard_page.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/notifications_service.dart' show NotificationsService, firebaseBackgroundHandler;
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.init();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    await NotificationsService.instance.init();
  } catch (e) {
    debugPrint('[Firebase] init failed: $e');
  }
  runApp(const _Root());
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> with WidgetsBindingObserver {
  final AppState _appState = AppState();
  final AuthService _auth = AuthService();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<({String title, String body})>? _notifSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifSub = NotificationsService.instance.inAppNotifications.listen((n) {
      debugPrint('[FCM] inApp received: ${n.title} — key=${_messengerKey.currentState}');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (n.body.isNotEmpty) Text(n.body),
            ],
          ),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _auth.refreshToken();
      unawaited(NotificationsService.instance.syncTokenWithBackend());
    }
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _appState.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      notifier: _appState,
      child: MaterialApp(
        scaffoldMessengerKey: _messengerKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const DashboardPage(),
      ),
    );
  }
}

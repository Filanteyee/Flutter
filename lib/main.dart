import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/app_state_scope.dart';
import 'firebase_options.dart';
import 'pages/dashboard_page.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/notifications_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.init();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationsService.instance.init();
  runApp(const _Root());
}

class _Root extends StatefulWidget {
  const _Root({super.key});

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> with WidgetsBindingObserver {
  final AppState _appState = AppState();
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // При возврате приложения на экран обновляем JWT с актуальной ролью из БД
    if (state == AppLifecycleState.resumed) {
      _auth.refreshToken();
    }
  }

  @override
  void dispose() {
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
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const DashboardPage(),
      ),
    );
  }
}

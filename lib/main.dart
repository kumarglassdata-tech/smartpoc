import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_logger.dart';
import 'app_router.dart';
import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'location_service.dart';
import 'session/session_provider.dart';
import 'sources/camera_service.dart';

// wakelock_plus has no web platform-channel implementation in this setup -
// calling it there throws PlatformException and (unhandled) aborts startup
// before runApp(), producing a blank page. Screen-awake is a mobile concern
// anyway, so it's skipped on web rather than worked around.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await AppLogger.init();
  if (!kIsWeb) {
    await WakelockPlus.enable();
  }

  final auth = AuthProvider();
  await auth.load();
  final settings = SettingsProvider();
  await settings.load();

  final session = SessionProvider(
    cameraService: CameraService(),
    locationService: LocationService(),
    settingsProvider: settings,
    authProvider: auth,
  );

  runApp(SmartPocApp(auth: auth, settings: settings, session: session));
}

class SmartPocApp extends StatelessWidget {
  final AuthProvider auth;
  final SettingsProvider settings;
  final SessionProvider session;

  const SmartPocApp({super.key, required this.auth, required this.settings, required this.session});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: session),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settingsValue, _) => MaterialApp.router(
          title: 'SmartPoc',
          theme: buildAppTheme(isDark: settingsValue.isDarkMode),
          routerConfig: createRouter(auth),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}

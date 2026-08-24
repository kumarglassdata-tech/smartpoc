import 'package:go_router/go_router.dart';

import 'auth/auth_provider.dart';
import 'auth/login_screen.dart';
import 'auth/splash_screen.dart';
import 'home_shell.dart';
import 'personalize_feed_screen.dart';

GoRouter createRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      // Splash controls its own timing (auth/settings are already loaded by
      // the time it mounts, so it's a fixed-duration animation, not a real
      // loading wait) - it navigates onward itself once it's done.
      if (state.matchedLocation == '/splash') return null;

      final loggedIn = auth.isLoggedIn;
      final isLogin = state.matchedLocation == '/login';
      final isPersonalize = state.matchedLocation == '/personalize-feed';
      if (!loggedIn) return isLogin ? null : '/login';
      if (loggedIn && isLogin) return '/home';
      if (loggedIn && !auth.hasPreferences && !isPersonalize) return '/personalize-feed';
      if (loggedIn && auth.hasPreferences && isPersonalize) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => SplashScreen(auth: auth)),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/personalize-feed', builder: (context, state) => const PersonalizeFeedScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeShell()),
    ],
  );
}

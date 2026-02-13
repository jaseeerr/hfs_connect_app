import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'services/auth_storage.dart';
import 'services/app_navigator.dart';
import 'screens/clients_page.dart';
import 'screens/dashboard_page.dart';
import 'screens/guards_page.dart';
import 'screens/home_page.dart';
import 'screens/login_page.dart';
import 'screens/new_roster_page.dart';
import 'screens/roster_page.dart';
import 'screens/splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthStorage.init();
  runApp(const HfsConnectApp(initialRoute: AppRoutes.splash));
}

class HfsConnectApp extends StatelessWidget {
  const HfsConnectApp({super.key, this.initialRoute = AppRoutes.login});

  final String initialRoute;

  static const Set<String> _protectedRoutes = <String>{
    AppRoutes.home,
    AppRoutes.dashboard,
    AppRoutes.roster,
    AppRoutes.newRoster,
    AppRoutes.rosterView,
    AppRoutes.guards,
    AppRoutes.clients,
  };

  String? _extractRosterId(Object? args) {
    if (args is String) {
      final String id = args.trim();
      return id.isEmpty ? null : id;
    }
    if (args is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(args);
      final String id = (map['rosterId'] ?? '').toString().trim();
      return id.isEmpty ? null : id;
    }
    return null;
  }

  Widget _buildPage(String routeName, {Object? args}) {
    switch (routeName) {
      case AppRoutes.splash:
        return const SplashPage();
      case AppRoutes.login:
        return const LoginPage();
      case AppRoutes.home:
        return const HomePage();
      case AppRoutes.dashboard:
        return const DashboardPage();
      case AppRoutes.roster:
        return const RosterPage();
      case AppRoutes.newRoster:
        return NewRosterPage(rosterId: _extractRosterId(args));
      case AppRoutes.rosterView:
        return NewRosterPage(rosterId: _extractRosterId(args));
      case AppRoutes.guards:
        return const GuardsPage();
      case AppRoutes.clients:
        return const ClientsPage();
      default:
        return const LoginPage();
    }
  }

  bool _shouldRouteBackToDashboardOnRoot(String routeName) {
    if (routeName == AppRoutes.login ||
        routeName == AppRoutes.home ||
        routeName == AppRoutes.dashboard) {
      return false;
    }
    return _protectedRoutes.contains(routeName);
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final String requestedRoute = settings.name ?? AppRoutes.login;
    final bool hasToken = AuthStorage.hasToken;
    final bool isProtected = _protectedRoutes.contains(requestedRoute);
    final String resolvedRoute;
    if (requestedRoute == AppRoutes.login && hasToken) {
      resolvedRoute = AppRoutes.dashboard;
    } else if (isProtected && !hasToken) {
      resolvedRoute = AppRoutes.login;
    } else {
      resolvedRoute = requestedRoute;
    }

    final RouteSettings resolvedSettings = RouteSettings(
      name: resolvedRoute,
      arguments: settings.arguments,
    );
    final Widget page = _buildPage(resolvedRoute, args: settings.arguments);
    final Widget effectivePage =
        _shouldRouteBackToDashboardOnRoot(resolvedRoute)
        ? _BackToDashboardOnRoot(child: page)
        : page;

    final bool useCupertino =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    if (useCupertino) {
      return CupertinoPageRoute<dynamic>(
        settings: resolvedSettings,
        builder: (_) => effectivePage,
      );
    }

    return PageRouteBuilder<dynamic>(
      settings: resolvedSettings,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, animation, secondaryAnimation) => effectivePage,
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final CurvedAnimation curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppNavigator.navigatorKey,
      title: 'HFS Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      initialRoute: initialRoute,
      onGenerateRoute: _onGenerateRoute,
    );
  }
}

class _BackToDashboardOnRoot extends StatelessWidget {
  const _BackToDashboardOnRoot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        final NavigatorState navigator = Navigator.of(context);
        if (!navigator.canPop()) {
          navigator.pushReplacementNamed(AppRoutes.dashboard);
        }
      },
      child: child,
    );
  }
}

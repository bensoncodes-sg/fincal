import 'package:flutter/material.dart';

import 'prefs.dart';
import 'state.dart';
import 'storage.dart';
import 'ui/screens/shell.dart';
import 'ui/screens/splash.dart';
import 'ui/theme.dart';
import 'ui/tour.dart';

void main() {
  runApp(const BasisApp());
}

class BasisApp extends StatefulWidget {
  /// Where "the intro tour was seen" is remembered. Tests pass an in-memory
  /// one so runs do not affect each other.
  final TourMemory? tourMemory;

  /// Where saved scenarios live. Tests pass an in-memory store: the real one
  /// does disk work, which never completes under the test clock, so on a
  /// fresh machine (like the deploy server) the app never finished starting.
  final ScenarioStore? scenarioStore;

  const BasisApp({super.key, this.tourMemory, this.scenarioStore});

  @override
  State<BasisApp> createState() => _BasisAppState();
}

class _BasisAppState extends State<BasisApp> {
  late final AppState _app;
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final Future<void> _ready;
  late final TourController _tour;
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    _app = AppState(store: widget.scenarioStore ?? createScenarioStore());
    _ready = _app.init();
    _tour = TourController(
      app: _app,
      navigatorKey: _navigatorKey,
      memory: widget.tourMemory ?? PrefsTourMemory(createPrefsStore()),
    );
  }

  @override
  void dispose() {
    _tour.dispose();
    super.dispose();
  }

  void _onSplashDone() {
    setState(() => _splashDone = true);
    // First launch only: once the home screen is up and the examples are
    // loaded, so the tour has something real to point at.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ready;
      if (mounted) await _tour.startIfFirstRun();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _app,
      builder: (context, _) {
        final platformDark =
            MediaQuery.platformBrightnessOf(context) == Brightness.dark;
        final dark = switch (_app.themeMode) {
          BasisThemeMode.dark => true,
          BasisThemeMode.light => false,
          BasisThemeMode.system => platformDark,
        };
        final colors = dark ? BasisColors.dark : BasisColors.light;

        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Basis',
          debugShowCheckedModeBanner: false,
          theme: buildMaterialTheme(colors, dark),
          // BasisTheme must sit ABOVE the Navigator, not inside `home`.
          // A pushed route is a sibling of `home`, not a descendant, so
          // wrapping `home` left every pushed screen without the theme —
          // which threw on lookup and rendered a blank route in release,
          // where the assert in BasisTheme.of is stripped out.
          // The tour sits above the Navigator too, so it can move between
          // screens and stay on top of all of them.
          builder: (context, child) => BasisTheme(
            colors: colors,
            isDark: dark,
            child: TourScope(
              controller: _tour,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child ?? const SizedBox.shrink(),
                  TourOverlay(controller: _tour),
                ],
              ),
            ),
          ),
          home: _splashDone
              ? Shell(app: _app)
              : SplashScreen(onDone: _onSplashDone),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import 'state.dart';
import 'storage.dart';
import 'ui/screens/shell.dart';
import 'ui/screens/splash.dart';
import 'ui/theme.dart';

void main() {
  runApp(const BasisApp());
}

class BasisApp extends StatefulWidget {
  const BasisApp({super.key});

  @override
  State<BasisApp> createState() => _BasisAppState();
}

class _BasisAppState extends State<BasisApp> {
  final _app = AppState(store: createScenarioStore());
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    _app.init();
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
          title: 'Basis',
          debugShowCheckedModeBanner: false,
          theme: buildMaterialTheme(colors, dark),
          // BasisTheme must sit ABOVE the Navigator, not inside `home`.
          // A pushed route is a sibling of `home`, not a descendant, so
          // wrapping `home` left every pushed screen without the theme —
          // which threw on lookup and rendered a blank route in release,
          // where the assert in BasisTheme.of is stripped out.
          builder: (context, child) => BasisTheme(
            colors: colors,
            isDark: dark,
            child: child ?? const SizedBox.shrink(),
          ),
          home: _splashDone
              ? Shell(app: _app)
              : SplashScreen(onDone: () => setState(() => _splashDone = true)),
        );
      },
    );
  }
}

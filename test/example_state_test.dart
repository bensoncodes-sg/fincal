import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/registry.dart';
import 'package:basis/state.dart';
import 'package:basis/ui/components.dart';
import 'package:basis/ui/screens/calculator_screen.dart';
import 'package:basis/ui/theme.dart';

/// Seeded values must never look like the user's own figures.
///
/// A calculator that opens showing 850,000 at full ink is making a claim about
/// someone's money that nobody made. Until an input is edited it is drawn
/// translucent, the way placeholder text is, and the result badge says EXAMPLE
/// rather than LIVE.
Widget _host(Widget child) => MaterialApp(
  builder: (context, c) => BasisTheme(
    colors: BasisColors.light,
    isDark: false,
    child: c ?? const SizedBox.shrink(),
  ),
  home: child,
);

void main() {
  testWidgets('opens marked EXAMPLE, not LIVE', (tester) async {
    final calc = calculatorById('mortgage')!;
    await tester.pumpWidget(
      _host(CalculatorScreen(calculator: calc, app: AppState())),
    );
    await tester.pumpAndSettle();

    expect(find.text('EXAMPLE'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('every seeded input starts translucent', (tester) async {
    final calc = calculatorById('mortgage')!;
    await tester.pumpWidget(
      _host(CalculatorScreen(calculator: calc, app: AppState())),
    );
    await tester.pumpAndSettle();

    final rows = tester.widgetList<InputRow>(find.byType(InputRow));
    expect(rows, isNotEmpty);
    for (final r in rows) {
      expect(
        r.isExample,
        isTrue,
        reason: '${r.spec.key} should start marked as an example',
      );
    }
  });

  testWidgets('editing one field makes only that field solid', (tester) async {
    final calc = calculatorById('mortgage')!;
    await tester.pumpWidget(
      _host(CalculatorScreen(calculator: calc, app: AppState())),
    );
    await tester.pumpAndSettle();

    // Type into the first money field.
    final fields = find.byType(TextField);
    expect(fields, findsWidgets);
    await tester.enterText(fields.first, '900000');
    await tester.pumpAndSettle();

    final rows = tester.widgetList<InputRow>(find.byType(InputRow)).toList();
    final edited = rows.where((r) => !r.isExample).toList();
    final untouched = rows.where((r) => r.isExample).toList();

    expect(edited.length, 1, reason: 'only the edited row should turn solid');
    expect(
      untouched,
      isNotEmpty,
      reason: 'the rest must stay marked as examples',
    );
  });

  testWidgets('badge flips to LIVE once anything is edited', (tester) async {
    final calc = calculatorById('mortgage')!;
    await tester.pumpWidget(
      _host(CalculatorScreen(calculator: calc, app: AppState())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '900000');
    await tester.pumpAndSettle();

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('EXAMPLE'), findsNothing);
  });

  testWidgets('the example state exists on every calculator, not just one', (
    tester,
  ) async {
    for (final calc in allCalculators) {
      await tester.pumpWidget(
        _host(
          KeyedSubtree(
            key: ValueKey(calc.id),
            child: CalculatorScreen(calculator: calc, app: AppState()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: calc.id);
      // Calculators whose result is an error show no badge; the rest must
      // declare themselves as examples on open.
      final result = calc.compute(calc.defaults, AppState().rules);
      if (result.error == null) {
        expect(find.text('EXAMPLE'), findsOneWidget, reason: calc.id);
      }
    }
  });

  testWidgets('an edited value is what actually drives the result', (
    tester,
  ) async {
    final calc = calculatorById('mortgage')!;
    await tester.pumpWidget(
      _host(CalculatorScreen(calculator: calc, app: AppState())),
    );
    await tester.pumpAndSettle();

    // Seeded 637,500 at 3.85% over 25 years gives 3,312.39.
    expect(find.textContaining('3,312.39'), findsWidgets);

    // Halve the loan; the instalment must move, not merely restyle.
    final loanField = find.byType(TextField).at(1);
    await tester.enterText(loanField, '318750');
    await tester.pumpAndSettle();

    expect(find.textContaining('3,312.39'), findsNothing);
    expect(find.textContaining('1,656'), findsWidgets);
  });
}

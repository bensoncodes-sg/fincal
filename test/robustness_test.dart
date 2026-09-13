import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/registry.dart';
import 'package:basis/core/calculator.dart';
import 'package:basis/core/money.dart';
import 'package:basis/rules/sg_rules.dart';
import 'package:basis/state.dart';
import 'package:basis/ui/screens/calculator_screen.dart';
import 'package:basis/ui/screens/compare.dart';
import 'package:basis/ui/screens/shell.dart';
import 'package:basis/ui/theme.dart';

/// Bug hunt. Each group here targets a place where something looked wrong on
/// inspection rather than a place a feature was being added.
Widget host(Widget child, {bool dark = false}) => MaterialApp(
  builder: (context, c) => BasisTheme(
    colors: dark ? BasisColors.dark : BasisColors.light,
    isDark: dark,
    child: c ?? const SizedBox.shrink(),
  ),
  home: child,
);

Scenario scn(String id, {DateTime? at}) => Scenario(
  id: id,
  calculatorId: 'mortgage',
  name: id,
  inputs: const {},
  savedAt: at ?? DateTime(2026, 9, 1),
  headlineLabel: 'X',
  headlineValue: 'Y',
);

void main() {
  final rules = SgRules.defaults;

  group('Reading state must not change it', () {
    test('the scenarios getter does not reorder the underlying list', () async {
      final app = AppState();
      await app.init();
      for (var i = 0; i < 5; i++) {
        await app.saveScenario(scn('s$i', at: DateTime(2026, 9, 1 + i)));
      }

      // Reading twice must be stable, and must not disturb anything else.
      final first = app.scenarios.map((s) => s.id).toList();
      final second = app.scenarios.map((s) => s.id).toList();
      expect(first, second);

      // A getter that sorts in place mutates private state on every read,
      // which is how iteration-order bugs and concurrent-modification
      // crashes appear later.
      final ours = first.where((id) => id.startsWith('s')).toList();
      expect(ours.first, 's4', reason: 'newest of ours first');
      expect(ours, ['s4', 's3', 's2', 's1', 's0']);
    });

    test('reading scenarios during iteration does not throw', () async {
      final app = AppState();
      await app.init();
      for (var i = 0; i < 20; i++) {
        await app.saveScenario(scn('n$i', at: DateTime(2026, 9, 1 + i % 28)));
      }
      expect(() {
        for (final _ in app.scenarios) {
          app.scenarios.length; // a read inside the loop
        }
      }, returnsNormally);
    });
  });

  group('What is displayed is what is computed', () {
    testWidgets('a value clamped to the maximum is shown clamped', (
      tester,
    ) async {
      final calc = calculatorById('mortgage')!;
      await tester.pumpWidget(
        host(CalculatorScreen(calculator: calc, app: AppState())),
      );
      await tester.pumpAndSettle();

      // The rate field caps at 8. Typing 99 must not leave "99" on screen
      // while the app quietly computes with 8.
      final rate = find.byType(TextField).at(2);
      await tester.enterText(rate, '99');
      await tester.pumpAndSettle();

      // While focused the typed text stays, but the app must SAY it is using
      // a different value rather than silently computing with one.
      expect(
        find.textContaining('Using the maximum'),
        findsOneWidget,
        reason: 'typed 99 against a maximum of 8 with no warning',
      );

      // On blur the field snaps to the value actually in use.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final shown = tester.widget<TextField>(rate).controller!.text;
      final asNumber = double.tryParse(shown.replaceAll(',', ''));
      expect(asNumber, isNotNull, reason: 'field shows "\$shown"');
      expect(
        asNumber,
        lessThanOrEqualTo(8.0),
        reason: 'after blur the field still shows \$shown',
      );
    });

    testWidgets('a value below the minimum is shown clamped', (tester) async {
      final calc = calculatorById('mortgage')!;
      await tester.pumpWidget(
        host(CalculatorScreen(calculator: calc, app: AppState())),
      );
      await tester.pumpAndSettle();

      final tenor = find.byType(TextField).at(3);
      await tester.enterText(tenor, '0');
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Using the minimum'),
        findsOneWidget,
        reason: 'typed 0 against a minimum of 1 with no warning',
      );

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final shown = tester.widget<TextField>(tenor).controller!.text;
      final asNumber = double.tryParse(shown.replaceAll(',', ''));
      expect(asNumber, isNotNull);
      expect(
        asNumber,
        greaterThanOrEqualTo(1.0),
        reason: 'after blur the field still shows \$shown',
      );
    });
  });

  group('The EXAMPLE badge tells the truth', () {
    testWidgets('switching what TVM solves for is not an edit', (tester) async {
      final calc = calculatorById('tvm')!;
      await tester.pumpWidget(
        host(CalculatorScreen(calculator: calc, app: AppState())),
      );
      await tester.pumpAndSettle();
      expect(find.text('EXAMPLE'), findsOneWidget);

      // Choosing a different unknown changes no figure the user supplied,
      // so the seeded values are still examples.
      await tester.tap(find.text('FV'));
      await tester.pumpAndSettle();

      expect(
        find.text('EXAMPLE'),
        findsOneWidget,
        reason: 'no input value was edited, so nothing became the user\'s',
      );
      expect(find.text('LIVE'), findsNothing);
    });

    testWidgets('editing an actual value still flips it', (tester) async {
      final calc = calculatorById('tvm')!;
      await tester.pumpWidget(
        host(CalculatorScreen(calculator: calc, app: AppState())),
      );
      await tester.pumpAndSettle();

      // The inputs sit below the result and the example note.
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '-100000');
      await tester.pumpAndSettle();
      // Back up to the result card, where the badge is.
      await tester.drag(find.byType(ListView).first, const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(find.text('LIVE'), findsOneWidget);
    });
  });

  group('Money formatting holds at the edges', () {
    test('negative amounts round to whole dollars correctly', () {
      expect(const Money(-99371457).format(decimals: 0), '-993,715');
      expect(const Money(-50).format(decimals: 0), '-0');
      expect(const Money(-150).format(decimals: 0), '-2');
    });

    test('zero and sub-cent values format cleanly', () {
      expect(Money.zero.format(), '0.00');
      expect(Money.zero.sgd, 'S\$ 0.00');
      expect(const Money(1).format(), '0.01');
      expect(const Money(-1).format(), '-0.01');
    });

    test('very large amounts keep their grouping', () {
      expect(const Money(999999999999).format(), '9,999,999,999.99');
    });

    test('parsing rejects nonsense rather than guessing', () {
      for (final bad in ['', '  ', 'abc', '-', '.', '..', '1.2.3', '--5']) {
        expect(Money.tryParse(bad), isNull, reason: 'parsed "$bad"');
      }
    });
  });

  group('Screens survive hostile inputs', () {
    testWidgets('a one-month loan renders its schedule', (tester) async {
      final calc = calculatorById('mortgage')!;
      final r = calc.compute({...calc.defaults, 'tenor': 1.0}, rules);
      expect(r.error, isNull);
      await tester.pumpWidget(
        host(ScheduleScreen(result: r, title: 'Mortgage')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 35-year schedule renders without overflowing', (
      tester,
    ) async {
      final calc = calculatorById('mortgage')!;
      final r = calc.compute({...calc.defaults, 'tenor': 35.0}, rules);
      await tester.pumpWidget(
        host(ScheduleScreen(result: r, title: 'Mortgage')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every calculator builds in dark mode too', (tester) async {
      for (final calc in allCalculators) {
        await tester.pumpWidget(
          host(
            KeyedSubtree(
              key: ValueKey('dark-${calc.id}'),
              child: CalculatorScreen(calculator: calc, app: AppState()),
            ),
            dark: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: calc.id);
      }
    });

    testWidgets('a very long scenario name does not overflow Saved', (
      tester,
    ) async {
      final app = AppState();
      await app.init();
      await app.saveScenario(
        Scenario(
          id: 'long',
          calculatorId: 'mortgage',
          name: 'A' * 200,
          inputs: const {},
          savedAt: DateTime(2026, 9, 1),
          headlineLabel: 'MONTHLY INSTALMENT',
          headlineValue: 'S\$ 9,999,999.99',
        ),
      );
      await tester.pumpWidget(host(SavedTab(app: app)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Compare stays consistent as scenarios change', () {
    test('deleting a compared scenario drops it from the comparison', () async {
      final app = AppState();
      await app.init();
      await app.saveScenario(scn('a'));
      await app.saveScenario(scn('b'));
      app.toggleCompare('a');
      app.toggleCompare('b');
      expect(app.comparing, hasLength(2));

      await app.deleteScenario('a');
      expect(app.comparing, hasLength(1));
      expect(app.compareIds, isNot(contains('a')));
    });

    test('compare never holds more than three', () async {
      final app = AppState();
      await app.init();
      for (var i = 0; i < 6; i++) {
        await app.saveScenario(scn('x$i'));
        app.toggleCompare('x$i');
      }
      expect(app.compareIds.length, lessThanOrEqualTo(3));
    });

    testWidgets('comparing two scenarios with no saved inputs still renders', (
      tester,
    ) async {
      final app = AppState();
      await app.init();
      // Seeded examples carry inputs now, but a scenario saved by an older
      // build may not. It must fall back to defaults, not crash.
      await app.saveScenario(scn('bare1'));
      await app.saveScenario(scn('bare2'));
      app.toggleCompare('bare1');
      app.toggleCompare('bare2');

      await tester.pumpWidget(host(CompareTab(app: app)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('No calculator can be made to produce a silent wrong answer', () {
    test('extreme but legal inputs either compute or refuse, never NaN', () {
      final extremes = <String, List<Object>>{
        'money': [Money.zero, const Money(1), Money.tryParse('99999999')!],
        'number': [0.0, 0.01, 1.0, 99.0],
      };

      for (final calc in allCalculators) {
        for (final input in calc.inputs) {
          final pool = input.kind == InputKind.money
              ? extremes['money']!
              : extremes['number']!;
          for (final v in pool) {
            if (input.kind == InputKind.choice) continue;
            final values = {...calc.defaults, input.key: v};
            final r = calc.compute(values, rules);
            if (r.error != null) continue;
            expect(
              r.primaryValue,
              isNot(contains('NaN')),
              reason: '${calc.id}.${input.key} = $v',
            );
            expect(
              r.primaryValue,
              isNot(contains('Infinity')),
              reason: '${calc.id}.${input.key} = $v',
            );
            for (final m in r.secondary) {
              expect(
                m.value,
                isNot(contains('NaN')),
                reason: '${calc.id}.${input.key} = $v -> ${m.label}',
              );
              expect(
                m.value,
                isNot(contains('Infinity')),
                reason: '${calc.id}.${input.key} = $v -> ${m.label}',
              );
            }
          }
        }
      }
    });
  });
}

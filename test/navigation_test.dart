import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/registry.dart';
import 'package:basis/core/money.dart';
import 'package:basis/main.dart';
import 'package:basis/state.dart';
import 'package:basis/ui/components.dart';
import 'package:basis/ui/screens/calculator_screen.dart';
import 'package:basis/ui/screens/shell.dart';
import 'package:basis/ui/theme.dart';
import 'package:basis/ui/tour.dart';

/// Regression guard for a bug that only appeared on a real device in release.
///
/// BasisTheme used to wrap `home:`, which makes it a SIBLING of any pushed
/// route rather than an ancestor. Every pushed screen then failed its theme
/// lookup. In debug the assert fired; in release the assert is stripped, the
/// null check threw, and the route rendered as a blank grey screen.
///
/// These tests push real routes and assert they actually build.
void main() {
  testWidgets('pushed routes inherit BasisTheme', (tester) async {
    late BuildContext pushedContext;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BasisTheme(
          colors: BasisColors.light,
          isDark: false,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (ctx) {
                    pushedContext = ctx;
                    return Scaffold(
                      backgroundColor: ctx.c.ground,
                      body: Text('pushed', style: T.body),
                    );
                  },
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('pushed'), findsOneWidget);
    // The real assertion: the lookup resolves from inside the pushed route.
    expect(
      BasisTheme.of(pushedContext).colors.accent,
      BasisColors.light.accent,
    );
  });

  testWidgets('every calculator screen builds when pushed', (tester) async {
    final app = AppState();

    for (final calc in allCalculators) {
      await tester.pumpWidget(
        MaterialApp(
          // A fresh key per iteration, otherwise the Navigator keeps the
          // previously pushed route and the trigger is no longer reachable.
          key: ValueKey(calc.id),
          builder: (context, child) => BasisTheme(
            colors: BasisColors.light,
            isDark: false,
            child: child ?? const SizedBox.shrink(),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CalculatorScreen(calculator: calc, app: app),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: '${calc.id} threw while building',
      );
      expect(
        find.byType(CalculatorScreen),
        findsOneWidget,
        reason: '${calc.id} did not render',
      );
    }
  });

  testWidgets('category screens build for every question group', (
    tester,
  ) async {
    final app = AppState();

    for (final q in allCalculators.map((c) => c.question).toSet()) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(q.name),
          builder: (context, child) => BasisTheme(
            colors: BasisColors.dark,
            isDark: true,
            child: child ?? const SizedBox.shrink(),
          ),
          home: CategoryScreen(question: q, app: app),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${q.name} threw');
    }
  });

  testWidgets('the whole app boots and reaches the shell', (tester) async {
    await tester.pumpWidget(
      BasisApp(tourMemory: InMemoryTourMemory(seen: true)),
    );
    await tester.pump();
    // Splash hands off on a timer; let it run out.
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Shell), findsOneWidget);
    expect(find.text('What are you working out today?'), findsOneWidget);
  });

  testWidgets('mode switch hides the input it makes irrelevant', (
    tester,
  ) async {
    final calc = calculatorById('credit_card')!;
    // A phone-sized viewport, matching the device the layout bug was seen on.
    tester.view.physicalSize = const Size(1344, 2992);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BasisTheme(
          colors: BasisColors.light,
          isDark: false,
          child: child ?? const SizedBox.shrink(),
        ),
        home: CalculatorScreen(calculator: calc, app: AppState()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Monthly payment'), findsOneWidget);
    expect(find.text('Clear it within'), findsNothing);
    // Both options are on screen, not scrolled out of reach.
    expect(find.text('Pay a fixed amount').hitTestable(), findsOneWidget);

    await tester.ensureVisible(find.text('Clear it by a date'));
    await tester.tap(find.text('Clear it by a date'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Monthly payment'), findsNothing);
    expect(find.text('Clear it within'), findsOneWidget);
    expect(find.text('MONTHLY PAYMENT'), findsOneWidget);
    // Every figure is still seeded, so the badge must not claim LIVE.
    expect(find.text('EXAMPLE'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('clearing a field to zero keeps focus so a new number can be '
      'typed', (tester) async {
    final calc = calculatorById('credit_card')!;
    tester.view.physicalSize = const Size(1170, 2532); // iPhone, 390 x 844
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BasisTheme(
          colors: BasisColors.light,
          isDark: false,
          child: child ?? const SizedBox.shrink(),
        ),
        home: CalculatorScreen(calculator: calc, app: AppState()),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.descendant(
      of: find.byKey(const ValueKey('balance')),
      matching: find.byType(EditableText),
    );
    await tester.tap(field);
    await tester.pump();
    await tester.pump();
    final ctl = tester.widget<EditableText>(field).controller;
    expect(ctl.selection.start, 0);
    expect(ctl.selection.end, ctl.text.length,
        reason: 'tapping a figure should select all of it, so typing '
            'replaces it rather than editing from wherever the finger landed');

    // On the way to a new number the field passes through an invalid value.
    await tester.enterText(field, '0');
    await tester.pump();
    expect(find.text('Enter the balance on the card.'), findsOneWidget);
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue,
        reason: 'the error state rebuilt the inputs and closed the keyboard');

    await tester.enterText(field, '12000');
    await tester.pump();
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    expect(find.text('Enter the balance on the card.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save is visibly disabled while the inputs cannot compute',
      (tester) async {
    final calc = calculatorById('credit_card')!;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BasisTheme(
          colors: BasisColors.light,
          isDark: false,
          child: child ?? const SizedBox.shrink(),
        ),
        home: CalculatorScreen(calculator: calc, app: AppState()),
      ),
    );
    await tester.pumpAndSettle();
    SaveBar bar() => tester.widget<SaveBar>(find.byType(SaveBar));
    expect(bar().onSave, isNotNull);

    final field = find.descendant(
      of: find.byKey(const ValueKey('balance')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(field, '0');
    await tester.pump();
    expect(bar().onSave, isNull);
    expect(bar().onCompare, isNull);
  });

  testWidgets('OPEN on a saved scenario restores its inputs, not the example',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final app = AppState();
    await app.init();
    final calc = calculatorById('credit_card')!;
    final inputs = {
      ...calc.defaults,
      'balance': Money.tryParse('12000')!,
    };
    final r = calc.compute(inputs, app.rules);
    expect(r.primaryValue, '51 months');
    for (final s in List.of(app.scenarios)) {
      await app.deleteScenario(s.id);
    }
    await app.saveScenario(Scenario(
      id: 'mine',
      calculatorId: 'credit_card',
      name: 'Card test 12k',
      inputs: inputs,
      savedAt: DateTime.now(),
      headlineLabel: r.primaryLabel,
      headlineValue: r.primaryValue,
    ));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BasisTheme(
          colors: BasisColors.light,
          isDark: false,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(body: SavedTab(app: app)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    expect(find.byType(CalculatorScreen), findsOneWidget);
    expect(find.text('51 months'), findsOneWidget,
        reason: 'opened with the example balance instead of the saved one');
    expect(find.text('27 months'), findsNothing);
    expect(find.text('LIVE'), findsOneWidget,
        reason: 'saved figures belong to the user, not the example');
    expect(tester.takeException(), isNull);
  });
}

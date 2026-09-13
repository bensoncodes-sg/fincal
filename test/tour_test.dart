import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basis/main.dart';
import 'package:basis/ui/screens/calculator_screen.dart';
import 'package:basis/ui/screens/shell.dart';
import 'package:basis/ui/tour.dart';

/// The intro tour: shown once, walks every part of the app, and never leaves
/// the user stuck or looking at a spotlight on nothing.
void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532); // iPhone, 390 x 844
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// Advances time in small steps so the tour's delays, route transitions and
  /// scrolls all complete, without relying on pumpAndSettle.
  Future<void> settle(WidgetTester tester, [int steps = 14]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<TourController> launch(WidgetTester tester, TourMemory memory) async {
    phone(tester);
    await tester.pumpWidget(BasisApp(tourMemory: memory));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1800)); // splash
    await settle(tester, 20);
    final context = tester.element(find.byType(Shell));
    return TourScope.maybeOf(context)!;
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settle(tester);
  }

  testWidgets('first launch shows the tour, and Next walks the whole app', (
    tester,
  ) async {
    final memory = InMemoryTourMemory();
    final tour = await launch(tester, memory);

    expect(tour.isActive, isTrue);
    expect(find.text('Welcome to Basis'), findsOneWidget);
    expect(find.text('STEP 1 OF 10'), findsOneWidget);
    expect(find.text('Back'), findsNothing, reason: 'nothing to go back to');

    final seenPlaces = <TourPlace>{};
    for (var i = 0; i < kTourSteps.length; i++) {
      final step = kTourSteps[i];
      expect(tour.index, i);
      expect(find.text(step.title), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Every spotlight lands on the element it describes.
      if (step.target != null) {
        expect(
          tour.targetRect,
          isNotNull,
          reason: 'step ${i + 1} "${step.title}" found no ${step.target}',
        );
        final screen = Offset.zero & tester.view.physicalSize / 3;
        expect(
          screen.overlaps(tour.targetRect!),
          isTrue,
          reason: 'step ${i + 1} target is off screen',
        );
      }

      // And the right screen is showing.
      seenPlaces.add(step.place);
      expect(
        find.byType(CalculatorScreen),
        step.place == TourPlace.calculator ? findsOneWidget : findsNothing,
        reason: 'step ${i + 1}',
      );

      await tap(tester, i == 0 ? 'Show me' : (tour.isLast ? 'Done' : 'Next'));
    }

    expect(seenPlaces, TourPlace.values.toSet());
    expect(tour.isActive, isFalse);
    expect(await memory.hasSeen(), isTrue);
    expect(find.text('STEP 10 OF 10'), findsNothing);
  });

  testWidgets('Back from the calculator returns to Home', (tester) async {
    final tour = await launch(tester, InMemoryTourMemory());
    await tap(tester, 'Show me'); // 2
    await tap(tester, 'Next'); // 3
    await tap(tester, 'Next'); // 4: calculator
    expect(find.byType(CalculatorScreen), findsOneWidget);

    await tap(tester, 'Back');
    expect(tour.index, 2);
    expect(find.byType(CalculatorScreen), findsNothing);
    expect(find.text('Pick up where you left off'), findsOneWidget);
  });

  testWidgets('Skip ends the tour and it does not come back next launch', (
    tester,
  ) async {
    final memory = InMemoryTourMemory();
    final tour = await launch(tester, memory);
    await tap(tester, 'Skip');
    expect(tour.isActive, isFalse);
    expect(await memory.hasSeen(), isTrue);

    await tester.pumpWidget(const SizedBox());
    final again = await launch(tester, memory);
    expect(again.isActive, isFalse);
    expect(find.text('Welcome to Basis'), findsNothing);
  });

  testWidgets('the tour can be replayed from Settings', (tester) async {
    final tour = await launch(tester, InMemoryTourMemory(seen: true));
    expect(tour.isActive, isFalse);

    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tester.ensureVisible(find.text('Replay the app tour'));
    await settle(tester, 4);
    await tap(tester, 'Replay the app tour');

    expect(tour.isActive, isTrue);
    expect(tour.index, 0);
    expect(find.text('Welcome to Basis'), findsOneWidget);
  });

  testWidgets('the back button steps the tour back, not the screen', (
    tester,
  ) async {
    final tour = await launch(tester, InMemoryTourMemory());
    await tap(tester, 'Show me');
    await tap(tester, 'Next');
    await tap(tester, 'Next'); // calculator
    expect(tour.index, 3);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(tour.isActive, isTrue);
    expect(tour.index, 2);
  });

  testWidgets('taps outside the card do not reach the app underneath', (
    tester,
  ) async {
    final tour = await launch(tester, InMemoryTourMemory());
    // Where the Saved tab sits; the tour's dimmed layer is on top of it.
    await tester.tapAt(const Offset(130, 820));
    await settle(tester);
    expect(tour.isActive, isTrue);
    expect(find.text('Welcome to Basis'), findsOneWidget);
    expect(find.text('What are you working out today?'), findsOneWidget);
  });

  testWidgets('keyboard: right arrow goes next, left goes back, Escape skips', (
    tester,
  ) async {
    final memory = InMemoryTourMemory();
    final tour = await launch(tester, memory);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(tour.index, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester);
    expect(tour.index, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(tour.isActive, isFalse);
    expect(await memory.hasSeen(), isTrue);
  });

  testWidgets('tour card text has proper styling, not the no-Material '
      'fallback', (tester) async {
    await launch(tester, InMemoryTourMemory());
    final title = tester.widget<Text>(find.text('Welcome to Basis'));
    final style = DefaultTextStyle.of(
      tester.element(find.text('Welcome to Basis')),
    ).style.merge(title.style);
    expect(
      style.decoration,
      isNot(TextDecoration.underline),
      reason: 'yellow double underline means no Material ancestor',
    );
    expect(style.decorationColor, isNot(const Color(0xFFFFFF00)));
  });
}

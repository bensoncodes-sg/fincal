@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:basis/feedback.dart';
import 'package:basis/platform/scenario_store_web.dart';
import 'package:basis/state.dart';
import 'package:basis/storage.dart' as storage;

/// Browser persistence, run in real Chrome:
/// `flutter test --platform chrome test/web_storage_test.dart`.
void main() {
  setUp(() => web.window.localStorage.clear());

  Scenario sample(String id) => Scenario(
    id: id,
    calculatorId: 'mortgage',
    name: 'Test $id',
    inputs: const {'rate': 3.5},
    headlineLabel: 'MONTHLY',
    headlineValue: 'S\$ 1,000.00',
    savedAt: DateTime(2026, 9, 13),
  );

  test('the app picks the localStorage store on the web', () {
    // Through the same conditional export main.dart uses.
    expect(storage.createScenarioStore(), isA<LocalStorageScenarioStore>());
  });

  test(
    'saved scenarios survive a fresh store, as after a page reload',
    () async {
      final a = LocalStorageScenarioStore();
      expect(await a.hasBeenWritten(), isFalse);
      await a.save([sample('s1'), sample('s2')]);

      final b = LocalStorageScenarioStore();
      final loaded = await b.load();
      expect(loaded.map((s) => s.id), ['s1', 's2']);
      expect(await b.hasBeenWritten(), isTrue);
    },
  );

  test('deleting everything does not bring the examples back', () async {
    final a = LocalStorageScenarioStore();
    await a.save([]);
    final app = AppState(store: LocalStorageScenarioStore());
    await app.init();
    expect(app.scenarios, isEmpty);
  });

  test('one corrupt row does not lose the others', () async {
    final good = LocalStorageScenarioStore();
    await good.save([sample('ok')]);
    final raw = web.window.localStorage.getItem('basis.scenarios')!;
    web.window.localStorage.setItem(
      'basis.scenarios',
      raw.replaceFirst('[', '[{"nope":1},'),
    );
    final loaded = await LocalStorageScenarioStore().load();
    expect(loaded.map((s) => s.id), ['ok']);
  });

  test('garbage in storage degrades to empty, never a crash', () async {
    web.window.localStorage.setItem('basis.scenarios', '{not json');
    expect(await LocalStorageScenarioStore().load(), isEmpty);
  });

  test('feedback queues in localStorage and survives a reload', () async {
    final s = FeedbackService(store: FeedbackStore(), sink: LocalOnlySink());
    final outcome = await s.submit(
      FeedbackItem(
        id: 'f1',
        rulesetVersion: 'test',
        category: FeedbackCategory.values.first,
        message: 'Numbers look right',
        createdAt: DateTime(2026, 9, 13),
      ),
    );
    expect(outcome, isNot(FeedbackOutcome.rejected));
    final again = FeedbackService(
      store: FeedbackStore(),
      sink: LocalOnlySink(),
    );
    expect(await again.pending(), hasLength(1));
  });
}

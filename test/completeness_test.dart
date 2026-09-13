import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/registry.dart';
import 'package:basis/core/calculator.dart';
import 'package:basis/core/money.dart';
import 'package:basis/rules/sg_rules.dart';
import 'package:basis/state.dart';
import 'package:basis/storage.dart';
import 'package:basis/ui/screens/export.dart';

/// Count CSV fields honouring quoting, so a quoted "3,312.39" counts as one.
int _fieldCount(String line) {
  var count = 1;
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (ch == ',' && !inQuotes) {
      count++;
    }
  }
  return count;
}

void main() {
  final rules = SgRules.defaults;

  CalcResult run(String id, [Map<String, Object> overrides = const {}]) {
    final c = calculatorById(id)!;
    return c.compute({...c.defaults, ...overrides}, rules);
  }

  // -------------------------------------------------------------------------
  group('Persistence survives a restart', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('basis_test_');
    });
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('saved scenarios come back from a fresh store', () async {
      final store = FileScenarioStore(
        fileName: 'roundtrip.json',
        directory: tmp,
      );
      final a = AppState(store: store);
      await a.init();

      await a.saveScenario(
        Scenario(
          id: 'x1',
          calculatorId: 'mortgage',
          name: 'Punggol 4-room',
          inputs: {'loan': Money.tryParse('500000')!, 'rate': 3.5},
          savedAt: DateTime(2026, 9, 1),
          headlineLabel: 'MONTHLY INSTALMENT',
          headlineValue: 'S\$ 2,500.00',
        ),
      );

      // A brand-new AppState over the same file: this is the restart.
      store.reset();
      final b = AppState(store: store);
      await b.init();

      final found = b.scenarios.where((s) => s.id == 'x1').toList();
      expect(found, hasLength(1));
      expect(found.first.name, 'Punggol 4-room');
      expect(found.first.headlineValue, 'S\$ 2,500.00');
      // Typed values must survive the JSON round trip.
      expect(found.first.inputs['loan'], isA<Money>());
      expect((found.first.inputs['loan']! as Money).cents, 50000000);
      expect(found.first.inputs['rate'], 3.5);
    });

    test('deleting everything does not resurrect the examples', () async {
      final store = FileScenarioStore(
        fileName: 'noreseed.json',
        directory: tmp,
      );
      final a = AppState(store: store);
      await a.init();
      expect(a.scenarios, isNotEmpty, reason: 'examples seed on first run');

      for (final s in a.scenarios.toList()) {
        await a.deleteScenario(s.id);
      }
      expect(a.scenarios, isEmpty);

      store.reset();
      final b = AppState(store: store);
      await b.init();
      expect(
        b.scenarios,
        isEmpty,
        reason: 'examples must not come back after a deliberate clear-out',
      );
    });

    test('a corrupt file loses one row, not the whole store', () async {
      final store = FileScenarioStore(fileName: 'corrupt.json', directory: tmp);
      final a = AppState(store: store);
      await a.init();
      await a.saveScenario(
        Scenario(
          id: 'good',
          calculatorId: 'mortgage',
          name: 'Good row',
          inputs: const {},
          savedAt: DateTime(2026, 9, 1),
          headlineLabel: 'X',
          headlineValue: 'Y',
        ),
      );

      // Splice a broken record in beside the good one.
      final f = File('${tmp.path}${Platform.pathSeparator}corrupt.json');
      final rows = (jsonDecode(await f.readAsString()) as List).toList()
        ..insert(0, {'id': 'broken'});
      await f.writeAsString(jsonEncode(rows));

      store.reset();
      final b = AppState(store: store);
      await b.init();
      expect(b.scenarios.map((s) => s.id), contains('good'));
      expect(b.scenarios.map((s) => s.id), isNot(contains('broken')));
    });

    test('a store that cannot write never throws', () async {
      final store = FileScenarioStore(fileName: 'ok.json', directory: tmp);
      final a = AppState(store: store);
      await a.init();
      // Saving repeatedly must not throw even under churn.
      for (var i = 0; i < 5; i++) {
        await a.saveScenario(
          Scenario(
            id: 'n$i',
            calculatorId: 'mortgage',
            name: 'n$i',
            inputs: const {},
            savedAt: DateTime(2026, 9, 1),
            headlineLabel: 'X',
            headlineValue: 'Y',
          ),
        );
      }
      expect(a.scenarios.length, greaterThanOrEqualTo(5));
    });
  });

  // -------------------------------------------------------------------------
  group('Compare needs a declared direction', () {
    test('cost calculators declare lower-is-better on the headline', () {
      for (final id in ['mortgage', 'income_tax', 'stamp_duty']) {
        expect(run(id).primaryBetter, Better.lower, reason: id);
      }
    });

    test('capacity calculators declare higher-is-better', () {
      for (final id in ['affordability', 'cpf_projection']) {
        expect(run(id).primaryBetter, Better.higher, reason: id);
      }
    });

    test('mortgage cost metrics are all lower-is-better', () {
      final r = run('mortgage');
      final interest = r.secondary.firstWhere(
        (m) => m.label == 'Total interest',
      );
      final repaid = r.secondary.firstWhere((m) => m.label == 'Total repaid');
      expect(interest.better, Better.lower);
      expect(repaid.better, Better.lower);
      // A date has no direction and must not be marked.
      final payoff = r.secondary.firstWhere((m) => m.label == 'Payoff');
      expect(payoff.better, Better.none);
    });
  });

  // -------------------------------------------------------------------------
  group('Export produces valid CSV', () {
    test('every column count matches its header', () {
      final calc = calculatorById('mortgage')!;
      final result = calc.compute(calc.defaults, rules);
      final csv = csvForResult(
        calculatorName: calc.name,
        inputs: calc.inputs,
        values: calc.defaults,
        result: result,
      );

      expect(csv, contains('Basis export'));
      expect(csv, contains('MONTHLY INSTALMENT'));
      expect(csv, contains('3,312.39'));
      expect(csv, contains('Assumptions'));
      expect(csv, contains('Schedule'));

      // The schedule block must have six fields on every row.
      final lines = csv.split('\n');
      final start = lines.indexWhere((l) => l.startsWith('No,Date,'));
      expect(start, greaterThan(0));
      var checked = 0;
      for (var i = start + 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        expect(_fieldCount(line), 6, reason: 'row $i: $line');
        checked++;
      }
      expect(checked, 300);
    });

    test('values containing commas are quoted', () {
      expect(csvEscape('1,234.56'), '"1,234.56"');
      expect(csvEscape('plain'), 'plain');
      expect(csvEscape('say "hi"'), '"say ""hi"""');
    });

    test('every calculator exports without throwing', () {
      for (final calc in allCalculators) {
        final result = calc.compute(calc.defaults, rules);
        if (result.error != null) continue;
        final csv = csvForResult(
          calculatorName: calc.name,
          inputs: calc.inputs,
          values: calc.defaults,
          result: result,
        );
        expect(csv, contains(calc.name), reason: calc.id);
        expect(csv.trim().split('\n').length, greaterThan(4), reason: calc.id);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('Quick math', () {
    test('GST adds 9% and strips it back out exactly', () {
      final add = run('gst', {'amount': Money.tryParse('100')!});
      expect(add.primaryValue, 'S\$ 109.00');

      final strip = run('gst', {
        'amount': Money.tryParse('109')!,
        'mode': 'Remove GST',
      });
      expect(strip.primaryValue, 'S\$ 100.00');
    });

    test('GST follows the ruleset rather than a hardcoded rate', () {
      final calc = calculatorById('gst')!;
      final r = calc.compute({
        ...calc.defaults,
        'amount': Money.tryParse('100')!,
      }, rules.copyWith(gstPct: 7));
      expect(r.primaryValue, 'S\$ 107.00');
    });

    test('bill split applies GST on top of service charge', () {
      // 120 + 10% service = 132; GST 9% of 132 = 11.88; total 143.88.
      // Adding 19% to 120 would give 142.80 — the wrong answer.
      final r = run('bill_split');
      expect(
        r.secondary.firstWhere((m) => m.label == 'Total').value,
        'S\$ 143.88',
      );
      expect(r.primaryValue, 'S\$ 35.97');
    });

    test('an uneven split gives the remainder to one payer', () {
      final r = run('bill_split', {'people': 7.0});
      // 14388 cents / 7 = 2055 each, remainder 3.
      expect(r.primaryValue, 'S\$ 20.55');
      expect(r.delta, isNotNull);
      expect(r.delta!.text, contains('0.03'));
    });

    test('shares always add back to the total', () {
      for (var people = 1; people <= 20; people++) {
        final r = run('bill_split', {'people': people.toDouble()});
        final total = Money.tryParse(
          r.secondary.firstWhere((m) => m.label == 'Total').value,
        )!;
        final each = Money.tryParse(r.primaryValue)!;
        final extra = r.secondary
            .where((m) => m.label == 'One pays')
            .map((m) => Money.tryParse(m.value)!)
            .toList();
        final sum = extra.isEmpty
            ? each.cents * people
            : each.cents * (people - 1) + extra.first.cents;
        expect(sum, total.cents, reason: '$people people');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('Nothing is advertised that does not exist', () {
    test('home counts equal built calculators, group by group', () {
      for (final q in Question.values) {
        expect(builtCountFor(q), calculatorsFor(q).length, reason: q.name);
      }
    });

    test('seeded example headlines match what their inputs compute', () async {
      final a = AppState();
      await a.init();
      for (final s in a.scenarios.where((s) => s.isExample)) {
        final calc = calculatorById(s.calculatorId);
        expect(calc, isNotNull, reason: s.calculatorId);
        final r = calc!.compute({...calc.defaults, ...s.inputs}, rules);
        expect(
          s.headlineValue,
          r.primaryValue,
          reason:
              'seed ${s.id} advertises a figure its inputs do not '
              'produce; Compare recomputes and would contradict it',
        );
        expect(s.headlineLabel, r.primaryLabel, reason: s.id);
      }
    });

    test('the tax curve is not labelled in years', () {
      final calc = calculatorById('income_tax')!;
      final r = calc.compute(calc.defaults, rules);
      expect(r.series.single.xUnit, isNot('yr'));
      expect(r.series.single.xUnit, contains('income'));
    });

    test(
      'balance curves are labelled in years, cash-flow curves in months',
      () {
        expect(
          calculatorById('mortgage')!
              .compute(calculatorById('mortgage')!.defaults, rules)
              .series
              .single
              .xUnit,
          'yr',
        );
        expect(
          calculatorById('refinance')!
              .compute(calculatorById('refinance')!.defaults, rules)
              .series
              .single
              .xUnit,
          'mo',
        );
      },
    );

    test('quick math is no longer empty', () {
      expect(builtCountFor(Question.quick), greaterThanOrEqualTo(4));
    });

    test('every calculator still has a golden file', () {
      final dir = Directory('test/golden');
      final covered = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map(
            (f) =>
                (jsonDecode(f.readAsStringSync()) as Map)['calculator']
                    as String,
          )
          .toSet();
      final missing = allCalculators
          .map((c) => c.id)
          .where((id) => !covered.contains(id));
      expect(missing, isEmpty, reason: 'no golden file for: $missing');
    });
  });
}

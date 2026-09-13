import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/registry.dart';
import 'package:basis/core/calculator.dart';
import 'package:basis/core/money.dart';
import 'package:basis/rules/sg_rules.dart';

/// End-to-end checks on the calculator layer: declaration -> compute ->
/// formatted strings, exactly what the renderer puts on screen.
void main() {
  final rules = SgRules.defaults;

  CalcResult run(String id, [Map<String, Object> overrides = const {}]) {
    final c = calculatorById(id)!;
    return c.compute({...c.defaults, ...overrides}, rules);
  }

  group('Registry', () {
    test('every calculator has a unique id and at least one input', () {
      final ids = <String>{};
      for (final c in allCalculators) {
        expect(ids.add(c.id), isTrue, reason: 'duplicate id ${c.id}');
        expect(c.inputs, isNotEmpty, reason: '${c.id} has no inputs');
      }
    });

    test(
      'every calculator computes from its own defaults without throwing',
      () {
        for (final c in allCalculators) {
          final r = c.compute(c.defaults, rules);
          expect(r.primaryValue, isNotEmpty, reason: c.id);
        }
      },
    );

    test('home screen counts match what is actually built', () {
      var total = 0;
      for (final q in Question.values) {
        total += builtCountFor(q);
      }
      expect(total, allCalculators.length);
    });
  });

  group('Mortgage', () {
    test('headline figures match the verified schedule', () {
      final r = run('mortgage');
      expect(r.primaryValue, 'S\$ 3,312.39');
      expect(r.secondary[0].value, 'S\$ 356,215'); // total interest
      expect(r.secondary[1].value, 'S\$ 993,715'); // total repaid
      expect(r.secondary[2].value, '35.8%');
      expect(r.schedule.length, 300);
      expect(r.schedule.last.balance.cents, 0);
    });

    test('extra payment produces the verified saving', () {
      final r = run('mortgage', {'extra': Money.tryParse('500')!});
      expect(r.delta, isNotNull);
      expect(r.delta!.text, contains('78,548'));
      expect(r.delta!.text, contains('4y 11m'));
      expect(r.schedule.length, 241);
    });

    test('a zero loan reports instead of guessing', () {
      final r = run('mortgage', {'loan': Money.zero});
      expect(r.error, isNotNull);
      expect(r.primaryValue, '—');
    });
  });

  group('Affordability — TDSR and MSR', () {
    test('MSR binds for HDB when it is the tighter ceiling', () {
      final r = run('affordability');
      // 9,000 income, 600 debts: TDSR room 4,350 vs MSR room 2,700 -> MSR.
      expect(r.delta!.text, contains('MSR 30%'));
      expect(r.delta!.text, contains('S\$ 2,700'));
    });

    test('TDSR binds for private property', () {
      final r = run('affordability', {'type': 'Private'});
      expect(r.delta!.text, contains('TDSR 55%'));
      expect(r.delta!.text, contains('S\$ 4,350'));
    });

    test('debts above the TDSR ceiling refuse to produce a number', () {
      final r = run('affordability', {
        'type': 'Private',
        'debts': Money.tryParse('9000')!,
      });
      expect(r.error, isNotNull);
      expect(r.error, contains('TDSR'));
    });

    test('cash on hand can be the binding constraint', () {
      final r = run('affordability', {'cash': Money.tryParse('50000')!});
      expect(r.secondary.last.value, 'Cash on hand');
    });
  });

  group('HDB vs bank', () {
    test('HDB at 2.6% beats a 3.85% bank package', () {
      final r = run('hdb_vs_bank');
      expect(r.primaryValue, contains('HDB'));
      expect(r.secondary[0].value, 'S\$ 2,892.14');
      expect(r.secondary[1].value, 'S\$ 3,312.39');
      expect(r.delta!.text, contains('126,071.16'));
    });

    test('a cheaper bank rate flips the winner', () {
      final r = run('hdb_vs_bank', {'bankRate': 2.0});
      expect(r.primaryValue, contains('Bank'));
    });
  });

  group('Refinance', () {
    test('break-even is reported in whole months', () {
      final r = run('refinance');
      expect(r.error, isNull);
      expect(r.primaryValue, contains('months'));
      final months = int.parse(r.primaryValue.split(' ').first);
      expect(months, greaterThan(0));
      expect(months, lessThan(216));
    });

    test('a worse rate is refused rather than dressed up', () {
      final r = run('refinance', {'newRate': 5.5});
      expect(r.error, isNotNull);
      expect(r.error, contains('does not pay'));
    });
  });

  group('TVM', () {
    test('solves PMT to the Excel value', () {
      final r = run('tvm');
      expect(r.primaryLabel, 'PAYMENT');
      expect(r.primaryValue, 'S\$ 1,432.86');
    });

    test('solves RATE back to the input', () {
      final r = run('tvm', {'solve': 'RATE'});
      expect(r.primaryLabel, 'ANNUAL RATE');
      expect(r.primaryValue, startsWith('6.00'));
    });

    test('solves N back to the input term', () {
      final r = run('tvm', {'solve': 'N'});
      expect(r.primaryValue, contains('240.0'));
    });

    test('impossible signs produce a failure, not a number', () {
      final r = run('tvm', {
        'solve': 'N',
        'pv': Money.tryParse('200000')!,
        'pmt': Money.tryParse('1000')!,
      });
      expect(r.error, isNotNull);
    });
  });

  group('CPF projection', () {
    test('projects to 55 with balances in the right order', () {
      final r = run('cpf_projection');
      expect(r.primaryLabel, contains('55'));
      expect(r.error, isNull);
      expect(r.series.length, 3);
      // OA receives the largest allocation share before 55.
      final oa = Money.tryParse(r.secondary[0].value)!;
      final sa = Money.tryParse(r.secondary[1].value)!;
      expect(oa > sa, isTrue);
    });

    test('projecting backwards is refused', () {
      final r = run('cpf_projection', {'toAge': 25.0});
      expect(r.error, isNotNull);
    });

    test('allocation shares always sum to one', () {
      for (final age in [25, 40, 48, 53, 58, 63, 70]) {
        final a = rules.allocationForAge(age);
        expect(a.oa + a.sa + a.ma, closeTo(1.0, 1e-9), reason: 'age $age');
      }
    });
  });

  group('Income tax', () {
    test('progressive bands compute correctly at 120k', () {
      // Chargeable 120,000 - 18,000 reliefs = 102,000.
      // 0 on first 20k, 2% next 10k (200), 3.5% next 10k (350),
      // 7% next 40k (2,800), 11.5% on 22,000 (2,530) = 5,880.
      final r = run('income_tax');
      expect(r.primaryValue, 'S\$ 5,880.00');
      expect(r.secondary[0].value, 'S\$ 102,000');
      expect(r.secondary[3].value, 'S\$ 114,120');
    });

    test('no tax below the first threshold', () {
      final r = run('income_tax', {
        'income': Money.tryParse('20000')!,
        'reliefs': Money.zero,
      });
      expect(r.primaryValue, 'S\$ 0.00');
    });

    test('marginal rate is reported, not just the effective rate', () {
      final r = run('income_tax');
      expect(r.secondary[2].value, '11.5%');
    });

    test('reliefs are capped', () {
      final a = run('income_tax', {
        'income': Money.tryParse('300000')!,
        'reliefs': Money.tryParse('200000')!,
      });
      // Cap is 80,000, so chargeable floors at 220,000.
      expect(a.secondary[0].value, 'S\$ 220,000');
    });
  });

  group('Stamp duty', () {
    test('BSD on 850,000 uses the marginal bands', () {
      // 1% on 180k (1,800) + 2% on 180k (3,600) + 3% on 490k (14,700)
      // = 20,100.
      final r = run('stamp_duty');
      expect(r.secondary[0].value, 'S\$ 20,100.00');
      expect(r.primaryValue, 'S\$ 20,100.00');
    });

    test('ABSD applies from the second property for a citizen', () {
      final r = run('stamp_duty', {'count': 2.0});
      expect(r.secondary[1].label, contains('20%'));
      expect(r.secondary[1].value, 'S\$ 170,000');
      expect(r.primaryValue, 'S\$ 190,100.00');
    });

    test('a foreigner pays ABSD on the first property', () {
      final r = run('stamp_duty', {'profile': 'Foreigner'});
      expect(r.secondary[1].label, contains('60%'));
      expect(r.secondary[1].value, 'S\$ 510,000');
    });
  });

  group('Every result is presentable', () {
    test('explanations carry a formula and substituted values', () {
      for (final c in allCalculators) {
        final r = c.compute(c.defaults, rules);
        if (r.error != null) continue;
        expect(r.explain, isNotNull, reason: '${c.id} has no explanation');
        expect(r.explain!.formula, isNotEmpty, reason: c.id);
        expect(r.explain!.substituted, isNotEmpty, reason: c.id);
      }
    });

    test('no result shows more than four secondary metrics', () {
      for (final c in allCalculators) {
        final r = c.compute(c.defaults, rules);
        expect(r.secondary.length, lessThanOrEqualTo(4), reason: c.id);
      }
    });

    test('series always have at least two points when present', () {
      for (final c in allCalculators) {
        final r = c.compute(c.defaults, rules);
        for (final s in r.series) {
          expect(
            s.points.length,
            greaterThanOrEqualTo(2),
            reason: '${c.id} / ${s.name}',
          );
        }
      }
    });
  });
}

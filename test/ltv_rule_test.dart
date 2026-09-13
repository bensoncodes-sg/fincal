import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/registry.dart';
import 'package:basis/core/calculator.dart';
import 'package:basis/core/money.dart';
import 'package:basis/rules/sg_rules.dart';

/// Loan-to-value is not a flat 75%.
///
/// Full LTV needs BOTH a short-enough tenure and a loan that finishes by 65.
/// Applying 75% flat overstates the maximum price by roughly a quarter for
/// anyone borrowing later in life — which is the group least able to absorb
/// being told they can afford more than they can.
void main() {
  final rules = SgRules.defaults;

  CalcResult afford(Map<String, Object> overrides) {
    final c = calculatorById('affordability')!;
    return c.compute({...c.defaults, ...overrides}, rules);
  }

  String metric(CalcResult r, String label) =>
      r.secondary.firstWhere((m) => m.label == label).value;

  group('The rule itself', () {
    test('a short loan finishing before 65 keeps full LTV', () {
      final r = rules.ltvFor(age: 35, tenureYears: 25, isHdb: false);
      expect(r.ltv, rules.bankLtvPct);
      expect(r.reason, 'Full LTV');
    });

    test('finishing exactly at 65 still keeps full LTV', () {
      // The rule is "past 65", so landing on it is fine.
      final r = rules.ltvFor(age: 35, tenureYears: 30, isHdb: false);
      expect(r.ltv, rules.bankLtvPct);
    });

    test('finishing after 65 drops to the reduced LTV', () {
      final r = rules.ltvFor(age: 45, tenureYears: 25, isHdb: false);
      expect(r.ltv, rules.reducedLtvPct);
      expect(r.reason, contains('70'));
      expect(r.reason, contains('past 65'));
    });

    test('an over-long tenure drops it even for a young borrower', () {
      final r = rules.ltvFor(age: 25, tenureYears: 35, isHdb: false);
      expect(r.ltv, rules.reducedLtvPct);
      expect(r.reason, contains('Tenure over 30'));
    });

    test('HDB has the tighter tenure limit', () {
      // 30 years is fine for private but too long for HDB.
      expect(
        rules.ltvFor(age: 30, tenureYears: 30, isHdb: false).ltv,
        rules.bankLtvPct,
      );
      expect(
        rules.ltvFor(age: 30, tenureYears: 30, isHdb: true).ltv,
        rules.reducedLtvPct,
      );
    });

    test('both failures are reported together, not just the first', () {
      final r = rules.ltvFor(age: 50, tenureYears: 35, isHdb: false);
      expect(r.ltv, rules.reducedLtvPct);
      expect(r.reason, contains('Tenure over'));
      expect(r.reason, contains('85'));
    });

    test('the reduced LTV is materially lower, not a rounding nudge', () {
      expect(rules.reducedLtvPct, lessThan(rules.bankLtvPct - 15));
    });
  });

  group('Affordability applies it', () {
    test('a 35-year-old over 25 years gets full LTV', () {
      final r = afford({'age': 35.0, 'tenor': 25.0});
      expect(r.secondary.map((m) => m.label), contains('Limited by'));
      expect(
        r.explain!.assumptions
            .firstWhere((a) => a.label == 'Loan-to-value')
            .value,
        '75%',
      );
    });

    test('a 50-year-old over 25 years does not', () {
      // Ends at 75, well past the cut-off.
      final r = afford({'age': 50.0, 'tenor': 25.0});
      expect(r.secondary.map((m) => m.label), contains('LTV (reduced)'));
      expect(metric(r, 'LTV (reduced)'), '55%');
      expect(r.delta!.text, contains('LTV cut to 55%'));
    });

    test('the reduced LTV lowers the maximum price, and says why', () {
      final young = afford({'age': 35.0, 'tenor': 25.0});
      final older = afford({'age': 50.0, 'tenor': 25.0});

      final youngPrice = Money.tryParse(young.primaryValue)!;
      final olderPrice = Money.tryParse(older.primaryValue)!;
      expect(
        olderPrice < youngPrice,
        isTrue,
        reason: 'a loan running past 65 must not allow a higher price',
      );

      // The explanation must name the reason, not just show a smaller number.
      final basis = older.explain!.assumptions
          .firstWhere((a) => a.label == 'LTV basis')
          .value;
      expect(basis, contains('past 65'));
    });

    test('the loan end age is stated so the rule is checkable', () {
      final r = afford({'age': 42.0, 'tenor': 20.0});
      expect(
        r.explain!.assumptions
            .firstWhere((a) => a.label == 'Loan ends at age')
            .value,
        '62',
      );
    });

    test('every age and tenor combination still produces a usable result', () {
      for (final age in [25, 35, 45, 55, 65]) {
        for (final tenor in [5, 15, 25, 30, 35]) {
          final r = afford({
            'age': age.toDouble(),
            'tenor': tenor.toDouble(),
            'type': 'Private',
          });
          expect(r.error, isNull, reason: 'age $age, tenor $tenor');
          expect(
            Money.tryParse(r.primaryValue),
            isNotNull,
            reason: 'age $age, tenor $tenor',
          );
        }
      }
    });
  });
}

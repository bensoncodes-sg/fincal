import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/cpf_projection.dart';
import 'package:basis/calculators/registry.dart';
import 'package:basis/core/calculator.dart';
import 'package:basis/core/money.dart';
import 'package:basis/rules/sg_rules.dart';

/// The Basic Healthcare Sum and Full Retirement Sum are what separate a real
/// CPF projection from a compound-interest toy. These pin the ceilings and
/// the overflow order.
void main() {
  final rules = SgRules.defaults;

  CalcResult project(Map<String, Object> overrides) {
    final c = calculatorById('cpf_projection')!;
    return c.compute({...c.defaults, ...overrides}, rules);
  }

  String metric(CalcResult r, String label) =>
      r.secondary.firstWhere((m) => m.label == label).value;

  group('Basic Healthcare Sum', () {
    test('MediSave never finishes above the BHS', () {
      // A long, well-paid run pushes MA hard against the ceiling.
      final r = project({
        'age': 25.0,
        'salary': Money.tryParse('9000')!,
        'ma': Money.tryParse('40000')!,
        'toAge': 55.0,
        'growth': 3.0,
      });
      final ma = Money.tryParse(metric(r, 'MediSave'))!;
      expect(ma.asDouble, lessThanOrEqualTo(rules.cpfBasicHealthcareSum + 1));
    });

    test(
      'interest credited into MediSave is swept out, not left above the cap',
      () {
        // Before the sweep existed, interest pushed MA far past the BHS.
        final r = project({
          'age': 32.0,
          'salary': Money.tryParse('7000')!,
          'toAge': 55.0,
        });
        expect(metric(r, 'MediSave'), 'S\$ 79,000');
      },
    );

    test('the overflow is redistributed, never lost', () {
      // Capping MA must not reduce the total; it only moves money sideways.
      final capped = project({
        'age': 32.0,
        'salary': Money.tryParse('7000')!,
        'toAge': 55.0,
      });
      final total = Money.tryParse(capped.primaryValue)!;
      final parts = [
        Money.tryParse(metric(capped, 'Ordinary Account'))!,
        Money.tryParse(metric(capped, 'Special Account'))!,
        Money.tryParse(metric(capped, 'MediSave'))!,
      ];
      final sum = parts.fold<int>(0, (s, m) => s + m.cents);
      // Displayed figures are rounded to the dollar, so allow a few of them.
      expect((sum - total.cents).abs(), lessThan(300));
    });

    test('below the ceiling nothing overflows', () {
      final r = project({
        'age': 30.0,
        'salary': Money.tryParse('5000')!,
        'ma': Money.tryParse('8000')!,
        'toAge': 40.0,
        'growth': 0.0,
      });
      final ma = Money.tryParse(metric(r, 'MediSave'))!;
      expect(ma.asDouble, lessThan(rules.cpfBasicHealthcareSum));
    });
  });

  group('Full Retirement Sum and the Retirement Account', () {
    test('crossing 55 forms an RA and reports it instead of the SA', () {
      final r = project({
        'age': 50.0,
        'salary': Money.tryParse('8000')!,
        'oa': Money.tryParse('150000')!,
        'sa': Money.tryParse('120000')!,
        'ma': Money.tryParse('60000')!,
        'toAge': 60.0,
        'growth': 0.0,
      });
      expect(r.secondary.map((m) => m.label), contains('Retirement Account'));
      expect(
        r.secondary.map((m) => m.label),
        isNot(contains('Special Account')),
      );
      final ra = Money.tryParse(metric(r, 'Retirement Account'))!;
      // The RA is seeded up to the FRS and then grows on its own interest.
      expect(ra.asDouble, greaterThanOrEqualTo(rules.cpfFullRetirementSum));
    });

    test('below 55 there is no Retirement Account', () {
      final r = project({'age': 32.0, 'toAge': 55.0});
      expect(r.secondary.map((m) => m.label), contains('Special Account'));
      expect(
        r.secondary.map((m) => m.label),
        isNot(contains('Retirement Account')),
      );
    });

    test('the RA is formed from SA first, then OA', () {
      final a = Accounts(300000, 50000, 0, 0);
      formRetirementAccount(a, rules);
      // SA only had 50,000, so the balance of the FRS comes out of OA.
      expect(a.ra, closeTo(rules.cpfFullRetirementSum, 0.01));
      expect(a.sa, 0);
      expect(
        a.oa,
        closeTo(300000 - (rules.cpfFullRetirementSum - 50000), 0.01),
      );
    });

    test('an SA larger than the FRS leaves the remainder in OA', () {
      final a = Accounts(10000, 300000, 0, 0);
      formRetirementAccount(a, rules);
      expect(a.ra, closeTo(rules.cpfFullRetirementSum, 0.01));
      expect(a.sa, 0);
      expect(
        a.oa,
        closeTo(10000 + (300000 - rules.cpfFullRetirementSum), 0.01),
      );
    });

    test('contributions past the FRS land in OA, not the RA', () {
      final a = Accounts(
        0,
        0,
        rules.cpfBasicHealthcareSum,
        rules.cpfFullRetirementSum,
      );
      final before = a.oa;
      allocateContribution(a, 3000, 57, rules);
      expect(
        a.ra,
        closeTo(rules.cpfFullRetirementSum, 0.01),
        reason: 'RA is already at the FRS and must not grow from contributions',
      );
      expect(a.oa, greaterThan(before));
    });
  });

  group('Allocation and overflow order', () {
    test('a full MediSave sends its share to the SA below 55', () {
      final a = Accounts(0, 0, rules.cpfBasicHealthcareSum, 0);
      allocateContribution(a, 1000, 40, rules);
      expect(a.ma, closeTo(rules.cpfBasicHealthcareSum, 0.01));
      final share = rules.allocationForAge(40);
      // The SA receives its own share plus the whole MediSave overflow.
      expect(a.sa, closeTo(1000 * (share.sa + share.ma), 0.01));
    });

    test('every dollar contributed is placed somewhere', () {
      for (final age in [25, 40, 54, 56, 62, 68, 75]) {
        final a = Accounts(0, 0, 0, 0);
        allocateContribution(a, 1000, age, rules);
        expect(a.total, closeTo(1000, 0.01), reason: 'age $age');
      }
    });

    test('nothing is placed anywhere when the contribution is zero', () {
      final a = Accounts(1, 2, 3, 4);
      allocateContribution(a, 0, 40, rules);
      expect(a.total, closeTo(10, 1e-9));
    });
  });

  group('Extra interest', () {
    test('under 55 the bonus is capped at the first 60k combined', () {
      final small = Accounts(10000, 10000, 10000, 0);
      final large = Accounts(500000, 500000, 79000, 0);
      final rSmall = monthlyInterest(small, 40, rules);
      final rLarge = monthlyInterest(large, 40, rules);
      // Base interest scales with balance; the bonus does not.
      final bonusSmall =
          rSmall - (small.oa * 0.025 / 12 + (small.sa + small.ma) * 0.04 / 12);
      final bonusLarge =
          rLarge - (large.oa * 0.025 / 12 + (large.sa + large.ma) * 0.04 / 12);
      expect(bonusSmall, greaterThan(0));
      expect(bonusLarge, closeTo(60000 * 0.01 / 12, 0.01));
      expect(bonusLarge, greaterThan(bonusSmall));
    });

    test('the OA contributes at most 20k toward the bonus tier', () {
      final allOa = Accounts(100000, 0, 0, 0);
      final base = allOa.oa * 0.025 / 12;
      final bonus = monthlyInterest(allOa, 40, rules) - base;
      expect(bonus, closeTo(20000 * 0.01 / 12, 0.01));
    });

    test('from 55 the first 30k earns 2% extra', () {
      final a = Accounts(0, 0, 0, 30000);
      final base = 30000 * 0.04 / 12;
      final bonus = monthlyInterest(a, 60, rules) - base;
      expect(bonus, closeTo(30000 * 0.02 / 12, 0.01));
    });
  });
}

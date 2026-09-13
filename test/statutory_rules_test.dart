import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/registry.dart';
import 'package:basis/core/money.dart';
import 'package:basis/rules/sg_rules.dart';

void main() {
  test('CPF 2026 allocation bands match the official table', () {
    final r = SgRules.defaults;
    expect(r.allocationForAge(55), (oa: 0.4055, sa: 0.3108, ma: 0.2837));
    expect(r.allocationForAge(56), (oa: 0.353, sa: 0.3382, ma: 0.3088));
    expect(r.allocationForAge(61), (oa: 0.14, sa: 0.44, ma: 0.42));
    expect(r.allocationForAge(66), (oa: 0.0607, sa: 0.303, ma: 0.6363));
    expect(r.allocationForAge(71), (oa: 0.08, sa: 0.08, ma: 0.84));
  });

  test('CPF 2026 total contribution rates match official age bands', () {
    final r = SgRules.defaults;
    // "55 & below" is one band in the CPF table, so age 55 is 37%, not 34%.
    // This assertion previously read 34 and did not match the published table.
    expect(
      r.contributionForAge(55).employee + r.contributionForAge(55).employer,
      37,
    );
    expect(r.contributionForAge(55).employee, 20);
    expect(r.contributionForAge(55).employer, 17);
    expect(
      r.contributionForAge(56).employee + r.contributionForAge(56).employer,
      34,
    );
    expect(r.contributionForAge(56).employee, 18);
    expect(r.contributionForAge(56).employer, 16);
    expect(
      r.contributionForAge(61).employee + r.contributionForAge(61).employer,
      25,
    );
    expect(r.contributionForAge(61).employee, 12.5);
    // A swapped employee/employer split still sums to the right total, so the
    // shares are pinned individually. This caught exactly that on the 65-70
    // band, where the split was reversed.
    expect(
      r.contributionForAge(66).employee + r.contributionForAge(66).employer,
      16.5,
    );
    expect(r.contributionForAge(66).employee, 7.5);
    expect(r.contributionForAge(66).employer, 9);
    expect(
      r.contributionForAge(71).employee + r.contributionForAge(71).employer,
      12.5,
    );
    expect(r.contributionForAge(71).employee, 5);
  });

  test('income tax caps SRS before applying the relief calculation', () {
    final c = calculatorById('income_tax')!;
    final r = c.compute({
      ...c.defaults,
      'income': Money.tryParse('100000')!,
      'reliefs': Money.zero,
      'srs': Money.tryParse('50000')!,
    }, SgRules.defaults);
    expect(r.secondary.first.value, 'S\$ 84,700');
  });

  test('ABSD is rounded down to whole dollars', () {
    final c = calculatorById('stamp_duty')!;
    final r = c.compute({
      ...c.defaults,
      'price': Money.tryParse('850000.55')!,
      'profile': 'Foreigner',
    }, SgRules.defaults);
    expect(r.secondary[1].value, 'S\$ 510,000');
  });
}

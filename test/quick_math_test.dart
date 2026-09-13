import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/registry.dart';
import 'package:basis/core/calculator.dart';
import 'package:basis/core/finance.dart';
import 'package:basis/core/money.dart';
import 'package:basis/rules/sg_rules.dart';

void main() {
  CalcResult run(String id, [Map<String, Object> overrides = const {}]) {
    final c = calculatorById(id)!;
    return c.compute({...c.defaults, ...overrides}, SgRules.defaults);
  }

  test('Quick math is registered and percentage-of is exact', () {
    final r = run('percentage', {
      'a': Money.tryParse('200')!,
      'b': Money.tryParse('30')!,
    });
    expect(r.primaryValue, '15.00%');
    expect(r.error, isNull);
  });

  test('percentage change reports a decrease', () {
    final r = run('percentage', {
      'mode': 'Percentage change',
      'a': Money.tryParse('200')!,
      'b': Money.tryParse('150')!,
    });
    expect(r.primaryValue, '-25.00%');
    expect(r.secondary.first.value, 'Decrease');
  });

  test('Rule of 72 uses the stated estimate', () {
    final r = run('rule_72');
    expect(r.primaryValue, '12.0 years');
  });

  test('periodsFor handles payments at the beginning of a period', () {
    final end = periodsFor(pv: -1000, fv: 0, pmt: 100, ratePerPeriod: 0);
    final due = periodsFor(
      pv: -1000,
      fv: 0,
      pmt: 100,
      ratePerPeriod: 0,
      dueAtBeginning: true,
    );
    expect(end, 10);
    expect(due, 10);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:basis/core/finance.dart';
import 'package:basis/core/money.dart';

/// Cross-checks against a THIRD-PARTY app's published outputs (Bishinews
/// Financial Calculators, read off its own store screenshots).
///
/// This is the only oracle in the suite that was not produced by me, so it is
/// the only test here capable of catching a shared wrong assumption — a
/// convention I chose that happens to be wrong in the same way in my hand
/// working, my Node script and my Dart code.
void main() {
  test('their Loan Calculator: 150,000 @ 3.125% / 15y -> 1,044.91', () {
    final p = payment(
      principal: Money.tryParse('150000')!,
      annualRatePct: 3.125,
      months: 180,
    );
    expect(p.format(), '1,044.91');
  });

  test('the base loan runs exactly 180 payments, not 181', () {
    // Rounding the level instalment down to 1,044.91 under-amortises by a
    // few cents a month. Before the final-instalment fix this loan ran a
    // 181st period; the 25-year fixture happened to land clean and hid it.
    final a = amortize(
      principal: Money.tryParse('150000')!,
      annualRatePct: 3.125,
      months: 180,
      start: DateTime(2026, 1, 1),
    );
    expect(a.months, 180);
    expect(a.rows.last.balance.cents, 0);
    expect(a.totalPaid.cents - 15000000, a.totalInterest.cents);
    // Consistent with 180 instalments plus the final rounding adjustment.
    expect(a.totalPaid.asDouble, closeTo(180 * 1044.91, 2.0));
  });

  test('their extra-payment figures: 183,707.68 total after +100/month', () {
    // Their screen shows the base instalment beside the WITH-EXTRA totals.
    // 183,707.68 only reconciles once the 100/month extra is applied.
    final withExtra = amortize(
      principal: Money.tryParse('150000')!,
      annualRatePct: 3.125,
      months: 180,
      start: DateTime(2026, 1, 1),
      extra: Money.tryParse('100')!,
    );
    expect(withExtra.totalPaid.asDouble, closeTo(183707.68, 1.00));
    expect(withExtra.totalInterest.asDouble, closeTo(33707.68, 1.00));
  });

  test('their "payoff earlier by 19 months" reproduces', () {
    final base = amortize(
      principal: Money.tryParse('150000')!,
      annualRatePct: 3.125,
      months: 180,
      start: DateTime(2026, 1, 1),
    );
    final fast = amortize(
      principal: Money.tryParse('150000')!,
      annualRatePct: 3.125,
      months: 180,
      start: DateTime(2026, 1, 1),
      extra: Money.tryParse('100')!,
    );
    expect(base.months - fast.months, 19);
  });

  test('their TVM: PV -200,000, 6%, n=240 -> PMT 1,432.86', () {
    final v = paymentFor(pv: 200000, fv: 0, ratePerPeriod: 0.005, periods: 240);
    expect(Money.fromDouble(v).format(), '-1,432.86');
  });

  test('their Compound Interest: 10,000 + 1,000/mo at 2.125% for 12mo', () {
    // Their screen shows maturity 22,353.61, which only reconciles if the
    // monthly deposit lands at the BEGINNING of each period. Reproducing
    // their number tells us which convention they chose.
    final fv = futureValue(
      pv: -10000,
      pmt: -1000,
      ratePerPeriod: 0.02125 / 12,
      periods: 12,
      dueAtBeginning: true,
    );
    expect(Money.fromDouble(fv).format(), '22,353.61');
  });

  test('their APY: 2.125% nominal compounded monthly -> 2.1458%', () {
    final apy = (pow1p(0.02125 / 12, 12) - 1) * 100;
    expect(apy, closeTo(2.1458, 0.0001));
  });
}

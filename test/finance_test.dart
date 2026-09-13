import 'package:flutter_test/flutter_test.dart';

import 'package:basis/core/finance.dart';
import 'package:basis/core/money.dart';
import 'package:basis/core/solver.dart';

void main() {
  group('Money — integer cents, half-even rounding', () {
    test('parses and rejects', () {
      expect(Money.tryParse('1,234.56')!.cents, 123456);
      expect(Money.tryParse('S\$ 850,000')!.cents, 85000000);
      expect(Money.tryParse('-1234.5')!.cents, -123450);
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('abc'), isNull);
    });

    test('half-even rounding does not drift upward', () {
      expect(roundHalfEven(0.5), 0);
      expect(roundHalfEven(1.5), 2);
      expect(roundHalfEven(2.5), 2);
      expect(roundHalfEven(3.5), 4);
      expect(roundHalfEven(-0.5), 0);
    });

    test('decimal parsing uses half-even and normalizes cent carry', () {
      expect(Money.tryParse('1.005')!.cents, 100);
      expect(Money.tryParse('1.015')!.cents, 102);
      expect(Money.tryParse('1.999')!.cents, 200);
    });

    test('formats with grouping and tabular decimals', () {
      expect(const Money(331239).format(), '3,312.39');
      expect(const Money(99371457).format(), '993,714.57');
      expect(const Money(99371457).format(decimals: 0), '993,715');
      expect(const Money(331239).sgd, 'S\$ 3,312.39');
    });

    test('addition never loses a cent over 300 iterations', () {
      var total = Money.zero;
      for (var i = 0; i < 300; i++) {
        total = total + const Money(331239);
      }
      expect(total.cents, 331239 * 300);
    });
  });

  group('Mortgage — 637,500 @ 3.85% over 25 years', () {
    // Closed-form PMT verified by hand and against Excel:
    //   PMT(0.0385/12, 300, 637500) = 3312.39
    final principal = Money.tryParse('637500')!;
    const rate = 3.85;
    const months = 300;

    test('instalment matches the closed form', () {
      final p = payment(
        principal: principal,
        annualRatePct: rate,
        months: months,
      );
      expect(p.format(), '3,312.39');
    });

    test('schedule runs the full term and closes at exactly zero', () {
      final a = amortize(
        principal: principal,
        annualRatePct: rate,
        months: months,
        start: DateTime(2026, 10, 1),
      );
      expect(a.months, 300);
      expect(a.rows.last.balance.cents, 0);
      expect(a.rows.first.date.year, 2026);
      expect(a.rows.first.date.month, 10);
      // First payment Oct 2026 + 299 further months = Sep 2051.
      expect(a.payoffDate.year, 2051);
      expect(a.payoffDate.month, 9);
    });

    test('totals reconcile: interest = paid - principal', () {
      final a = amortize(
        principal: principal,
        annualRatePct: rate,
        months: months,
        start: DateTime(2026, 10, 1),
      );
      expect(a.totalPaid.cents - principal.cents, a.totalInterest.cents);
      expect(a.totalInterest.format(decimals: 0), '356,215');
      expect(a.totalPaid.format(decimals: 0), '993,715');
      expect(a.interestShare, closeTo(35.85, 0.01));
    });

    test('first row splits interest correctly', () {
      final a = amortize(
        principal: principal,
        annualRatePct: rate,
        months: months,
        start: DateTime(2026, 10, 1),
      );
      // 637,500 x 0.0385/12 = 2,045.3125 -> 2,045.31 half-even
      expect(a.rows[0].interest.format(), '2,045.31');
      expect(a.rows[0].principal.format(), '1,267.08');
      expect(a.rows[0].balance.format(), '636,232.92');
    });

    test('balance after 15 years', () {
      final a = amortize(
        principal: principal,
        annualRatePct: rate,
        months: months,
        start: DateTime(2026, 10, 1),
      );
      expect(a.balanceAfterYears(15).format(decimals: 0), '329,479');
    });

    test('extra 500/month shortens the term and cuts interest', () {
      final base = amortize(
        principal: principal,
        annualRatePct: rate,
        months: months,
        start: DateTime(2026, 10, 1),
      );
      final withExtra = amortize(
        principal: principal,
        annualRatePct: rate,
        months: months,
        start: DateTime(2026, 10, 1),
        extra: Money.tryParse('500')!,
      );
      expect(withExtra.months, 241);
      expect(base.months - withExtra.months, 59); // 4y 11m
      final saved = base.totalInterest - withExtra.totalInterest;
      expect(saved.format(decimals: 0), '78,548');
    });
  });

  group('Comparison set — same 637,500 principal, 25 years', () {
    final p = Money.tryParse('637500')!;
    Amortization run(double r) => amortize(
      principal: p,
      annualRatePct: r,
      months: 300,
      start: DateTime(2026, 10, 1),
    );

    test('HDB 2.6%', () {
      final a = run(2.6);
      expect(a.instalment.format(), '2,892.14');
      expect(a.totalInterest.format(decimals: 0), '230,143');
      expect(a.totalPaid.format(decimals: 0), '867,643');
    });

    test('Bank fixed 3.85%', () {
      final a = run(3.85);
      expect(a.instalment.format(), '3,312.39');
      expect(a.totalInterest.format(decimals: 0), '356,215');
    });

    test('Bank float 3.40%', () {
      final a = run(3.40);
      expect(a.instalment.format(), '3,157.39');
      expect(a.totalInterest.format(decimals: 0), '309,716');
      expect(a.totalPaid.format(decimals: 0), '947,216');
    });

    test('HDB is the cheapest of the three', () {
      final hdb = run(2.6), fixed = run(3.85), float = run(3.40);
      expect(hdb.totalPaid < float.totalPaid, isTrue);
      expect(hdb.totalPaid < fixed.totalPaid, isTrue);
      // Differences as displayed on the compare screen.
      // Deltas carry cents: subtracting two rounded columns can differ by
      // a dollar, so the app shows the exact difference instead.
      expect((float.totalInterest - hdb.totalInterest).format(), '79,572.49');
      expect((fixed.totalPaid - hdb.totalPaid).format(), '126,071.16');
    });
  });

  group('Time value of money — pinned to Excel', () {
    test('PMT(0.005, 240, 200000) = -1432.86', () {
      final v = paymentFor(
        pv: 200000,
        fv: 0,
        ratePerPeriod: 0.005,
        periods: 240,
      );
      expect(v, closeTo(-1432.862117, 1e-6));
    });

    test('FV(0.005, 240, -1432.86, 0) is approximately zero', () {
      final v = futureValue(
        pv: 200000,
        pmt: -1432.862117,
        ratePerPeriod: 0.005,
        periods: 240,
      );
      expect(v.abs(), lessThan(0.001));
    });

    test('PV round-trips against FV', () {
      final fv = futureValue(
        pv: -10000,
        pmt: 0,
        ratePerPeriod: 0.06,
        periods: 10,
      );
      final pv = presentValue(fv: fv, pmt: 0, ratePerPeriod: 0.06, periods: 10);
      expect(pv, closeTo(-10000, 1e-6));
    });

    test('NPER solves back to the input term', () {
      final n = periodsFor(
        pv: 200000,
        fv: 0,
        pmt: -1432.862117,
        ratePerPeriod: 0.005,
      );
      expect(n, closeTo(240, 0.01));
    });

    test('RATE converges back to 0.5% per month', () {
      final r = rateFor(pv: 200000, fv: 0, pmt: -1432.862117, periods: 240);
      expect(r.converged, isTrue);
      expect(r.value!, closeTo(0.005, 1e-6));
    });

    test('zero-rate paths do not divide by zero', () {
      expect(
        paymentFor(pv: 1200, fv: 0, ratePerPeriod: 0, periods: 12),
        closeTo(-100, 1e-9),
      );
      expect(
        futureValue(pv: 0, pmt: -100, ratePerPeriod: 0, periods: 12),
        closeTo(1200, 1e-9),
      );
    });
  });

  group('Cash-flow measures', () {
    test('IRR of [-100, 110] is exactly 10%', () {
      final r = irr([-100, 110]);
      expect(r.converged, isTrue);
      expect(r.value!, closeTo(0.10, 1e-9));
    });

    test('IRR of a four-period project', () {
      final r = irr([-1000, 400, 400, 400]);
      expect(r.converged, isTrue);
      // NPV at the solved rate must be zero.
      expect(npv(r.value!, [-1000, 400, 400, 400]).abs(), lessThan(1e-7));
    });

    test('IRR refuses flows with no sign change instead of guessing', () {
      final r = irr([100, 200, 300]);
      expect(r.converged, isFalse);
      expect(r.failure, contains('negative'));
    });

    test('NPV discounts from t=0', () {
      expect(npv(0.10, [0, 110]), closeTo(100, 1e-9));
      expect(npv(0.0, [-100, 50, 50]), closeTo(0, 1e-9));
    });

    test('MIRR sits between the finance and reinvestment rates', () {
      final r = mirr([-1000, 400, 400, 400], 0.05, 0.08);
      expect(r.converged, isTrue);
      expect(r.value!, greaterThan(0));
    });

    test('CAGR doubling over 10 years is 7.177%', () {
      expect(cagr(begin: 100, end: 200, years: 10), closeTo(7.17734625, 1e-7));
    });

    test('Rule of 72 approximation against the exact figure', () {
      final exact = doublingPeriods(8); // 8% per period
      expect(exact, closeTo(9.006468, 1e-5));
      expect(72 / 8, 9.0); // the approximation the app shows alongside
    });
  });

  group('Solver honesty', () {
    test('reports failure rather than returning a plausible number', () {
      final r = solveRoot((x) => x * x + 1, lo: -1, hi: 1);
      expect(r.converged, isFalse);
      expect(r.failure, isNotNull);
    });

    test('finds a root that Newton alone would miss', () {
      final r = solveRoot(
        (x) => (x - 0.42) * (x * x + 1),
        guess: 8.5,
        lo: -0.9,
        hi: 9.0,
      );
      expect(r.converged, isTrue);
      expect(r.value!, closeTo(0.42, 1e-4));
    });
  });

  group('Edge cases that break naive implementations', () {
    test('zero interest loan splits evenly', () {
      final a = amortize(
        principal: const Money(120000),
        annualRatePct: 0,
        months: 12,
        start: DateTime(2026, 1, 1),
      );
      expect(a.instalment.cents, 10000);
      expect(a.totalInterest.cents, 0);
      expect(a.rows.last.balance.cents, 0);
    });

    test('one-month loan closes immediately', () {
      final a = amortize(
        principal: const Money(100000),
        annualRatePct: 6,
        months: 1,
        start: DateTime(2026, 1, 1),
      );
      expect(a.months, 1);
      expect(a.rows.last.balance.cents, 0);
    });

    test('month arithmetic clamps to the end of short months', () {
      final d = addMonths(DateTime(2026, 1, 31), 1);
      expect(d.month, 2);
      expect(d.day, 28);
    });
  });
}

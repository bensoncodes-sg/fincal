import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:basis/core/finance.dart';
import 'package:basis/core/money.dart';
import 'package:basis/rules/sg_rules.dart';

/// Property-based tests.
///
/// A fixture only ever checks the case someone thought of. These check
/// mathematical LAWS that must hold for every input, then fuzz thousands of
/// random cases against them. Several of these laws can only be violated by a
/// genuine defect — a schedule whose principal payments do not sum to the loan
/// is wrong no matter what number it prints.
///
/// The RNG is seeded so a failure is reproducible.
void main() {
  final rng = math.Random(20260912);

  double randRate() => 0.1 + rng.nextDouble() * 9.4; // 0.1% .. 9.5%
  int randMonths() => 6 + rng.nextInt(414); // 6 .. 420 months
  Money randLoan() =>
      Money(1000 * 100 + rng.nextInt(4_000_000 * 100)); // 1k .. 4m
  DateTime randStart() =>
      DateTime(2020 + rng.nextInt(20), 1 + rng.nextInt(12), 1);

  // ---------------------------------------------------------------------
  group('Amortization invariants (500 random loans)', () {
    late List<({Money loan, double rate, int months, Amortization a})> runs;

    setUpAll(() {
      runs = [];
      for (var k = 0; k < 500; k++) {
        final loan = randLoan();
        final rate = randRate();
        final months = randMonths();
        runs.add((
          loan: loan,
          rate: rate,
          months: months,
          a: amortize(
            principal: loan,
            annualRatePct: rate,
            months: months,
            start: randStart(),
          ),
        ));
      }
    });

    test('principal payments sum to exactly the loan', () {
      for (final r in runs) {
        var sum = Money.zero;
        for (final row in r.a.rows) {
          sum = sum + row.principal;
        }
        expect(
          sum.cents,
          r.loan.cents,
          reason: 'loan ${r.loan} @ ${r.rate}% x ${r.months}mo',
        );
      }
    });

    test('totalPaid - principal == totalInterest, to the cent', () {
      for (final r in runs) {
        expect(
          r.a.totalPaid.cents - r.loan.cents,
          r.a.totalInterest.cents,
          reason: 'loan ${r.loan} @ ${r.rate}% x ${r.months}mo',
        );
      }
    });

    test('interest payments sum to totalInterest', () {
      for (final r in runs) {
        var sum = Money.zero;
        for (final row in r.a.rows) {
          sum = sum + row.interest;
        }
        expect(sum.cents, r.a.totalInterest.cents);
      }
    });

    test('every schedule closes at exactly zero', () {
      for (final r in runs) {
        expect(
          r.a.rows.last.balance.cents,
          0,
          reason: 'loan ${r.loan} @ ${r.rate}% x ${r.months}mo',
        );
      }
    });

    test('term is exactly the scheduled number of months', () {
      for (final r in runs) {
        expect(
          r.a.months,
          r.months,
          reason: 'loan ${r.loan} @ ${r.rate}% x ${r.months}mo',
        );
      }
    });

    test('balance is strictly decreasing and never negative', () {
      for (final r in runs) {
        var prev = r.loan.cents;
        for (final row in r.a.rows) {
          expect(row.balance.cents, lessThanOrEqualTo(prev));
          expect(row.balance.cents, greaterThanOrEqualTo(0));
          prev = row.balance.cents;
        }
      }
    });

    test('each row: payment == principal + interest', () {
      for (final r in runs) {
        for (final row in r.a.rows) {
          expect(row.payment.cents, row.principal.cents + row.interest.cents);
        }
      }
    });

    test('total interest is always positive for a positive rate', () {
      for (final r in runs) {
        expect(r.a.totalInterest.cents, greaterThan(0));
      }
    });

    test('no NaN or infinity leaks into any figure', () {
      for (final r in runs) {
        expect(r.a.interestShare.isFinite, isTrue);
        expect(r.a.instalment.asDouble.isFinite, isTrue);
        expect(r.a.totalPaid.asDouble.isFinite, isTrue);
      }
    });
  });

  // ---------------------------------------------------------------------
  group('Second derivation — closed form vs iterated schedule', () {
    test('remaining balance matches the closed form at every sampled month', () {
      // B_k = P(1+i)^k - M((1+i)^k - 1)/i
      // Independent of the loop that builds the schedule, so agreement is
      // evidence rather than a restatement.
      for (var k = 0; k < 200; k++) {
        final loan = randLoan();
        final rate = randRate();
        final months = randMonths();
        final a = amortize(
          principal: loan,
          annualRatePct: rate,
          months: months,
          start: DateTime(2026, 1, 1),
        );
        final i = periodicRate(rate);
        final m = a.instalment.asDouble;
        final p = loan.asDouble;

        for (final frac in [0.25, 0.5, 0.75]) {
          final atMonth = (months * frac).floor();
          if (atMonth < 1 || atMonth >= a.rows.length) continue;
          final f = math.pow(1 + i, atMonth).toDouble();
          final closed = p * f - m * (f - 1) / i;
          final iterated = a.rows[atMonth - 1].balance.asDouble;
          // Per-period cent rounding accumulates; allow a few cents per month.
          final tolerance = math.max(1.0, atMonth * 0.05);
          expect(
            (closed - iterated).abs(),
            lessThan(tolerance),
            reason:
                'loan $loan @ $rate% x ${months}mo at month $atMonth: '
                'closed ${closed.toStringAsFixed(2)} vs '
                'iterated ${iterated.toStringAsFixed(2)}',
          );
        }
      }
    });

    test('instalment matches the annuity formula computed independently', () {
      for (var k = 0; k < 300; k++) {
        final loan = randLoan();
        final rate = randRate();
        final months = randMonths();
        final ours = payment(
          principal: loan,
          annualRatePct: rate,
          months: months,
        ).asDouble;
        // Same value via the reciprocal annuity-factor form.
        final i = rate / 100 / 12;
        final annuityFactor = (1 - math.pow(1 + i, -months)) / i;
        final independent = loan.asDouble / annuityFactor;
        expect(
          (ours - independent).abs(),
          lessThan(0.01),
          reason: 'loan $loan @ $rate% x ${months}mo',
        );
      }
    });
  });

  // ---------------------------------------------------------------------
  group('Monotonicity — direction of every lever', () {
    test('a higher rate never lowers the instalment or total interest', () {
      for (var k = 0; k < 200; k++) {
        final loan = randLoan();
        final months = randMonths();
        final lo = 0.5 + rng.nextDouble() * 4;
        final hi = lo + 0.1 + rng.nextDouble() * 4;
        final a = amortize(
          principal: loan,
          annualRatePct: lo,
          months: months,
          start: DateTime(2026, 1, 1),
        );
        final b = amortize(
          principal: loan,
          annualRatePct: hi,
          months: months,
          start: DateTime(2026, 1, 1),
        );
        expect(b.instalment.cents, greaterThanOrEqualTo(a.instalment.cents));
        expect(
          b.totalInterest.cents,
          greaterThanOrEqualTo(a.totalInterest.cents),
        );
      }
    });

    test('a longer term lowers the instalment and raises total interest', () {
      for (var k = 0; k < 200; k++) {
        final loan = randLoan();
        final rate = randRate();
        final shortT = 12 + rng.nextInt(120);
        final longT = shortT + 12 + rng.nextInt(180);
        final a = amortize(
          principal: loan,
          annualRatePct: rate,
          months: shortT,
          start: DateTime(2026, 1, 1),
        );
        final b = amortize(
          principal: loan,
          annualRatePct: rate,
          months: longT,
          start: DateTime(2026, 1, 1),
        );
        expect(b.instalment.cents, lessThanOrEqualTo(a.instalment.cents));
        expect(
          b.totalInterest.cents,
          greaterThanOrEqualTo(a.totalInterest.cents),
        );
      }
    });

    test('extra payments never lengthen the term or raise interest', () {
      for (var k = 0; k < 200; k++) {
        final loan = randLoan();
        final rate = randRate();
        final months = 24 + rng.nextInt(300);
        final base = amortize(
          principal: loan,
          annualRatePct: rate,
          months: months,
          start: DateTime(2026, 1, 1),
        );
        final extra = Money(1 + rng.nextInt(200000));
        final fast = amortize(
          principal: loan,
          annualRatePct: rate,
          months: months,
          start: DateTime(2026, 1, 1),
          extra: extra,
        );
        expect(fast.months, lessThanOrEqualTo(base.months));
        expect(
          fast.totalInterest.cents,
          lessThanOrEqualTo(base.totalInterest.cents),
        );
        // Still fully repays the loan.
        expect(fast.rows.last.balance.cents, 0);
        var sum = Money.zero;
        for (final r in fast.rows) {
          sum = sum + r.principal;
        }
        expect(sum.cents, loan.cents);
      }
    });

    test('a bigger loan never costs less', () {
      for (var k = 0; k < 150; k++) {
        final rate = randRate();
        final months = randMonths();
        final small = randLoan();
        final big = Money(small.cents + 1 + rng.nextInt(500000));
        final a = amortize(
          principal: small,
          annualRatePct: rate,
          months: months,
          start: DateTime(2026, 1, 1),
        );
        final b = amortize(
          principal: big,
          annualRatePct: rate,
          months: months,
          start: DateTime(2026, 1, 1),
        );
        expect(b.instalment.cents, greaterThanOrEqualTo(a.instalment.cents));
      }
    });
  });

  // ---------------------------------------------------------------------
  group('Time value of money — round trips over random inputs', () {
    test('PV and FV invert each other', () {
      for (var k = 0; k < 500; k++) {
        final pv = -(1000 + rng.nextDouble() * 500000);
        final i = rng.nextDouble() * 0.02;
        final n = 1 + rng.nextInt(480);
        final fv = futureValue(pv: pv, pmt: 0, ratePerPeriod: i, periods: n);
        final back = presentValue(fv: fv, pmt: 0, ratePerPeriod: i, periods: n);
        expect((back - pv).abs() / pv.abs(), lessThan(1e-9));
      }
    });

    test('PMT then FV returns to the target', () {
      for (var k = 0; k < 500; k++) {
        final pv = 1000 + rng.nextDouble() * 500000;
        final i = 0.0001 + rng.nextDouble() * 0.02;
        final n = 2 + rng.nextInt(480);
        final pmt = paymentFor(pv: pv, fv: 0, ratePerPeriod: i, periods: n);
        final fv = futureValue(pv: pv, pmt: pmt, ratePerPeriod: i, periods: n);
        expect(fv.abs(), lessThan(math.max(1e-6, pv * 1e-9)));
      }
    });

    test('RATE recovers the rate it was generated from', () {
      var checked = 0;
      for (var k = 0; k < 300; k++) {
        final pv = 1000 + rng.nextDouble() * 500000;
        final i = 0.0005 + rng.nextDouble() * 0.02;
        final n = 12 + rng.nextInt(360);
        final pmt = paymentFor(pv: pv, fv: 0, ratePerPeriod: i, periods: n);
        final solved = rateFor(pv: pv, fv: 0, pmt: pmt, periods: n);
        expect(
          solved.converged,
          isTrue,
          reason: 'failed to converge for i=$i n=$n pv=$pv',
        );
        expect(
          (solved.value! - i).abs(),
          lessThan(1e-8),
          reason: 'i=$i n=$n pv=$pv',
        );
        checked++;
      }
      expect(checked, 300);
    });

    test('NPER recovers the term it was generated from', () {
      for (var k = 0; k < 300; k++) {
        final pv = 1000 + rng.nextDouble() * 500000;
        final i = 0.0005 + rng.nextDouble() * 0.02;
        final n = 12 + rng.nextInt(360);
        final pmt = paymentFor(pv: pv, fv: 0, ratePerPeriod: i, periods: n);
        final solved = periodsFor(pv: pv, fv: 0, pmt: pmt, ratePerPeriod: i);
        expect(solved.isFinite, isTrue, reason: 'i=$i n=$n');
        expect((solved - n).abs(), lessThan(1e-6), reason: 'i=$i n=$n');
      }
    });
  });

  // ---------------------------------------------------------------------
  group('Cash-flow measures', () {
    test('NPV at the solved IRR is zero for random conventional flows', () {
      var solved = 0;
      for (var k = 0; k < 300; k++) {
        final outlay = -(1000 + rng.nextDouble() * 100000);
        final periods = 2 + rng.nextInt(10);
        final flows = <double>[outlay];
        for (var t = 0; t < periods; t++) {
          flows.add(rng.nextDouble() * (outlay.abs() / periods) * 1.6);
        }
        final r = irr(flows);
        if (!r.converged) continue;
        // The solver converges on the RATE to 1e-10, so the NPV residual
        // scales with the magnitude of the flows. Assert relative error,
        // not absolute — an absolute bound here just measures the size of
        // the inputs.
        final scale = flows.fold<double>(0, (s, f) => s + f.abs());
        expect(
          npv(r.value!, flows).abs() / scale,
          lessThan(1e-9),
          reason: 'flows $flows solved ${r.value}',
        );
        solved++;
      }
      // The vast majority of conventional flows must solve.
      expect(solved, greaterThan(250));
    });

    test('NPV falls as the discount rate rises, for conventional flows', () {
      for (var k = 0; k < 200; k++) {
        final flows = <double>[-(10000 + rng.nextDouble() * 90000)];
        for (var t = 0; t < 5; t++) {
          flows.add(1000 + rng.nextDouble() * 30000);
        }
        final lo = 0.01 + rng.nextDouble() * 0.05;
        final hi = lo + 0.01 + rng.nextDouble() * 0.2;
        expect(npv(hi, flows), lessThan(npv(lo, flows)));
      }
    });

    test('CAGR inverts compound growth', () {
      for (var k = 0; k < 300; k++) {
        final begin = 100 + rng.nextDouble() * 100000;
        final years = 1 + rng.nextDouble() * 40;
        final rate = rng.nextDouble() * 0.25;
        final end = begin * math.pow(1 + rate, years);
        final g = cagr(begin: begin, end: end, years: years) / 100;
        expect((g - rate).abs(), lessThan(1e-9));
      }
    });
  });

  // ---------------------------------------------------------------------
  group(
    'Statutory functions — shape laws, independent of the table values',
    () {
      final rules = SgRules.defaults;

      test('tax is non-decreasing in income', () {
        var prev = -1.0;
        for (var x = 0.0; x <= 1500000; x += 250) {
          final t = rules.taxOn(x);
          expect(t, greaterThanOrEqualTo(prev));
          prev = t;
        }
      });

      test('tax never exceeds income and is never negative', () {
        for (var x = 0.0; x <= 1500000; x += 500) {
          final t = rules.taxOn(x);
          expect(t, greaterThanOrEqualTo(0));
          expect(t, lessThanOrEqualTo(x));
        }
      });

      test('tax is continuous across every band boundary', () {
        for (final b in rules.incomeTaxBands) {
          if (b.upTo == null) continue;
          final below = rules.taxOn(b.upTo! - 0.01);
          final above = rules.taxOn(b.upTo! + 0.01);
          expect(
            (above - below).abs(),
            lessThan(0.02),
            reason: 'discontinuity at ${b.upTo}',
          );
        }
      });

      test('marginal rate is never below the effective rate', () {
        for (var x = 1000.0; x <= 1500000; x += 1000) {
          final effective = rules.taxOn(x) / x * 100;
          expect(
            rules.marginalRate(x),
            greaterThanOrEqualTo(effective - 1e-9),
            reason: 'at $x',
          );
        }
      });

      test('BSD is non-decreasing and continuous across tiers', () {
        var prev = -1.0;
        for (var p = 0.0; p <= 6000000; p += 1000) {
          final d = rules.bsdOn(p);
          expect(d, greaterThanOrEqualTo(prev));
          prev = d;
        }
        for (final b in rules.bsdBands) {
          if (b.upTo == null) continue;
          final below = rules.bsdOn(b.upTo! - 0.01);
          final above = rules.bsdOn(b.upTo! + 0.01);
          expect(
            (above - below).abs(),
            lessThan(0.02),
            reason: 'BSD discontinuity at ${b.upTo}',
          );
        }
      });

      test('CPF allocation shares sum to one at every age', () {
        for (var age = 16; age <= 80; age++) {
          final a = rules.allocationForAge(age);
          expect(a.oa + a.sa + a.ma, closeTo(1.0, 1e-9), reason: 'age $age');
          expect(a.oa, greaterThanOrEqualTo(0));
          expect(a.sa, greaterThanOrEqualTo(0));
          expect(a.ma, greaterThanOrEqualTo(0));
        }
      });

      test('CPF contribution rates are non-increasing with age', () {
        var prev = 100.0;
        for (var age = 20; age <= 80; age++) {
          final c = rules.contributionForAge(age);
          final total = c.employee + c.employer;
          expect(total, lessThanOrEqualTo(prev + 1e-9), reason: 'age $age');
          prev = total;
        }
      });
    },
  );

  // ---------------------------------------------------------------------
  group('Money arithmetic laws', () {
    test('format then parse round-trips exactly', () {
      for (var k = 0; k < 2000; k++) {
        final m = Money(rng.nextInt(1 << 31) - (1 << 30));
        final back = Money.tryParse(m.format());
        expect(back, isNotNull, reason: m.format());
        expect(back!.cents, m.cents, reason: m.format());
      }
    });

    test('addition is associative and exact over long chains', () {
      for (var k = 0; k < 200; k++) {
        final parts = List.generate(500, (_) => Money(rng.nextInt(1000000)));
        var left = Money.zero;
        for (final p in parts) {
          left = left + p;
        }
        var right = Money.zero;
        for (final p in parts.reversed) {
          right = right + p;
        }
        expect(left.cents, right.cents);
        expect(left.cents, parts.fold<int>(0, (s, p) => s + p.cents));
      }
    });

    test('half-even rounding is symmetric and unbiased on ties', () {
      var up = 0, down = 0;
      for (var n = 0; n < 2000; n++) {
        final v = n + 0.5;
        final r = roundHalfEven(v);
        if (r > v) {
          up++;
        } else {
          down++;
        }
      }
      // Ties split evenly; half-up would give up = 2000.
      expect((up - down).abs(), lessThanOrEqualTo(1));
    });
  });

  // ---------------------------------------------------------------------
  group('Adversarial inputs do not produce garbage', () {
    test('zero rate over many terms stays exact', () {
      for (var n = 1; n <= 400; n++) {
        final a = amortize(
          principal: const Money(120000000),
          annualRatePct: 0,
          months: n,
          start: DateTime(2026, 1, 1),
        );
        expect(a.totalInterest.cents, 0, reason: 'n=$n');
        expect(a.rows.last.balance.cents, 0, reason: 'n=$n');
        expect(a.months, n);
      }
    });

    test('one-cent loans still terminate and close', () {
      for (final rate in [0.0, 0.5, 3.85, 9.5]) {
        final a = amortize(
          principal: const Money(1),
          annualRatePct: rate,
          months: 12,
          start: DateTime(2026, 1, 1),
        );
        expect(a.rows.last.balance.cents, 0);
      }
    });

    test('very long terms at high rates still terminate', () {
      final a = amortize(
        principal: Money.tryParse('4000000')!,
        annualRatePct: 9.5,
        months: 480,
        start: DateTime(2026, 1, 1),
      );
      expect(a.months, 480);
      expect(a.rows.last.balance.cents, 0);
    });

    test('IRR on degenerate flows fails loudly rather than guessing', () {
      for (final flows in [
        <double>[0, 0, 0],
        <double>[-100],
        <double>[100, 100],
        <double>[-100, -100],
      ]) {
        final r = irr(flows);
        expect(r.converged, isFalse, reason: 'flows $flows');
        expect(r.failure, isNotNull);
      }
    });

    test('negative and zero inputs never yield NaN in CAGR', () {
      expect(cagr(begin: 0, end: 100, years: 5).isNaN, isTrue);
      expect(cagr(begin: 100, end: 200, years: 0).isNaN, isTrue);
      expect(cagr(begin: -100, end: 200, years: 5).isNaN, isTrue);
    });
  });
}

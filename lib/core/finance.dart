/// Core financial primitives.
///
/// Conventions, stated once and applied everywhere:
///   * Monthly rate is the NOMINAL annual rate divided by 12. This is what
///     Singapore banks quote and use; it is NOT (1+r)^(1/12)-1.
///   * Schedules run in integer cents and the final instalment is balanced
///     so the closing balance is exactly zero.
///   * Interest each period is rounded half-even to the cent before the
///     principal split, the way a bank ledger posts it.
library;

import 'dart:math' as math;

import 'money.dart';
import 'solver.dart';

export 'solver.dart' show SolveResult, pow1p, kTolerance, kMaxIterations;

/// Nominal annual percentage -> periodic decimal rate.
double periodicRate(double annualPct, {int periodsPerYear = 12}) =>
    annualPct / 100 / periodsPerYear;

/// Level instalment for a fully amortising loan.
Money payment({
  required Money principal,
  required double annualRatePct,
  required int months,
}) {
  if (months <= 0) return Money.zero;
  final i = periodicRate(annualRatePct);
  if (i == 0) return Money(roundHalfEven(principal.cents / months));
  final factor = i / (1 - math.pow(1 + i, -months));
  return Money(roundHalfEven(principal.cents * factor));
}

class ScheduleRow {
  final int number;
  final DateTime date;
  final Money payment;
  final Money principal;
  final Money interest;
  final Money balance;

  const ScheduleRow({
    required this.number,
    required this.date,
    required this.payment,
    required this.principal,
    required this.interest,
    required this.balance,
  });
}

class Amortization {
  final Money instalment;
  final List<ScheduleRow> rows;
  final Money totalInterest;
  final Money totalPaid;
  final int months;

  const Amortization({
    required this.instalment,
    required this.rows,
    required this.totalInterest,
    required this.totalPaid,
    required this.months,
  });

  double get interestShare =>
      totalPaid.isZero ? 0 : totalInterest.cents / totalPaid.cents * 100;

  DateTime get payoffDate => rows.isEmpty ? DateTime.now() : rows.last.date;

  /// Outstanding balance after [year] full years of payments.
  Money balanceAfterYears(int year) {
    final idx = year * 12 - 1;
    if (idx < 0) return rows.isEmpty ? Money.zero : rows.first.balance;
    if (idx >= rows.length) return Money.zero;
    return rows[idx].balance;
  }

  /// Interest and principal totals for a calendar year.
  ({Money paid, Money principal, Money interest}) yearTotals(int year) {
    var p = Money.zero, pr = Money.zero, it = Money.zero;
    for (final r in rows) {
      if (r.date.year == year) {
        p = p + r.payment;
        pr = pr + r.principal;
        it = it + r.interest;
      }
    }
    return (paid: p, principal: pr, interest: it);
  }
}

/// Build a complete amortization schedule.
///
/// [extra] is an optional additional principal payment each month.
Amortization amortize({
  required Money principal,
  required double annualRatePct,
  required int months,
  required DateTime start,
  Money extra = Money.zero,
}) {
  final i = periodicRate(annualRatePct);
  final base = payment(
    principal: principal,
    annualRatePct: annualRatePct,
    months: months,
  );

  var balance = principal;
  var totalInterest = Money.zero;
  var totalPaid = Money.zero;
  final rows = <ScheduleRow>[];
  var n = 0;

  // Hard ceiling guards against a payment too small to ever clear interest.
  final ceiling = months * 4 + 24;

  while (balance.cents > 0 && n < ceiling) {
    n++;
    final interest = Money(roundHalfEven(balance.cents * i));
    var principalPart = base + extra - interest;

    if (n >= months) {
      // The final scheduled instalment absorbs the rounding residue in both
      // directions. Rounding the level payment to the cent leaves a few cents
      // either over- or under-amortised; without this the loan silently runs
      // an extra period. Banks adjust the last payment for the same reason.
      //
      // This clamp runs BEFORE the shortfall guard below, so a loan small
      // enough that its instalment rounds to zero cents still terminates and
      // repays on the final period instead of returning an empty schedule.
      principalPart = balance;
    } else if (principalPart.isNegative) {
      // The payment cannot even cover the interest, so the balance would
      // grow without bound. Stop and let the caller report it; a zero
      // principal component is merely no progress, which the final-period
      // clamp above resolves.
      break;
    } else if (principalPart > balance) {
      principalPart = balance;
    }
    final paid = principalPart + interest;
    balance = balance - principalPart;
    totalInterest = totalInterest + interest;
    totalPaid = totalPaid + paid;

    rows.add(
      ScheduleRow(
        number: n,
        date: addMonths(start, n - 1),
        payment: paid,
        principal: principalPart,
        interest: interest,
        balance: balance,
      ),
    );
  }

  return Amortization(
    instalment: base,
    rows: rows,
    totalInterest: totalInterest,
    totalPaid: totalPaid,
    months: n,
  );
}

DateTime addMonths(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final y = total ~/ 12;
  final m = total % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, math.min(d.day, lastDay));
}

// ---------------------------------------------------------------------------
// Time value of money
// ---------------------------------------------------------------------------

/// Future value of a present sum plus a level annuity.
double futureValue({
  required double pv,
  required double pmt,
  required double ratePerPeriod,
  required int periods,
  bool dueAtBeginning = false,
}) {
  final i = ratePerPeriod;
  if (i == 0) return -(pv + pmt * periods);
  final f = math.pow(1 + i, periods).toDouble();
  final annuity = pmt * ((f - 1) / i) * (dueAtBeginning ? (1 + i) : 1);
  return -(pv * f + annuity);
}

double presentValue({
  required double fv,
  required double pmt,
  required double ratePerPeriod,
  required int periods,
  bool dueAtBeginning = false,
}) {
  final i = ratePerPeriod;
  if (i == 0) return -(fv + pmt * periods);
  final f = math.pow(1 + i, periods).toDouble();
  final annuity = pmt * ((f - 1) / i) * (dueAtBeginning ? (1 + i) : 1);
  return -(fv + annuity) / f;
}

double paymentFor({
  required double pv,
  required double fv,
  required double ratePerPeriod,
  required int periods,
  bool dueAtBeginning = false,
}) {
  final i = ratePerPeriod;
  if (periods == 0) return 0;
  if (i == 0) return -(pv + fv) / periods;
  final f = math.pow(1 + i, periods).toDouble();
  final due = dueAtBeginning ? (1 + i) : 1.0;
  return -(fv + pv * f) * i / ((f - 1) * due);
}

/// Solve for the number of periods.
double periodsFor({
  required double pv,
  required double fv,
  required double pmt,
  required double ratePerPeriod,
  bool dueAtBeginning = false,
}) {
  final i = ratePerPeriod;
  final adjustedPmt = dueAtBeginning ? pmt * (1 + i) : pmt;
  if (i == 0) {
    if (adjustedPmt == 0) return double.nan;
    return -(pv + fv) / adjustedPmt;
  }
  final numerator = adjustedPmt - fv * i;
  final denominator = adjustedPmt + pv * i;
  if (denominator == 0) return double.nan;
  final ratio = numerator / denominator;
  // Both terms are typically negative for a loan; it is the ratio that must
  // be positive for the logarithm to be defined.
  if (ratio <= 0) return double.nan;
  return math.log(ratio) / math.log(1 + i);
}

/// Solve for the periodic rate. Returns a SolveResult so a non-converging
/// input surfaces as a failure instead of a number.
SolveResult rateFor({
  required double pv,
  required double fv,
  required double pmt,
  required int periods,
  bool dueAtBeginning = false,
}) {
  if (periods <= 0) {
    return const SolveResult.failed('Periods must be positive.');
  }
  double f(double i) =>
      futureValue(
        pv: pv,
        pmt: pmt,
        ratePerPeriod: i,
        periods: periods,
        dueAtBeginning: dueAtBeginning,
      ) -
      fv;
  return solveRoot(f, guess: 0.01, lo: -0.9999, hi: 1.0);
}

// ---------------------------------------------------------------------------
// Cash-flow measures
// ---------------------------------------------------------------------------

double npv(double ratePerPeriod, List<double> flows) {
  var total = 0.0;
  for (var t = 0; t < flows.length; t++) {
    total += flows[t] / math.pow(1 + ratePerPeriod, t);
  }
  return total;
}

/// Internal rate of return for irregular flows. flows[0] is t=0.
SolveResult irr(List<double> flows) {
  if (flows.length < 2) {
    return const SolveResult.failed('Need at least two cash flows.');
  }
  final hasPos = flows.any((f) => f > 0);
  final hasNeg = flows.any((f) => f < 0);
  if (!hasPos || !hasNeg) {
    return const SolveResult.failed(
      'IRR needs at least one negative and one positive cash flow.',
    );
  }
  return solveRoot((r) => npv(r, flows), guess: 0.1, lo: -0.9999, hi: 10.0);
}

/// Modified IRR with explicit finance and reinvestment rates.
SolveResult mirr(List<double> flows, double financeRate, double reinvestRate) {
  final n = flows.length - 1;
  if (n < 1) return const SolveResult.failed('Need at least two cash flows.');
  var pvNeg = 0.0, fvPos = 0.0;
  for (var t = 0; t < flows.length; t++) {
    if (flows[t] < 0) {
      pvNeg += flows[t] / math.pow(1 + financeRate, t);
    } else {
      fvPos += flows[t] * math.pow(1 + reinvestRate, n - t);
    }
  }
  if (pvNeg == 0 || fvPos == 0) {
    return const SolveResult.failed('MIRR needs both inflows and outflows.');
  }
  final v = math.pow(fvPos / -pvNeg, 1 / n).toDouble() - 1;
  return SolveResult.success(v, 1);
}

/// Compound annual growth rate as a percentage.
double cagr({
  required double begin,
  required double end,
  required double years,
}) {
  if (begin <= 0 || years <= 0) return double.nan;
  return (math.pow(end / begin, 1 / years).toDouble() - 1) * 100;
}

/// Exact doubling time in periods at a given periodic rate.
double doublingPeriods(double ratePct) {
  if (ratePct <= 0) return double.nan;
  return math.log(2) / math.log(1 + ratePct / 100);
}

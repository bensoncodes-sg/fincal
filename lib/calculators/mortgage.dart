import '../core/calculator.dart';
import '../core/finance.dart';
import '../core/money.dart';

final mortgageCalculator = Calculator(
  id: 'mortgage',
  name: 'Mortgage & amortization',
  description: 'Instalment, total interest and the full schedule',
  question: Question.loanCost,
  inputs: [
    CalcInput(
      key: 'price',
      label: 'Property price',
      kind: InputKind.money,
      initial: Money.tryParse('850000')!,
      min: 0,
    ),
    CalcInput(
      key: 'loan',
      label: 'Loan amount',
      kind: InputKind.money,
      initial: Money.tryParse('637500')!,
      min: 0,
    ),
    const CalcInput(
      key: 'rate',
      label: 'Interest rate',
      kind: InputKind.percent,
      initial: 3.85,
      min: 0.5,
      max: 8.0,
      unit: '%',
    ),
    const CalcInput(
      key: 'tenor',
      label: 'Tenor',
      kind: InputKind.years,
      initial: 25.0,
      min: 1,
      max: 35,
      unit: 'years',
    ),
    CalcInput(
      key: 'extra',
      label: 'Extra payment monthly',
      kind: InputKind.money,
      initial: Money.zero,
      min: 0,
      hint: 'Paid straight off the principal',
    ),
  ],
  compute: (v, rules) {
    final loan = v.money('loan');
    final price = v.money('price');
    final rate = v.number('rate');
    final months = (v.number('tenor') * 12).round();
    final extra = v.money('extra');
    final start = DateTime(DateTime.now().year, DateTime.now().month, 1);

    if (loan.cents <= 0) {
      return const CalcResult.failed('Enter a loan amount above zero.');
    }
    if (months <= 0) {
      return const CalcResult.failed('Tenor must be at least one year.');
    }

    final base = amortize(
      principal: loan,
      annualRatePct: rate,
      months: months,
      start: start,
    );
    final actual = extra.isZero
        ? base
        : amortize(
            principal: loan,
            annualRatePct: rate,
            months: months,
            start: start,
            extra: extra,
          );

    if (actual.rows.isEmpty) {
      return const CalcResult.failed(
        'That instalment never clears the interest. Raise the payment or shorten the tenor.',
      );
    }

    final ltv = price.cents > 0 ? loan.cents / price.cents * 100 : 0.0;

    // Balance curve, sampled yearly so the chart stays honest at any tenor.
    final years = (actual.months / 12).ceil();
    final balance = <SeriesPoint>[SeriesPoint(0, loan.asDouble)];
    for (var y = 1; y <= years; y++) {
      balance.add(
        SeriesPoint(y.toDouble(), actual.balanceAfterYears(y).asDouble),
      );
    }

    final i = periodicRate(rate);
    final f = pow1p(i, months);

    return CalcResult(
      primaryBetter: Better.lower,
      primaryLabel: 'MONTHLY INSTALMENT',
      primaryValue: (actual.instalment + extra).sgd,
      secondary: [
        Metric(
          'Total interest',
          actual.totalInterest.sgd0,
          tone: Tone.negative,
          better: Better.lower,
        ),
        Metric('Total repaid', actual.totalPaid.sgd0, better: Better.lower),
        Metric(
          'Interest share',
          pct(actual.interestShare, dp: 1),
          better: Better.lower,
        ),
        Metric('Payoff', monthYear(actual.payoffDate)),
      ],
      series: [Series('Balance', balance, tone: Tone.neutral, xUnit: 'yr')],
      schedule: actual.rows,
      delta: extra.isZero
          ? null
          : DeltaNote(
              '${(base.totalInterest - actual.totalInterest).sgd0} less interest · '
              'paid off ${monthsAsTerm(base.months - actual.months)} earlier',
              tone: Tone.positive,
            ),
      explain: Explanation(
        formula: 'M  =  P · i · (1 + i)ⁿ  ÷  ((1 + i)ⁿ − 1)',
        substituted:
            'M = ${loan.format(decimals: 0)} × ${i.toStringAsFixed(6)}'
            ' × ${f.toStringAsFixed(5)} ÷ (${f.toStringAsFixed(5)} − 1)'
            '\nM = ${actual.instalment.sgd}',
        assumptions: [
          (label: 'Interest applied', value: 'Monthly rest'),
          (label: 'Rate type', value: 'Nominal ÷ 12'),
          (label: 'Day count', value: '30/360'),
          (label: 'Rounding', value: 'Half-even, 2 d.p.'),
          if (price.cents > 0) (label: 'Loan-to-value', value: pct(ltv, dp: 1)),
        ],
        footnote:
            'Banks may round differently. Your actual instalment can vary by a few cents.',
      ),
    );
  },
);

import '../core/calculator.dart';
import '../core/finance.dart';
import '../core/money.dart';

/// The month at which refinancing savings clear the switching cost.
final refinanceCalculator = Calculator(
  id: 'refinance',
  name: 'Refinance break-even',
  description: 'When the savings clear the switching cost',
  question: Question.loanCost,
  inputs: [
    CalcInput(
      key: 'balance',
      label: 'Outstanding balance',
      kind: InputKind.money,
      initial: Money.tryParse('520000')!,
      min: 0,
    ),
    const CalcInput(
      key: 'remaining',
      label: 'Remaining tenor',
      kind: InputKind.years,
      initial: 18.0,
      min: 1,
      max: 35,
      unit: 'years',
    ),
    const CalcInput(
      key: 'currentRate',
      label: 'Current rate',
      kind: InputKind.percent,
      initial: 4.25,
      min: 0.5,
      max: 8.0,
      unit: '%',
    ),
    const CalcInput(
      key: 'newRate',
      label: 'New rate',
      kind: InputKind.percent,
      initial: 3.35,
      min: 0.5,
      max: 8.0,
      unit: '%',
    ),
    CalcInput(
      key: 'cost',
      label: 'Switching cost',
      kind: InputKind.money,
      initial: Money.tryParse('3000')!,
      min: 0,
      hint: 'Legal, valuation, and any penalty',
    ),
  ],
  compute: (v, rules) {
    final bal = v.money('balance');
    final months = (v.number('remaining') * 12).round();
    final cur = v.number('currentRate');
    final nw = v.number('newRate');
    final cost = v.money('cost');
    final start = DateTime(DateTime.now().year, DateTime.now().month, 1);

    if (bal.cents <= 0 || months <= 0) {
      return const CalcResult.failed('Enter your balance and remaining tenor.');
    }

    final a = amortize(
      principal: bal,
      annualRatePct: cur,
      months: months,
      start: start,
    );
    final b = amortize(
      principal: bal,
      annualRatePct: nw,
      months: months,
      start: start,
    );

    final monthlySaving = a.instalment - b.instalment;
    if (monthlySaving.cents <= 0) {
      return CalcResult.failed(
        'The new rate costs '
        '${(b.instalment - a.instalment).sgd} more each month. '
        'Refinancing does not pay here.',
      );
    }

    // Break-even is a cash-flow question: switching costs are recovered when
    // cumulative instalment savings cover them. Interest-only savings are not
    // the same thing because principal is repaid on a different schedule.
    var cumulative = Money.zero;
    var breakEven = -1;
    final curve = <SeriesPoint>[const SeriesPoint(0, 0)];
    final n = a.rows.length < b.rows.length ? a.rows.length : b.rows.length;
    for (var m = 0; m < n; m++) {
      cumulative = cumulative + (a.rows[m].payment - b.rows[m].payment);
      if (breakEven < 0 && cumulative >= cost) breakEven = m + 1;
      if (m % 6 == 0) {
        curve.add(
          SeriesPoint((m + 1).toDouble(), (cumulative - cost).asDouble),
        );
      }
    }

    final lifetime = a.totalInterest - b.totalInterest - cost;

    return CalcResult(
      primaryLabel: 'BREAK-EVEN',
      primaryValue: breakEven < 0 ? 'Not within tenor' : '$breakEven months',
      secondary: [
        Metric('Monthly saving', monthlySaving.sgd, tone: Tone.positive),
        Metric(
          'Net lifetime saving',
          lifetime.sgd0,
          tone: lifetime.isNegative ? Tone.negative : Tone.positive,
        ),
        Metric('New instalment', b.instalment.sgd),
        Metric('Switching cost', cost.sgd0, tone: Tone.negative),
      ],
      series: [
        Series(
          'Cumulative net saving',
          curve,
          tone: Tone.positive,
          xUnit: 'mo',
        ),
      ],
      delta: breakEven < 0
          ? const DeltaNote(
              'Savings never cover the cost over the remaining tenor',
              tone: Tone.negative,
            )
          : DeltaNote(
              'Past month $breakEven you are ahead by '
              '${monthlySaving.sgd} a month',
              tone: Tone.positive,
            ),
      explain: Explanation(
        formula: 'Break-even  =  first month where  Σ(instalment saved) ≥ cost',
        substituted:
            'Monthly saving ${monthlySaving.sgd}\n'
            'Switching cost ${cost.sgd}\n'
            'Break-even ${breakEven < 0 ? "not reached" : "month $breakEven"}',
        assumptions: [
          (label: 'Tenor', value: 'Unchanged at ${monthsAsTerm(months)}'),
          (label: 'New rate held', value: 'Flat for full tenor'),
          (label: 'Interest applied', value: 'Monthly rest'),
        ],
        footnote:
            'Compares interest saved, not just the instalment gap. A reset tenor can lower the payment while raising total cost.',
      ),
    );
  },
);

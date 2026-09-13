import '../core/calculator.dart';
import '../core/finance.dart';
import '../core/money.dart';

/// Time value of money. Solve for whichever variable you leave as the target.
///
/// The solve-for pattern is the one genuinely good idea in the incumbent app,
/// kept here and given a proper convergence guarantee: a rate that does not
/// converge reports a failure instead of a plausible number.
final tvmCalculator = Calculator(
  id: 'tvm',
  name: 'Time value of money',
  description: 'Solve for PV, PMT, FV, rate or term',
  question: Question.worthIt,
  solveFor: ['pv', 'pmt', 'fv', 'rate', 'n'],
  inputs: [
    const CalcInput(
      key: 'solve',
      label: 'Solve for',
      kind: InputKind.choice,
      initial: 'PMT',
      choices: ['PV', 'PMT', 'FV', 'RATE', 'N'],
    ),
    CalcInput(
      key: 'pv',
      label: 'Present value',
      kind: InputKind.money,
      initial: Money.tryParse('-200000')!,
    ),
    CalcInput(
      key: 'pmt',
      label: 'Payment',
      kind: InputKind.money,
      initial: Money.tryParse('1432.86')!,
    ),
    CalcInput(
      key: 'fv',
      label: 'Future value',
      kind: InputKind.money,
      initial: Money.zero,
    ),
    const CalcInput(
      key: 'rate',
      label: 'Annual rate',
      kind: InputKind.percent,
      initial: 6.0,
      min: 0,
      max: 30,
      unit: '%',
    ),
    const CalcInput(
      key: 'n',
      label: 'Periods',
      kind: InputKind.integer,
      initial: 240.0,
      min: 1,
      max: 720,
      unit: 'months',
    ),
    const CalcInput(
      key: 'due',
      label: 'Payments at',
      kind: InputKind.choice,
      initial: 'End of period',
      choices: ['End of period', 'Beginning of period'],
    ),
  ],
  compute: (v, rules) {
    final solve = v.choice('solve');
    final pv = v.money('pv').asDouble;
    final pmt = v.money('pmt').asDouble;
    final fv = v.money('fv').asDouble;
    final annual = v.number('rate');
    final n = v.integer('n');
    final due = v.choice('due').startsWith('Beginning');
    final i = periodicRate(annual);

    String label;
    String value;
    final extra = <Metric>[];
    Explanation? explain;

    switch (solve) {
      case 'PV':
        final r = presentValue(
          fv: fv,
          pmt: pmt,
          ratePerPeriod: i,
          periods: n,
          dueAtBeginning: due,
        );
        label = 'PRESENT VALUE';
        value = Money.fromDouble(r).sgd;
        explain = Explanation(
          formula: 'PV  =  −(FV + PMT · ((1+i)ⁿ − 1) ÷ i)  ÷  (1+i)ⁿ',
          substituted:
              'i = ${annual.toStringAsFixed(2)}% ÷ 12 = '
              '${i.toStringAsFixed(6)}\nn = $n\nPV = ${Money.fromDouble(r).sgd}',
          assumptions: const [],
        );

      case 'FV':
        final r = futureValue(
          pv: pv,
          pmt: pmt,
          ratePerPeriod: i,
          periods: n,
          dueAtBeginning: due,
        );
        label = 'FUTURE VALUE';
        value = Money.fromDouble(r).sgd;
        explain = Explanation(
          formula: 'FV  =  −(PV · (1+i)ⁿ + PMT · ((1+i)ⁿ − 1) ÷ i)',
          substituted:
              'i = ${i.toStringAsFixed(6)}\nn = $n\n'
              'FV = ${Money.fromDouble(r).sgd}',
          assumptions: const [],
        );

      case 'RATE':
        final r = rateFor(
          pv: pv,
          fv: fv,
          pmt: pmt,
          periods: n,
          dueAtBeginning: due,
        );
        if (!r.converged) return CalcResult.failed(r.failure!);
        final annualSolved = r.value! * 12 * 100;
        label = 'ANNUAL RATE';
        value = pct(annualSolved, dp: 4);
        extra.add(Metric('Per period', pct(r.value! * 100, dp: 6)));
        extra.add(Metric('Iterations', '${r.iterations}'));
        explain = Explanation(
          formula: 'Solve  FV(i) − FV_target = 0  for i',
          substituted:
              'Newton–Raphson, bisection fallback\n'
              'tolerance 1e-10 · converged in ${r.iterations} iterations\n'
              'i = ${r.value!.toStringAsFixed(8)} per month',
          assumptions: const [
            (label: 'Method', value: 'Newton–Raphson'),
            (label: 'Fallback', value: 'Bisection'),
            (label: 'Tolerance', value: '1e-10'),
          ],
        );

      case 'N':
        final r = periodsFor(
          pv: pv,
          fv: fv,
          pmt: pmt,
          ratePerPeriod: i,
          dueAtBeginning: due,
        );
        if (r.isNaN || r.isInfinite || r <= 0) {
          return const CalcResult.failed(
            'No term satisfies these values. Check the signs — money in and money out need opposite signs.',
          );
        }
        label = 'PERIODS';
        value = '${r.toStringAsFixed(2)} months';
        extra.add(Metric('In years', (r / 12).toStringAsFixed(2)));
        explain = Explanation(
          formula: 'n  =  ln((PMT − FV·i) ÷ (PMT + PV·i))  ÷  ln(1 + i)',
          substituted:
              'i = ${i.toStringAsFixed(6)}\nn = ${r.toStringAsFixed(4)}',
          assumptions: const [],
        );

      default: // PMT
        final r = paymentFor(
          pv: pv,
          fv: fv,
          ratePerPeriod: i,
          periods: n,
          dueAtBeginning: due,
        );
        label = 'PAYMENT';
        value = Money.fromDouble(r).sgd;
        extra.add(Metric('Total paid', Money.fromDouble(r * n).sgd0));
        extra.add(
          Metric(
            'Interest',
            Money.fromDouble(r * n + pv + fv).sgd0,
            tone: Tone.negative,
          ),
        );
        explain = Explanation(
          formula: 'PMT  =  −(FV + PV · (1+i)ⁿ) · i  ÷  ((1+i)ⁿ − 1)',
          substituted:
              'i = ${annual.toStringAsFixed(2)}% ÷ 12 = '
              '${i.toStringAsFixed(6)}\n'
              '(1+i)ⁿ = ${pow1p(i, n).toStringAsFixed(6)}\n'
              'PMT = ${Money.fromDouble(r).sgd}',
          assumptions: const [],
        );
    }

    return CalcResult(
      primaryLabel: label,
      primaryValue: value,
      secondary: [
        ...extra,
        Metric('Compounding', 'Monthly'),
        Metric('Payments', due ? 'Beginning' : 'End'),
      ].take(4).toList(),
      explain: Explanation(
        formula: explain.formula,
        substituted: explain.substituted,
        assumptions: [
          ...explain.assumptions,
          (label: 'Compounding', value: 'Monthly'),
          (label: 'Payments due', value: due ? 'Beginning' : 'End'),
          (label: 'Sign convention', value: 'Cash out negative'),
        ],
        footnote:
            'Money paid out is negative and money received is positive, the same convention as Excel and the HP-12C.',
      ),
    );
  },
);

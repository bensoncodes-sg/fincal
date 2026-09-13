import 'dart:math' as math;

import '../core/calculator.dart';
import '../core/finance.dart';
import '../core/money.dart';

/// Savings, returns, share purchases and fees.

String _price(double v) => 'S\$ ${v.toStringAsFixed(4)}';

// ---------------------------------------------------------------------------
// Savings growth with regular deposits
// ---------------------------------------------------------------------------

const _periodsPerYear = {
  'Monthly': 12,
  'Quarterly': 4,
  'Annually': 1,
  'Daily': 365,
};

final savingsGrowthCalculator = Calculator(
  id: 'savings_growth',
  name: 'Savings growth',
  description: 'A lump sum plus monthly deposits, with the real annual yield',
  question: Question.later,
  inputs: [
    CalcInput(
      key: 'initial',
      label: 'Starting amount',
      kind: InputKind.money,
      initial: Money.tryParse('10000')!,
      min: 0,
    ),
    CalcInput(
      key: 'monthly',
      label: 'Monthly deposit',
      kind: InputKind.money,
      initial: Money.tryParse('500')!,
      min: 0,
    ),
    const CalcInput(
      key: 'rate',
      label: 'Interest rate',
      kind: InputKind.percent,
      initial: 3.0,
      min: 0,
      max: 15,
      unit: '% p.a.',
    ),
    const CalcInput(
      key: 'years',
      label: 'For',
      kind: InputKind.years,
      initial: 10.0,
      min: 1,
      max: 50,
      unit: 'years',
    ),
    const CalcInput(
      key: 'compounding',
      label: 'Interest is added',
      kind: InputKind.choice,
      initial: 'Monthly',
      choices: ['Monthly', 'Quarterly', 'Annually', 'Daily'],
    ),
    const CalcInput(
      key: 'timing',
      label: 'Deposits go in',
      kind: InputKind.choice,
      initial: 'End of month',
      choices: ['End of month', 'Start of month'],
    ),
  ],
  compute: (v, rules) {
    final initial = v.money('initial');
    final monthly = v.money('monthly');
    final ratePct = v.number('rate');
    final years = v.number('years');
    final m = _periodsPerYear[v.choice('compounding')] ?? 12;
    final atStart = v.choice('timing') == 'Start of month';
    final n = (years * 12).round();

    if (n < 1) {
      return const CalcResult.failed('Save for at least one month.');
    }
    if (initial.cents <= 0 && monthly.cents <= 0) {
      return const CalcResult.failed(
        'Enter a starting amount, a monthly deposit, or both.',
      );
    }
    if (ratePct < 0) {
      return const CalcResult.failed('The interest rate cannot be negative.');
    }

    final r = ratePct / 100;
    // Monthly rate equivalent to the stated compounding.
    final j = math.pow(1 + r / m, m / 12).toDouble() - 1;
    final apy = (math.pow(1 + r / m, m).toDouble() - 1) * 100;

    double balanceAt(int months) => futureValue(
      pv: -initial.asDouble,
      pmt: -monthly.asDouble,
      ratePerPeriod: j,
      periods: months,
      dueAtBeginning: atStart,
    );

    final finalBalance = Money.fromDouble(balanceAt(n));
    final deposited = initial + Money(monthly.cents * n);
    final interest = finalBalance - deposited;

    final curve = <SeriesPoint>[SeriesPoint(0, initial.asDouble)];
    final whole = (n / 12).ceil();
    for (var y = 1; y <= whole; y++) {
      curve.add(SeriesPoint(y.toDouble(), balanceAt(math.min(y * 12, n))));
    }

    return CalcResult(
      primaryLabel: 'BALANCE AFTER ${monthsAsTerm(n).toUpperCase()}',
      primaryValue: finalBalance.sgd,
      primaryBetter: Better.higher,
      secondary: [
        Metric('Total deposited', deposited.sgd0),
        Metric(
          'Interest earned',
          interest.sgd0,
          tone: Tone.positive,
          better: Better.higher,
        ),
        Metric('Effective yield', pct(apy, dp: 4), better: Better.higher),
        Metric('Monthly rate used', pct(j * 100, dp: 4)),
      ],
      series: [Series('Balance', curve, xUnit: 'yr')],
      delta: DeltaNote(
        'Interest makes up '
        '${finalBalance.cents == 0 ? "0" : (interest.cents / finalBalance.cents * 100).toStringAsFixed(1)}% '
        'of the final balance.',
        tone: Tone.positive,
      ),
      explain: Explanation(
        formula:
            'Monthly rate  j = (1 + r ÷ m)^(m ÷ 12) − 1\n'
            'Balance = start × (1 + j)ⁿ + deposit × ((1 + j)ⁿ − 1) ÷ j'
            '${atStart ? " × (1 + j)" : ""}\n'
            'Effective yield = (1 + r ÷ m)^m − 1',
        substituted:
            'r = ${pct(ratePct)}, m = $m, n = $n\n'
            'j = ${(j * 100).toStringAsFixed(6)}%\n'
            'Balance = ${finalBalance.sgd}\n'
            'Effective yield = ${pct(apy, dp: 4)}',
        assumptions: [
          (label: 'Interest added', value: v.choice('compounding')),
          (
            label: 'Deposits',
            value: atStart ? 'Start of month' : 'End of month',
          ),
          (label: 'Rate', value: 'Constant for the whole period'),
          (label: 'Tax', value: 'None (interest is not taxed in Singapore)'),
        ],
        footnote:
            'Bonus-interest accounts pay different rates on different '
            'slices of the balance; this uses one rate for all of it.',
      ),
    );
  },
);

// ---------------------------------------------------------------------------
// Return on investment, annualised
// ---------------------------------------------------------------------------

final roiCalculator = Calculator(
  id: 'roi',
  name: 'Return on investment',
  description: 'Total and annualised return, after income and fees',
  question: Question.worthIt,
  inputs: [
    CalcInput(
      key: 'invested',
      label: 'Amount invested',
      kind: InputKind.money,
      initial: Money.tryParse('10000')!,
      min: 0,
    ),
    CalcInput(
      key: 'value',
      label: 'Worth now',
      kind: InputKind.money,
      initial: Money.tryParse('14500')!,
      min: 0,
    ),
    CalcInput(
      key: 'income',
      label: 'Dividends or interest received',
      kind: InputKind.money,
      initial: Money.tryParse('600')!,
      min: 0,
    ),
    CalcInput(
      key: 'fees',
      label: 'Fees paid',
      kind: InputKind.money,
      initial: Money.tryParse('120')!,
      min: 0,
    ),
    const CalcInput(
      key: 'years',
      label: 'Held for',
      kind: InputKind.years,
      initial: 3.5,
      min: 0.1,
      max: 60,
      unit: 'years',
    ),
  ],
  compute: (v, rules) {
    final invested = v.money('invested');
    final value = v.money('value');
    final income = v.money('income');
    final fees = v.money('fees');
    final years = v.number('years');

    if (invested.cents <= 0) {
      return const CalcResult.failed('Enter how much you invested.');
    }
    if (years <= 0) {
      return const CalcResult.failed('Enter how long you held it.');
    }

    final back = value + income - fees;
    final profit = back - invested;
    final totalReturn = profit.cents / invested.cents * 100;
    final annualised = back.cents <= 0
        ? -100.0
        : (math.pow(back.cents / invested.cents, 1 / years).toDouble() - 1) *
              100;

    return CalcResult(
      primaryLabel: 'ANNUALISED RETURN',
      primaryValue: pct(annualised),
      primaryBetter: Better.higher,
      secondary: [
        Metric(
          'Total return',
          pct(totalReturn),
          tone: totalReturn >= 0 ? Tone.positive : Tone.negative,
          better: Better.higher,
        ),
        Metric(
          'Profit',
          profit.sgd0,
          tone: profit.isNegative ? Tone.negative : Tone.positive,
          better: Better.higher,
        ),
        Metric('Money in', invested.sgd0),
        Metric('Money back', back.sgd0, better: Better.higher),
      ],
      delta: DeltaNote(
        'Over ${years.toStringAsFixed(1)} years, ${pct(totalReturn)} in total '
        'is ${pct(annualised)} a year compounded.',
        tone: annualised >= 0 ? Tone.positive : Tone.negative,
      ),
      explain: Explanation(
        formula:
            'Money back = worth now + income − fees\n'
            'Total return = (money back − invested) ÷ invested\n'
            'Annualised = (money back ÷ invested)^(1 ÷ years) − 1',
        substituted:
            'Money back = ${value.sgd0} + ${income.sgd0} − '
            '${fees.sgd0} = ${back.sgd0}\n'
            'Total return = ${profit.sgd0} ÷ ${invested.sgd0} = ${pct(totalReturn)}\n'
            'Annualised = (${back.sgd0} ÷ ${invested.sgd0})^(1 ÷ '
            '${years.toStringAsFixed(2)}) − 1 = ${pct(annualised)}',
        assumptions: const [
          (label: 'Money in', value: 'One amount, at the start'),
          (label: 'Income', value: 'Counted at the end, not reinvested'),
        ],
        footnote:
            'If you added money along the way, this overstates or '
            'understates the return. Use Time value of money for regular '
            'contributions.',
      ),
    );
  },
);

// ---------------------------------------------------------------------------
// Average cost and break-even for shares
// ---------------------------------------------------------------------------

final averageCostCalculator = Calculator(
  id: 'average_cost',
  name: 'Share average cost',
  description: 'New average price after buying more, and the break-even price',
  question: Question.worthIt,
  inputs: [
    const CalcInput(
      key: 'held',
      label: 'Shares you hold',
      kind: InputKind.integer,
      initial: 1000.0,
      min: 0,
      unit: 'shares',
    ),
    const CalcInput(
      key: 'heldPrice',
      label: 'Their average price',
      kind: InputKind.decimal,
      initial: 1.20,
      min: 0,
    ),
    const CalcInput(
      key: 'buy',
      label: 'Shares you are buying',
      kind: InputKind.integer,
      initial: 500.0,
      min: 0,
      unit: 'shares',
    ),
    const CalcInput(
      key: 'buyPrice',
      label: 'Buying at',
      kind: InputKind.decimal,
      initial: 0.955,
      min: 0,
    ),
    CalcInput(
      key: 'fee',
      label: 'Fee per trade',
      kind: InputKind.money,
      initial: Money.tryParse('10')!,
      min: 0,
      hint: 'Include brokerage, clearing and exchange fees',
    ),
  ],
  compute: (v, rules) {
    final held = v.integer('held');
    final heldPrice = v.number('heldPrice');
    final buy = v.integer('buy');
    final buyPrice = v.number('buyPrice');
    final fee = v.money('fee').asDouble;
    final shares = held + buy;

    if (shares <= 0) {
      return const CalcResult.failed('Enter some shares held or bought.');
    }
    if (held < 0 || buy < 0 || heldPrice < 0 || buyPrice < 0 || fee < 0) {
      return const CalcResult.failed(
        'Shares, prices and fees cannot be negative.',
      );
    }

    final buyFee = buy > 0 ? fee : 0.0;
    final cost = held * heldPrice + buy * buyPrice + buyFee;
    final average = cost / shares;
    final breakEven = (cost + fee) / shares;
    final change = held > 0 && heldPrice > 0
        ? (average - heldPrice) / heldPrice * 100
        : 0.0;

    return CalcResult(
      primaryLabel: 'NEW AVERAGE PRICE',
      primaryValue: _price(average),
      primaryBetter: Better.lower,
      secondary: [
        Metric('Total shares', '$shares'),
        Metric('Total cost', Money.fromDouble(cost).sgd, better: Better.lower),
        Metric(
          'Break-even selling price',
          _price(breakEven),
          better: Better.lower,
        ),
        Metric(
          'Change in average',
          pct(change),
          tone: change <= 0 ? Tone.positive : Tone.negative,
        ),
      ],
      delta: DeltaNote(
        'You need to sell above ${_price(breakEven)} to come out ahead after '
        'one more fee.',
        tone: Tone.warn,
      ),
      explain: Explanation(
        formula:
            'Average = (held × price + bought × price + fee) ÷ shares\n'
            'Break-even = (total cost + selling fee) ÷ shares',
        substituted:
            'Cost = $held × ${heldPrice.toStringAsFixed(4)} + $buy × '
            '${buyPrice.toStringAsFixed(4)} + ${buyFee.toStringAsFixed(2)} = '
            '${Money.fromDouble(cost).sgd}\n'
            'Average = ${Money.fromDouble(cost).sgd} ÷ $shares = ${_price(average)}\n'
            'Break-even = ${_price(breakEven)}',
        assumptions: const [
          (label: 'Existing average', value: 'Already includes past fees'),
          (label: 'Fees', value: 'One to buy, one to sell'),
          (label: 'Dividends', value: 'Not deducted from cost'),
        ],
      ),
    );
  },
);

// ---------------------------------------------------------------------------
// What fees cost over time
// ---------------------------------------------------------------------------

final fundFeesCalculator = Calculator(
  id: 'fund_fees',
  name: 'What fees cost you',
  description: 'The drag of an annual fee on a fund, ILP or portfolio',
  question: Question.worthIt,
  inputs: [
    CalcInput(
      key: 'initial',
      label: 'Starting amount',
      kind: InputKind.money,
      initial: Money.tryParse('50000')!,
      min: 0,
    ),
    CalcInput(
      key: 'monthly',
      label: 'Monthly investment',
      kind: InputKind.money,
      initial: Money.tryParse('500')!,
      min: 0,
    ),
    const CalcInput(
      key: 'gross',
      label: 'Return before fees',
      kind: InputKind.percent,
      initial: 6.0,
      min: 0,
      max: 20,
      unit: '% p.a.',
    ),
    const CalcInput(
      key: 'fee',
      label: 'Total annual fees',
      kind: InputKind.percent,
      initial: 1.5,
      min: 0,
      max: 5,
      unit: '% p.a.',
      hint: 'Fund expense ratio plus platform or policy charges',
    ),
    const CalcInput(
      key: 'years',
      label: 'For',
      kind: InputKind.years,
      initial: 20.0,
      min: 1,
      max: 50,
      unit: 'years',
    ),
  ],
  compute: (v, rules) {
    final initial = v.money('initial');
    final monthly = v.money('monthly');
    final g = v.number('gross') / 100;
    final f = v.number('fee') / 100;
    final years = v.number('years');
    final n = (years * 12).round();

    if (n < 1) {
      return const CalcResult.failed('Invest for at least one month.');
    }
    if (initial.cents <= 0 && monthly.cents <= 0) {
      return const CalcResult.failed(
        'Enter a starting amount, a monthly investment, or both.',
      );
    }
    if (f < 0 || f >= 1 || g < -0.99) {
      return const CalcResult.failed(
        'Fees must be at least 0% and below 100%.',
      );
    }

    final jGross = math.pow(1 + g, 1 / 12).toDouble() - 1;
    final netAnnual = (1 + g) * (1 - f) - 1;
    final jNet = math.pow((1 + g) * (1 - f), 1 / 12).toDouble() - 1;

    double grow(double j, int months) => futureValue(
      pv: -initial.asDouble,
      pmt: -monthly.asDouble,
      ratePerPeriod: j,
      periods: months,
    );

    final withoutFees = Money.fromDouble(grow(jGross, n));
    final afterFees = Money.fromDouble(grow(jNet, n));
    final cost = withoutFees - afterFees;
    final share = withoutFees.cents <= 0
        ? 0.0
        : cost.cents / withoutFees.cents * 100;

    final whole = (n / 12).ceil();
    final grossCurve = <SeriesPoint>[SeriesPoint(0, initial.asDouble)];
    final netCurve = <SeriesPoint>[SeriesPoint(0, initial.asDouble)];
    for (var y = 1; y <= whole; y++) {
      final months = math.min(y * 12, n);
      grossCurve.add(SeriesPoint(y.toDouble(), grow(jGross, months)));
      netCurve.add(SeriesPoint(y.toDouble(), grow(jNet, months)));
    }

    return CalcResult(
      primaryLabel: 'FEES COST YOU',
      primaryValue: cost.sgd0,
      primaryBetter: Better.lower,
      secondary: [
        Metric('With no fees', withoutFees.sgd0, better: Better.higher),
        Metric('After fees', afterFees.sgd0, better: Better.higher),
        Metric(
          'Share of final value lost',
          pct(share, dp: 1),
          tone: Tone.negative,
          better: Better.lower,
        ),
        Metric(
          'Return after fees',
          pct(netAnnual * 100),
          better: Better.higher,
        ),
      ],
      series: [
        Series('No fees', grossCurve, tone: Tone.positive, xUnit: 'yr'),
        Series('After fees', netCurve, tone: Tone.negative, xUnit: 'yr'),
      ],
      delta: DeltaNote(
        'A ${pct(f * 100)} yearly fee takes ${pct(share, dp: 1)} of what you '
        'would have had after ${monthsAsTerm(n)}.',
        tone: Tone.warn,
      ),
      explain: Explanation(
        formula:
            'Net yearly growth = (1 + return) × (1 − fee)\n'
            'Monthly rate = growth^(1 ÷ 12) − 1\n'
            'Balance = start × (1 + j)ⁿ + monthly × ((1 + j)ⁿ − 1) ÷ j',
        substituted:
            'Before fees: j = ${(jGross * 100).toStringAsFixed(5)}%, '
            'balance ${withoutFees.sgd0}\n'
            'After fees: j = ${(jNet * 100).toStringAsFixed(5)}%, '
            'balance ${afterFees.sgd0}\n'
            'Difference = ${cost.sgd0}',
        assumptions: const [
          (label: 'Fee charged', value: 'On the balance, once a year'),
          (label: 'Return', value: 'Constant every year'),
          (label: 'Contributions', value: 'End of each month'),
          (label: 'Front-end charges', value: 'Not included'),
        ],
        footnote:
            'Real returns vary year to year; the fee does not. Policies '
            'with front-end or surrender charges cost more than this shows.',
      ),
    );
  },
);

final investingCalculators = [
  savingsGrowthCalculator,
  roiCalculator,
  averageCostCalculator,
  fundFeesCalculator,
];

import '../core/calculator.dart';
import '../core/money.dart';

final percentageCalculator = Calculator(
  id: 'percentage',
  name: 'Percentage change',
  description: 'Work out a percentage or percentage change',
  question: Question.quick,
  inputs: [
    CalcInput(
      key: 'mode',
      label: 'Work out',
      kind: InputKind.choice,
      initial: 'Percentage of',
      choices: ['Percentage of', 'Percentage change'],
    ),
    CalcInput(
      key: 'a',
      label: 'First amount',
      kind: InputKind.money,
      initial: Money.tryParse('100')!,
    ),
    CalcInput(
      key: 'b',
      label: 'Second amount',
      kind: InputKind.money,
      initial: Money.tryParse('20')!,
    ),
  ],
  compute: (v, rules) {
    final mode = v.choice('mode');
    final a = v.money('a');
    final b = v.money('b');
    if (mode == 'Percentage of') {
      final result = a.asDouble == 0
          ? double.nan
          : b.asDouble / a.asDouble * 100;
      if (!result.isFinite) {
        return const CalcResult.failed('The first amount cannot be zero.');
      }
      return CalcResult(
        primaryLabel: 'PERCENTAGE',
        primaryValue: pct(result),
        explain: Explanation(
          formula: 'percentage = second amount ÷ first amount × 100',
          substituted: '${b.sgd} ÷ ${a.sgd} × 100 = ${pct(result)}',
          assumptions: const [],
        ),
      );
    }
    if (mode == 'Percentage change') {
      if (a.isZero) {
        return const CalcResult.failed('The original amount cannot be zero.');
      }
      final result = (b.asDouble - a.asDouble) / a.asDouble * 100;
      return CalcResult(
        primaryLabel: 'PERCENTAGE CHANGE',
        primaryValue: pct(result),
        secondary: [
          Metric(
            'Direction',
            result >= 0 ? 'Increase' : 'Decrease',
            tone: result >= 0 ? Tone.positive : Tone.negative,
          ),
        ],
        explain: Explanation(
          formula: '(new − original) ÷ original × 100',
          substituted:
              '(${b.sgd} − ${a.sgd}) ÷ ${a.sgd} × 100 = ${pct(result)}',
          assumptions: const [],
        ),
      );
    }
    return const CalcResult.failed(
      'Choose a supported percentage calculation.',
    );
  },
);

final rule72Calculator = Calculator(
  id: 'rule_72',
  name: 'Rule of 72',
  description: 'Estimate how long money takes to double',
  question: Question.quick,
  inputs: [
    const CalcInput(
      key: 'rate',
      label: 'Annual return',
      kind: InputKind.percent,
      initial: 6.0,
      min: 0.01,
      max: 100,
      unit: '%',
    ),
  ],
  compute: (v, rules) {
    final rate = v.number('rate');
    if (rate <= 0) {
      return const CalcResult.failed(
        'Annual return must be greater than zero.',
      );
    }
    final years = 72 / rate;
    return CalcResult(
      primaryLabel: 'YEARS TO DOUBLE',
      primaryValue: '${years.toStringAsFixed(1)} years',
      secondary: [
        Metric('Annual return', pct(rate)),
        const Metric('Method', 'Estimate'),
      ],
      explain: Explanation(
        formula: 'years ≈ 72 ÷ annual return (%)',
        substituted:
            '72 ÷ ${rate.toStringAsFixed(2)}% = ${years.toStringAsFixed(2)} years',
        assumptions: const [(label: 'Approximation', value: 'Rule of 72')],
        footnote:
            'This is a mental-math estimate, not a compounded projection. Use TVM for an exact result.',
      ),
    );
  },
);

/// GST, inclusive or exclusive, at whatever rate the ruleset carries.
final gstCalculator = Calculator(
  id: 'gst',
  name: 'GST inclusive / exclusive',
  description: 'Add GST to a price, or strip it back out',
  question: Question.quick,
  sgSpecific: true,
  inputs: [
    CalcInput(
      key: 'amount',
      label: 'Amount',
      kind: InputKind.money,
      initial: Money.tryParse('100')!,
      min: 0,
    ),
    const CalcInput(
      key: 'mode',
      label: 'Direction',
      kind: InputKind.choice,
      initial: 'Add GST',
      choices: ['Add GST', 'Remove GST'],
    ),
  ],
  compute: (v, rules) {
    final amount = v.money('amount');
    final adding = v.choice('mode') == 'Add GST';
    final rate = rules.gstPct;

    if (amount.cents <= 0) {
      return const CalcResult.failed('Enter an amount above zero.');
    }

    final Money base;
    final Money gst;
    if (adding) {
      base = amount;
      gst = amount.scaled(rate / 100);
    } else {
      // Strip GST out of a tax-inclusive price.
      base = Money.fromDouble(amount.asDouble / (1 + rate / 100));
      gst = amount - base;
    }
    final total = base + gst;

    return CalcResult(
      primaryLabel: adding ? 'PRICE WITH GST' : 'PRICE BEFORE GST',
      primaryValue: adding ? total.sgd : base.sgd,
      secondary: [
        Metric('Before GST', base.sgd),
        Metric('GST at ${pct(rate, dp: 0)}', gst.sgd, tone: Tone.negative),
        Metric('With GST', total.sgd),
      ],
      explain: Explanation(
        formula: adding
            ? 'total = amount × (1 + rate)'
            : 'base = amount ÷ (1 + rate)',
        substituted: adding
            ? '${amount.sgd} × ${(1 + rate / 100).toStringAsFixed(2)} = ${total.sgd}'
            : '${amount.sgd} ÷ ${(1 + rate / 100).toStringAsFixed(2)} = ${base.sgd}',
        assumptions: [
          (label: 'GST rate', value: pct(rate, dp: 0)),
          (label: 'Rate table', value: 'REV ${rules.version}'),
        ],
        footnote:
            'GST rate comes from the ruleset in Settings, so it moves '
            'when the rate does.',
      ),
    );
  },
);

/// Restaurant bill the Singapore way: service charge first, then GST on the
/// total including that service charge. Doing it the other way round, or
/// applying both to the base, gives the wrong number.
final billSplitCalculator = Calculator(
  id: 'bill_split',
  name: 'Bill, service charge and split',
  description: 'Service charge, then GST on top, divided by the table',
  question: Question.quick,
  sgSpecific: true,
  inputs: [
    CalcInput(
      key: 'bill',
      label: 'Bill before charges',
      kind: InputKind.money,
      initial: Money.tryParse('120')!,
      min: 0,
    ),
    const CalcInput(
      key: 'service',
      label: 'Service charge',
      kind: InputKind.percent,
      initial: 10.0,
      min: 0,
      max: 20,
      unit: '%',
    ),
    const CalcInput(
      key: 'people',
      label: 'Split between',
      kind: InputKind.integer,
      initial: 4.0,
      min: 1,
      max: 50,
      unit: 'people',
    ),
  ],
  compute: (v, rules) {
    final bill = v.money('bill');
    final servicePct = v.number('service');
    final people = v.integer('people');
    final gstPct = rules.gstPct;

    if (bill.cents <= 0) {
      return const CalcResult.failed('Enter the bill amount.');
    }
    if (people < 1) {
      return const CalcResult.failed('Split between at least one person.');
    }

    final service = bill.scaled(servicePct / 100);
    final subtotal = bill + service;
    // GST applies to the bill INCLUDING service charge.
    final gst = subtotal.scaled(gstPct / 100);
    final total = subtotal + gst;

    // Divide to the cent, then give the remainder to the first payer so the
    // shares add back to the total exactly.
    final share = total.cents ~/ people;
    final remainder = total.cents - share * people;
    final each = Money(share);
    final firstPays = Money(share + remainder);

    return CalcResult(
      primaryLabel: 'EACH PAYS',
      primaryValue: each.sgd,
      primaryBetter: Better.lower,
      secondary: [
        Metric('Total', total.sgd),
        Metric(
          'Service ${pct(servicePct, dp: 0)}',
          service.sgd,
          tone: Tone.negative,
        ),
        Metric('GST ${pct(gstPct, dp: 0)}', gst.sgd, tone: Tone.negative),
        if (remainder > 0)
          Metric('One pays', firstPays.sgd, tone: Tone.warn)
        else
          Metric('Splits evenly', 'Yes'),
      ],
      delta: remainder > 0
          ? DeltaNote(
              'Does not divide evenly, so one person covers '
              '${Money(remainder).sgd} more',
              tone: Tone.warn,
            )
          : null,
      explain: Explanation(
        formula:
            'total = (bill + service) × (1 + GST)      each = total ÷ people',
        substituted:
            'service = ${bill.sgd} × ${pct(servicePct, dp: 0)} = ${service.sgd}\n'
            'subtotal = ${subtotal.sgd}\n'
            'GST = ${subtotal.sgd} × ${pct(gstPct, dp: 0)} = ${gst.sgd}\n'
            'total = ${total.sgd}  ÷ $people = ${each.sgd}',
        assumptions: [
          (label: 'Order', value: 'Service charge first, then GST'),
          (label: 'GST rate', value: pct(gstPct, dp: 0)),
          (label: 'Rounding', value: 'Remainder to one payer'),
        ],
        footnote:
            'GST is charged on the bill including service charge, which '
            'is why the total is higher than adding both rates to the bill.',
      ),
    );
  },
);

final quickMathCalculators = [
  percentageCalculator,
  rule72Calculator,
  gstCalculator,
  billSplitCalculator,
];

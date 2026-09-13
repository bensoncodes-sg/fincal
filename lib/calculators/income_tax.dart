import '../core/calculator.dart';
import '../core/money.dart';

/// Singapore resident income tax on a progressive band table.
final incomeTaxCalculator = Calculator(
  id: 'income_tax',
  name: 'Income tax',
  description: 'Resident tax after reliefs, with your marginal rate',
  question: Question.takeHome,
  sgSpecific: true,
  inputs: [
    CalcInput(
      key: 'income',
      label: 'Annual income',
      kind: InputKind.money,
      initial: Money.tryParse('120000')!,
      min: 0,
    ),
    CalcInput(
      key: 'reliefs',
      label: 'Total reliefs',
      kind: InputKind.money,
      initial: Money.tryParse('18000')!,
      min: 0,
      hint: 'Earned income, CPF, parent, course fees and so on',
    ),
    CalcInput(
      key: 'srs',
      label: 'SRS contribution',
      kind: InputKind.money,
      initial: Money.zero,
      min: 0,
    ),
    CalcInput(
      key: 'donations',
      label: 'Approved donations',
      kind: InputKind.money,
      initial: Money.zero,
      min: 0,
      hint: 'Deducted at 2.5 times the amount given',
    ),
  ],
  compute: (v, rules) {
    final income = v.money('income');
    final reliefs = v.money('reliefs');
    final srs = v.money('srs');
    final donations = v.money('donations');

    if (income.cents <= 0) {
      return const CalcResult.failed('Enter your annual income.');
    }

    // SRS has its own annual cap before the overall personal-relief cap;
    // approved donations are a separate 2.5x deduction.
    final eligibleSrs = srs.asDouble > rules.srsCapCitizen
        ? Money.fromDouble(rules.srsCapCitizen)
        : srs;
    final rawReliefs = reliefs + eligibleSrs;
    final cappedReliefs = rawReliefs.asDouble > rules.personalReliefCap
        ? Money.fromDouble(rules.personalReliefCap)
        : rawReliefs;
    final donationDeduction = donations.scaled(2.5);

    var chargeable = income - cappedReliefs - donationDeduction;
    if (chargeable.isNegative) chargeable = Money.zero;

    final tax = Money.fromDouble(rules.taxOn(chargeable.asDouble));
    final marginal = rules.marginalRate(chargeable.asDouble);
    final effective = income.cents == 0 ? 0.0 : tax.cents / income.cents * 100;
    final net = income - tax;

    // What one more dollar of SRS would save, at the current margin.
    final srsHeadroom = rules.srsCapCitizen - eligibleSrs.asDouble;
    final srsSaving = srsHeadroom > 0
        ? Money.fromDouble(srsHeadroom * marginal / 100)
        : Money.zero;

    final bandCurve = <SeriesPoint>[];
    for (var x = 0.0; x <= chargeable.asDouble * 1.4 + 20000; x += 5000) {
      bandCurve.add(SeriesPoint(x / 1000, rules.taxOn(x)));
    }

    return CalcResult(
      primaryBetter: Better.lower,
      primaryLabel: 'TAX PAYABLE',
      primaryValue: tax.sgd,
      secondary: [
        Metric('Chargeable income', chargeable.sgd0),
        Metric('Effective rate', pct(effective, dp: 2)),
        Metric('Marginal rate', pct(marginal, dp: 1), tone: Tone.warn),
        Metric('After tax', net.sgd0, tone: Tone.positive),
      ],
      series: [
        Series('Tax by chargeable income', bandCurve, xUnit: 'k income'),
      ],
      delta: srsHeadroom > 0
          ? DeltaNote(
              'Another ${Money.fromDouble(srsHeadroom).sgd0} into SRS would '
              'save about ${srsSaving.sgd0} at your ${pct(marginal, dp: 1)} margin',
              tone: Tone.positive,
            )
          : null,
      explain: Explanation(
        formula: 'Tax  =  Σ  (slice within each band × that band rate)',
        substituted:
            'Income        ${income.sgd0}\n'
            'Less reliefs  ${cappedReliefs.sgd0}'
            '${rawReliefs.asDouble > rules.personalReliefCap ? "  (capped)" : ""}\n'
            'Less donations ${donationDeduction.sgd0}\n'
            'Chargeable    ${chargeable.sgd0}\n'
            'Tax           ${tax.sgd}',
        assumptions: [
          (label: 'Residency', value: 'Tax resident'),
          (
            label: 'Relief cap',
            value: Money.fromDouble(rules.personalReliefCap).sgd0,
          ),
          (label: 'Donation multiple', value: '2.5×'),
          (label: 'Band table', value: 'REV ${rules.version}'),
        ],
        footnote:
            'Band rates last verified ${rules.verifiedOn.day}/${rules.verifiedOn.month}/${rules.verifiedOn.year}. Confirm against IRAS before filing.',
      ),
    );
  },
);

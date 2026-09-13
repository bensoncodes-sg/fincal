import '../core/calculator.dart';
import '../core/money.dart';

/// Buyer stamp duty plus additional buyer stamp duty.
///
/// The upfront cash figure nobody budgets for until the lawyer asks.
final stampDutyCalculator = Calculator(
  id: 'stamp_duty',
  name: 'Stamp duty (BSD + ABSD)',
  description: 'What you owe on signing, by buyer profile',
  question: Question.takeHome,
  sgSpecific: true,
  inputs: [
    CalcInput(
      key: 'price',
      label: 'Purchase price',
      kind: InputKind.money,
      initial: Money.tryParse('850000')!,
      min: 0,
      hint: 'Duty applies to the higher of price or valuation',
    ),
    const CalcInput(
      key: 'profile',
      label: 'Buyer profile',
      kind: InputKind.choice,
      initial: 'Citizen',
      choices: ['Citizen', 'PR', 'Foreigner'],
    ),
    const CalcInput(
      key: 'count',
      label: 'This will be property number',
      kind: InputKind.integer,
      initial: 1.0,
      min: 1,
      max: 3,
    ),
  ],
  compute: (v, rules) {
    final price = v.money('price');
    final profile = v.choice('profile');
    final count = v.integer('count');

    if (price.cents <= 0) {
      return const CalcResult.failed('Enter a purchase price.');
    }

    final bsd = Money.fromDouble(rules.bsdOn(price.asDouble));
    final absdRate = rules.absdRate(profile, count);
    // IRAS rounds ABSD down to the nearest dollar (minimum duty $1 where
    // applicable). BSD is rounded to cents for this display model.
    final absdCents = (price.cents * absdRate / 100).floor();
    final absd = Money((absdCents ~/ 100) * 100);
    final total = bsd + absd;
    final asShare = price.cents == 0 ? 0.0 : total.cents / price.cents * 100;

    // Marginal BSD band the price lands in.
    var lower = 0.0;
    var bandRate = rules.bsdBands.last.ratePct;
    for (final b in rules.bsdBands) {
      final upper = b.upTo ?? double.infinity;
      if (price.asDouble > lower && price.asDouble <= upper) {
        bandRate = b.ratePct;
        break;
      }
      lower = upper;
    }

    return CalcResult(
      primaryBetter: Better.lower,
      primaryLabel: 'STAMP DUTY DUE',
      primaryValue: total.sgd,
      secondary: [
        Metric('Buyer stamp duty', bsd.sgd, tone: Tone.negative),
        Metric(
          'ABSD ${pct(absdRate, dp: 0)}',
          absd.sgd0,
          tone: absd.isZero ? Tone.neutral : Tone.negative,
        ),
        Metric('Share of price', pct(asShare, dp: 2)),
        Metric('Top BSD band', pct(bandRate, dp: 0)),
      ],
      delta: absd.isZero
          ? const DeltaNote(
              'No ABSD on a first property for this profile',
              tone: Tone.positive,
            )
          : DeltaNote(
              'ABSD adds ${absd.sgd0} because this is property number $count '
              'for a $profile buyer',
              tone: Tone.warn,
            ),
      explain: Explanation(
        formula:
            'BSD  =  Σ (slice in band × band rate)        ABSD  =  price × rate',
        substituted:
            'Price  ${price.sgd0}\n'
            'BSD    ${bsd.sgd}\n'
            'ABSD   ${pct(absdRate, dp: 0)} × ${price.format(decimals: 0)} = ${absd.sgd0}\n'
            'Total  ${total.sgd}',
        assumptions: [
          (label: 'Duty base', value: 'Higher of price or valuation'),
          (label: 'Profile', value: profile),
          (label: 'Property number', value: '$count'),
          (label: 'Rate table', value: 'REV ${rules.version}'),
        ],
        footnote:
            'Payable within 14 days of signing and almost always in cash. Reliefs (married couples, en-bloc) are not applied here. Verify with IRAS.',
      ),
    );
  },
);

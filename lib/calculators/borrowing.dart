import 'dart:math' as math;

import '../core/calculator.dart';
import '../core/finance.dart';
import '../core/money.dart';

/// Credit cards, personal loans and car loans.
///
/// The common thread is that the headline rate is rarely the real cost:
/// minimum payments stretch a card balance for decades, and a "flat" rate on
/// a personal or car loan is roughly half the effective rate, because interest
/// is charged on the original amount for the whole term even as it is repaid.

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Effective rate of a flat-rate loan.
///
/// Flat interest is charged on the ORIGINAL principal for the whole tenure,
/// so the instalment is (principal + principal × rate × years) ÷ months. The
/// effective rate is the monthly rate at which those instalments repay what
/// the borrower actually received, annualised.
({double monthlyRate, double eir, double nominal, String? failure}) flatToEir({
  required double received,
  required double instalment,
  required int months,
}) {
  final r = rateFor(pv: received, fv: 0, pmt: -instalment, periods: months);
  if (!r.converged) {
    return (monthlyRate: 0, eir: 0, nominal: 0, failure: r.failure);
  }
  final i = r.value!.abs() < 1e-12 ? 0.0 : r.value!;
  return (
    monthlyRate: i,
    eir: (math.pow(1 + i, 12) - 1) * 100,
    nominal: i * 12 * 100,
    failure: null,
  );
}

class _Payoff {
  final int months;
  final Money interest;
  final Money paid;
  const _Payoff(this.months, this.interest, this.paid);
}

/// Month-by-month card repayment in cents. Returns null when the balance
/// never clears, which is a real outcome and must not become a big number.
_Payoff? _simulateCard({
  required Money balance,
  required double monthlyRate,
  required int Function(int statementCents) paymentFor,
  int? clearAt,
  int maxMonths = 1200,
}) {
  var bal = balance.cents;
  var interest = 0;
  var paid = 0;
  var k = 0;
  while (bal > 0) {
    k++;
    if (k > maxMonths) return null;
    final charge = roundHalfEven(bal * monthlyRate);
    final statement = bal + charge;
    var pay = clearAt != null && k >= clearAt
        ? statement
        : paymentFor(statement);
    if (pay > statement) pay = statement;
    // A payment that does not cover the month's interest never ends.
    if (pay <= charge && pay < statement) return null;
    bal = statement - pay;
    interest += charge;
    paid += pay;
  }
  return _Payoff(k, Money(interest), Money(paid));
}

// ---------------------------------------------------------------------------
// Credit card payoff
// ---------------------------------------------------------------------------

final creditCardCalculator = Calculator(
  id: 'credit_card',
  name: 'Credit card payoff',
  description:
      'How long a balance takes to clear, and what minimum payments cost',
  question: Question.loanCost,
  inputs: [
    CalcInput(
      key: 'balance',
      label: 'Card balance',
      kind: InputKind.money,
      initial: Money.tryParse('8000')!,
      min: 0,
    ),
    const CalcInput(
      key: 'rate',
      label: 'Card interest rate',
      kind: InputKind.percent,
      initial: 26.9,
      min: 0,
      max: 40,
      unit: '% p.a.',
    ),
    const CalcInput(
      key: 'mode',
      label: 'I want to',
      kind: InputKind.choice,
      initial: 'Pay a fixed amount',
      choices: ['Pay a fixed amount', 'Clear it by a date'],
    ),
    CalcInput(
      key: 'payment',
      label: 'Monthly payment',
      kind: InputKind.money,
      initial: Money.tryParse('400')!,
      min: 0,
      showWhen: (key: 'mode', value: 'Pay a fixed amount'),
    ),
    const CalcInput(
      key: 'months',
      label: 'Clear it within',
      showWhen: (key: 'mode', value: 'Clear it by a date'),
      kind: InputKind.integer,
      initial: 24.0,
      min: 1,
      max: 360,
      unit: 'months',
    ),
  ],
  compute: (v, rules) {
    final balance = v.money('balance');
    final ratePct = v.number('rate');
    final byDate = v.choice('mode') == 'Clear it by a date';
    final i = ratePct / 100 / 12;

    if (balance.cents <= 0) {
      return const CalcResult.failed('Enter the balance on the card.');
    }
    if (ratePct < 0) {
      return const CalcResult.failed('The interest rate cannot be negative.');
    }

    _Payoff? plan;
    Money? requiredPayment;
    if (byDate) {
      final n = v.integer('months');
      if (n < 1) {
        return const CalcResult.failed('Choose at least one month.');
      }
      final level = i == 0
          ? (balance.cents / n).ceil()
          : roundHalfEven(balance.cents * i / (1 - math.pow(1 + i, -n)));
      requiredPayment = Money(level);
      plan = _simulateCard(
        balance: balance,
        monthlyRate: i,
        paymentFor: (_) => level,
        clearAt: n,
      );
    } else {
      final pay = v.money('payment').cents;
      plan = _simulateCard(
        balance: balance,
        monthlyRate: i,
        paymentFor: (_) => pay,
      );
      if (plan == null) {
        final firstInterest = Money(roundHalfEven(balance.cents * i));
        return CalcResult.failed(
          'This payment never clears the card: the first month alone adds '
          '${firstInterest.sgd} of interest. Pay more than that each month.',
        );
      }
    }
    if (plan == null) {
      return const CalcResult.failed('This balance cannot be cleared in time.');
    }

    // The minimum-payment path, for contrast.
    final minimum = _simulateCard(
      balance: balance,
      monthlyRate: i,
      paymentFor: (statement) =>
          math.max(roundHalfEven(statement * 0.03), 5000),
    );

    final secondary = <Metric>[
      Metric(
        'Total interest',
        plan.interest.sgd0,
        tone: Tone.negative,
        better: Better.lower,
      ),
      Metric('Total paid', plan.paid.sgd0, better: Better.lower),
      if (minimum != null) ...[
        Metric(
          'Minimum-only time',
          '${minimum.months} months',
          tone: Tone.warn,
          better: Better.lower,
        ),
        Metric(
          'Minimum-only interest',
          minimum.interest.sgd0,
          tone: Tone.negative,
          better: Better.lower,
        ),
      ],
    ];

    final extraCost = minimum == null ? null : minimum.interest - plan.interest;

    return CalcResult(
      primaryLabel: byDate ? 'MONTHLY PAYMENT' : 'DEBT-FREE IN',
      primaryValue: byDate ? requiredPayment!.sgd : '${plan.months} months',
      primaryBetter: Better.lower,
      secondary: secondary,
      delta: extraCost == null
          ? const DeltaNote(
              'Minimum payments alone would take over 100 years to clear this.',
              tone: Tone.negative,
            )
          : DeltaNote(
              'Paying only the minimum takes ${monthsAsTerm(minimum!.months)} '
              'and costs ${extraCost.sgd0} more in interest.',
              tone: Tone.warn,
            ),
      explain: Explanation(
        formula:
            'Each month: interest = balance × rate ÷ 12\n'
            'balance = balance + interest − payment',
        substituted:
            'Monthly rate = ${pct(ratePct)} ÷ 12 = '
            '${(i * 100).toStringAsFixed(4)}%\n'
            'First month interest = ${Money(roundHalfEven(balance.cents * i)).sgd}\n'
            '${byDate ? "Level payment over ${v.integer('months')} months = ${requiredPayment!.sgd}" : "Fixed payment = ${v.money('payment').sgd}"}\n'
            'Cleared after ${plan.months} payments',
        assumptions: const [
          (label: 'Interest charged', value: 'Monthly on the balance'),
          (label: 'New spending', value: 'None'),
          (label: 'Minimum payment', value: '3% or S\$50, whichever is higher'),
          (label: 'Late fees', value: 'Not included'),
        ],
        footnote:
            'Minimum-payment rules differ between cards. Check the rule '
            'printed on your statement.',
      ),
    );
  },
);

// ---------------------------------------------------------------------------
// Personal loan: flat rate against effective rate
// ---------------------------------------------------------------------------

final personalLoanCalculator = Calculator(
  id: 'personal_loan',
  name: 'Personal loan: flat vs effective rate',
  description: 'What a "flat" advertised rate really costs',
  question: Question.loanCost,
  sgSpecific: true,
  inputs: [
    CalcInput(
      key: 'loan',
      label: 'Loan amount',
      kind: InputKind.money,
      initial: Money.tryParse('20000')!,
      min: 0,
    ),
    const CalcInput(
      key: 'flatRate',
      label: 'Advertised flat rate',
      kind: InputKind.percent,
      initial: 3.5,
      min: 0,
      max: 20,
      unit: '% p.a.',
    ),
    const CalcInput(
      key: 'tenure',
      label: 'Tenure',
      kind: InputKind.years,
      initial: 3.0,
      min: 1,
      max: 10,
      unit: 'years',
    ),
    const CalcInput(
      key: 'fee',
      label: 'Processing fee',
      kind: InputKind.percent,
      initial: 1.0,
      min: 0,
      max: 10,
      unit: '%',
      hint: 'Usually taken out of the amount you receive',
    ),
  ],
  compute: (v, rules) {
    final loan = v.money('loan');
    final flat = v.number('flatRate');
    final years = v.number('tenure');
    final feePct = v.number('fee');
    final n = (years * 12).round();

    if (loan.cents <= 0) {
      return const CalcResult.failed('Enter the loan amount.');
    }
    if (n < 1) {
      return const CalcResult.failed('Tenure must be at least one month.');
    }
    if (flat < 0 || feePct < 0) {
      return const CalcResult.failed('Rates and fees cannot be negative.');
    }

    final interest = loan.scaled(flat / 100 * n / 12);
    final total = loan + interest;
    final instalmentExact = total.asDouble / n;
    final instalment = Money(roundHalfEven(total.cents / n));
    final fee = loan.scaled(feePct / 100);
    final received = loan - fee;
    if (received.cents <= 0) {
      return const CalcResult.failed(
        'The fee takes the whole loan. Check the fee percentage.',
      );
    }

    final eir = flatToEir(
      received: received.asDouble,
      instalment: instalmentExact,
      months: n,
    );
    if (eir.failure != null) {
      return CalcResult.failed(
        'The effective rate could not be worked out for these terms: '
        '${eir.failure}',
      );
    }

    final ratio = flat > 0 ? eir.eir / flat : 0.0;

    return CalcResult(
      primaryLabel: 'EFFECTIVE INTEREST RATE',
      primaryValue: pct(eir.eir),
      primaryBetter: Better.lower,
      secondary: [
        Metric('Monthly instalment', instalment.sgd, better: Better.lower),
        Metric(
          'Total interest',
          interest.sgd0,
          tone: Tone.negative,
          better: Better.lower,
        ),
        Metric('You receive', received.sgd0, better: Better.higher),
        Metric('Nominal equivalent', pct(eir.nominal), better: Better.lower),
      ],
      delta: DeltaNote(
        flat > 0
            ? '${pct(flat, dp: 2)} flat is ${pct(eir.eir)} effective — about '
                  '${ratio.toStringAsFixed(1)} times the advertised rate.'
            : 'With no interest, the only cost is the fee.',
        tone: Tone.warn,
      ),
      explain: Explanation(
        formula:
            'Interest = loan × flat rate × years\n'
            'Instalment = (loan + interest) ÷ months\n'
            'Solve i: received = instalment × (1 − (1 + i)⁻ⁿ) ÷ i\n'
            'EIR = (1 + i)¹² − 1',
        substituted:
            'Interest = ${loan.sgd0} × ${pct(flat)} × '
            '${(n / 12).toStringAsFixed(2)} = ${interest.sgd}\n'
            'Instalment = ${total.sgd} ÷ $n = ${instalment.sgd}\n'
            'Received = ${received.sgd}\n'
            'i = ${(eir.monthlyRate * 100).toStringAsFixed(5)}% a month\n'
            'EIR = ${pct(eir.eir)}',
        assumptions: const [
          (label: 'Flat interest', value: 'On the original amount, full term'),
          (label: 'Fee', value: 'Deducted from the amount received'),
          (label: 'EIR basis', value: 'Monthly rate compounded to a year'),
        ],
        footnote:
            'Banks may state EIR on a slightly different basis. Compare '
            'the EIR in the loan documents with this figure.',
      ),
    );
  },
);

// ---------------------------------------------------------------------------
// Car loan: flat rate, effective rate, Rule of 78 early settlement
// ---------------------------------------------------------------------------

final carLoanCalculator = Calculator(
  id: 'car_loan',
  name: 'Car loan: Rule of 78',
  description:
      'Flat-rate instalment, real rate, and the cost of settling early',
  question: Question.loanCost,
  sgSpecific: true,
  inputs: [
    CalcInput(
      key: 'price',
      label: 'Car price',
      kind: InputKind.money,
      initial: Money.tryParse('150000')!,
      min: 0,
      hint: 'Including COE',
    ),
    CalcInput(
      key: 'down',
      label: 'Down payment',
      kind: InputKind.money,
      initial: Money.tryParse('60000')!,
      min: 0,
    ),
    const CalcInput(
      key: 'flatRate',
      label: 'Flat interest rate',
      kind: InputKind.percent,
      initial: 2.78,
      min: 0,
      max: 10,
      unit: '% p.a.',
    ),
    const CalcInput(
      key: 'tenure',
      label: 'Tenure',
      kind: InputKind.years,
      initial: 7.0,
      min: 1,
      max: 10,
      unit: 'years',
    ),
    const CalcInput(
      key: 'settleAfter',
      label: 'Settle early after',
      kind: InputKind.integer,
      initial: 36.0,
      min: 0,
      max: 120,
      unit: 'payments',
      hint: '0 means run the loan to the end',
    ),
  ],
  compute: (v, rules) {
    final price = v.money('price');
    final down = v.money('down');
    final flat = v.number('flatRate');
    final years = v.number('tenure');
    final n = (years * 12).round();
    final settleAfter = v.integer('settleAfter');
    final loan = price - down;

    if (price.cents <= 0) {
      return const CalcResult.failed('Enter the price of the car.');
    }
    if (loan.cents <= 0) {
      return const CalcResult.failed(
        'The down payment covers the car, so there is no loan.',
      );
    }
    if (n < 1) {
      return const CalcResult.failed('Tenure must be at least one month.');
    }
    if (flat < 0) {
      return const CalcResult.failed('The interest rate cannot be negative.');
    }

    final interest = loan.scaled(flat / 100 * n / 12);
    final total = loan + interest;
    final instalmentExact = total.asDouble / n;
    final instalment = Money(roundHalfEven(total.cents / n));

    final eir = flatToEir(
      received: loan.asDouble,
      instalment: instalmentExact,
      months: n,
    );
    if (eir.failure != null) {
      return CalcResult.failed(
        'The effective rate could not be worked out: ${eir.failure}',
      );
    }

    final settling = settleAfter > 0 && settleAfter < n;
    Money? settleAmount;
    Money? ruleOf78Cost;
    if (settling) {
      final k = n - settleAfter;
      // Rule of 78: unearned interest is the sum of the remaining months'
      // digits over the sum of all months' digits.
      final rebate = interest.asDouble * (k * (k + 1) / 2) / (n * (n + 1) / 2);
      final settle78 = instalmentExact * k - rebate;
      final i = eir.monthlyRate;
      final fair = i == 0
          ? instalmentExact * k
          : instalmentExact * (1 - math.pow(1 + i, -k)) / i;
      settleAmount = Money.fromDouble(settle78);
      ruleOf78Cost = Money.fromDouble(settle78 - fair);
    }

    return CalcResult(
      primaryLabel: 'MONTHLY INSTALMENT',
      primaryValue: instalment.sgd,
      primaryBetter: Better.lower,
      secondary: [
        Metric(
          'Total interest',
          interest.sgd0,
          tone: Tone.negative,
          better: Better.lower,
        ),
        Metric('Effective rate', pct(eir.eir), better: Better.lower),
        if (settling) ...[
          Metric(
            'Settle after $settleAfter',
            settleAmount!.sgd0,
            better: Better.lower,
          ),
          Metric(
            'Rule of 78 costs',
            ruleOf78Cost!.sgd0,
            tone: Tone.negative,
            better: Better.lower,
          ),
        ] else ...[
          Metric('Loan amount', loan.sgd0),
          Metric('Total repaid', total.sgd0, better: Better.lower),
        ],
      ],
      delta: DeltaNote(
        settling
            ? 'Settling after $settleAfter payments costs ${ruleOf78Cost!.sgd0} '
                  'more than a loan charging interest on the reducing balance at '
                  'the same effective rate.'
            : '${pct(flat)} flat works out to ${pct(eir.eir)} effective.',
        tone: Tone.warn,
      ),
      explain: Explanation(
        formula:
            'Instalment = (loan + loan × flat × years) ÷ months\n'
            'Rule of 78 rebate = interest × k(k+1) ÷ n(n+1)\n'
            'Settlement = instalment × k − rebate      k = payments left',
        substituted:
            'Loan = ${price.sgd0} − ${down.sgd0} = ${loan.sgd0}\n'
            'Interest = ${interest.sgd}\n'
            'Instalment = ${total.sgd} ÷ $n = ${instalment.sgd}\n'
            '${settling ? "k = ${n - settleAfter}, settlement = ${settleAmount!.sgd}" : "Run to the end, no early settlement"}',
        assumptions: const [
          (label: 'Interest', value: 'Flat, on the original loan'),
          (label: 'Early settlement', value: 'Rule of 78'),
          (label: 'Early settlement fee', value: 'Not included'),
          (label: 'Loan limits', value: 'Not checked'),
        ],
        footnote:
            'MAS sets a minimum down payment and maximum tenure for car '
            'loans, and many lenders add an early settlement fee. Neither is '
            'applied here.',
      ),
    );
  },
);

final borrowingCalculators = [
  creditCardCalculator,
  personalLoanCalculator,
  carLoanCalculator,
];

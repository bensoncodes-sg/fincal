import '../core/calculator.dart';
import '../core/finance.dart';
import '../core/money.dart';

/// Maximum responsible purchase price under TDSR and, for HDB/EC, MSR.
///
/// This is the calculation a US-centric app structurally cannot do: the
/// binding constraint is a regulatory ratio stress-tested at a floor rate,
/// not an income multiple.
final affordabilityCalculator = Calculator(
  id: 'affordability',
  name: 'Home affordability',
  description: 'Maximum price under TDSR and MSR, stress-tested',
  question: Question.afford,
  sgSpecific: true,
  inputs: [
    CalcInput(
      key: 'income',
      label: 'Monthly income',
      kind: InputKind.money,
      initial: Money.tryParse('9000')!,
      min: 0,
    ),
    CalcInput(
      key: 'debts',
      label: 'Other monthly debts',
      kind: InputKind.money,
      initial: Money.tryParse('600')!,
      min: 0,
      hint: 'Car loan, personal loan, card minimums',
    ),
    CalcInput(
      key: 'cash',
      label: 'Cash and CPF available',
      kind: InputKind.money,
      initial: Money.tryParse('250000')!,
      min: 0,
    ),
    const CalcInput(
      key: 'age',
      label: 'Your age',
      kind: InputKind.integer,
      initial: 35.0,
      min: 21,
      max: 70,
      unit: 'years',
      hint: 'Full LTV needs the loan to finish by 65',
    ),
    const CalcInput(
      key: 'tenor',
      label: 'Tenor',
      kind: InputKind.years,
      initial: 25.0,
      min: 5,
      max: 35,
      unit: 'years',
    ),
    const CalcInput(
      key: 'type',
      label: 'Property type',
      kind: InputKind.choice,
      initial: 'HDB / EC',
      choices: ['HDB / EC', 'Private'],
    ),
  ],
  compute: (v, rules) {
    final income = v.money('income');
    final debts = v.money('debts');
    final cash = v.money('cash');
    final tenureYears = v.number('tenor');
    final months = (tenureYears * 12).round();
    final isHdb = v.choice('type').startsWith('HDB');
    final age = v.integer('age');

    if (income.cents <= 0) {
      return const CalcResult.failed('Enter your monthly income.');
    }

    final stress = rules.stressTestFloorPct;
    final tdsrRoom = income.scaled(rules.tdsrCeilingPct / 100) - debts;
    final msrRoom = income.scaled(rules.msrCeilingPct / 100);
    final msrBinds = isHdb && msrRoom < tdsrRoom;
    final binding = msrBinds ? msrRoom : tdsrRoom;
    final bindingName = msrBinds ? 'MSR 30%' : 'TDSR 55%';

    if (binding.cents <= 0) {
      return const CalcResult.failed(
        'Existing debts already use up your TDSR headroom. Clear some before borrowing.',
      );
    }

    // Largest loan whose stress-tested instalment fits the binding ratio.
    final i = periodicRate(stress);
    final factor = (1 - pow1p(i, -months)) / i;
    final maxLoan = Money.fromDouble(binding.asDouble * factor);

    // LTV is not a flat 75%. A tenure that runs too long, or a loan that
    // finishes after 65, drops it to 55% — which cuts the maximum price by
    // roughly a quarter. Applying it flat overstates what someone can borrow.
    final ltvRule = rules.ltvFor(
      age: age,
      tenureYears: tenureYears,
      isHdb: isHdb,
    );
    final ltv = ltvRule.ltv;
    final ltvReduced = ltv < rules.bankLtvPct;
    final priceFromLoan = Money.fromDouble(maxLoan.asDouble / (ltv / 100));
    final priceFromCash = Money.fromDouble(cash.asDouble / (1 - ltv / 100));
    final maxPrice = priceFromLoan < priceFromCash
        ? priceFromLoan
        : priceFromCash;
    final limitedBy = priceFromLoan < priceFromCash
        ? 'Loan ceiling'
        : 'Cash on hand';

    final loanAtPrice = maxPrice.scaled(ltv / 100);
    final stressedInstalment = payment(
      principal: loanAtPrice,
      annualRatePct: stress,
      months: months,
    );

    return CalcResult(
      primaryBetter: Better.higher,
      primaryLabel: 'MAXIMUM PROPERTY PRICE',
      primaryValue: maxPrice.sgd0,
      secondary: [
        Metric('Max loan', maxLoan.sgd0),
        Metric('Down payment', (maxPrice - loanAtPrice).sgd0),
        Metric('Stressed instalment', stressedInstalment.sgd0),
        Metric(
          ltvReduced ? 'LTV (reduced)' : 'Limited by',
          ltvReduced ? pct(ltv, dp: 0) : limitedBy,
          tone: Tone.warn,
        ),
      ],
      delta: DeltaNote(
        ltvReduced
            ? 'LTV cut to ${pct(ltv, dp: 0)} — ${ltvRule.reason}. '
                  'Binding constraint is $bindingName.'
            : 'Binding constraint is $bindingName · monthly ceiling '
                  '${binding.sgd0}',
        tone: Tone.warn,
      ),
      explain: Explanation(
        formula:
            'Loan  =  ceiling · (1 − (1 + i)⁻ⁿ) ÷ i          i = stress ÷ 12',
        substituted:
            'ceiling = ${binding.sgd}\n'
            'i = ${pct(stress, dp: 2)} ÷ 12 = ${i.toStringAsFixed(6)}\n'
            'Loan  = ${maxLoan.sgd0}\n'
            'Price = Loan ÷ ${pct(ltv, dp: 0)} = ${maxPrice.sgd0}',
        assumptions: [
          (label: 'Stress-test rate', value: pct(stress, dp: 2)),
          (label: 'TDSR ceiling', value: pct(rules.tdsrCeilingPct, dp: 0)),
          if (isHdb)
            (label: 'MSR ceiling', value: pct(rules.msrCeilingPct, dp: 0)),
          (label: 'Loan-to-value', value: pct(ltv, dp: 0)),
          (label: 'LTV basis', value: ltvRule.reason),
          (label: 'Loan ends at age', value: '${age + tenureYears.round()}'),
        ],
        footnote:
            'Banks stress-test at a floor rate, not the rate you are offered. '
            'TDSR, MSR, the stress floor and the LTV limits come from MAS '
            'guidance, which could not be read from the Notice itself here — '
            'confirm them before relying on this. Your actual approval may '
            'differ.',
      ),
    );
  },
);

import '../core/calculator.dart';
import '../core/finance.dart';
import '../core/money.dart';

/// HDB concessionary loan against a bank package over the full tenor.
final hdbVsBankCalculator = Calculator(
  id: 'hdb_vs_bank',
  name: 'HDB loan vs bank loan',
  description: 'Concessionary rate against a bank package',
  question: Question.loanCost,
  sgSpecific: true,
  inputs: [
    CalcInput(
      key: 'loan',
      label: 'Loan amount',
      kind: InputKind.money,
      initial: Money.tryParse('637500')!,
      min: 0,
    ),
    const CalcInput(
      key: 'tenor',
      label: 'Tenor',
      kind: InputKind.years,
      initial: 25.0,
      min: 5,
      max: 30,
      unit: 'years',
    ),
    const CalcInput(
      key: 'hdbRate',
      label: 'HDB concessionary rate',
      kind: InputKind.percent,
      initial: 2.6,
      min: 1.0,
      max: 5.0,
      unit: '%',
    ),
    const CalcInput(
      key: 'bankRate',
      label: 'Bank rate',
      kind: InputKind.percent,
      initial: 3.85,
      min: 0.5,
      max: 8.0,
      unit: '%',
    ),
  ],
  compute: (v, rules) {
    final loan = v.money('loan');
    final months = (v.number('tenor') * 12).round();
    final hdbRate = v.number('hdbRate');
    final bankRate = v.number('bankRate');
    final start = DateTime(DateTime.now().year, DateTime.now().month, 1);

    if (loan.cents <= 0 || months <= 0) {
      return const CalcResult.failed('Enter a loan amount and tenor.');
    }

    final hdb = amortize(
      principal: loan,
      annualRatePct: hdbRate,
      months: months,
      start: start,
    );
    final bank = amortize(
      principal: loan,
      annualRatePct: bankRate,
      months: months,
      start: start,
    );

    final hdbWins = hdb.totalPaid <= bank.totalPaid;
    final gap = (bank.totalPaid - hdb.totalPaid).abs;
    final monthlyGap = (bank.instalment - hdb.instalment).abs;
    final years = (months / 12).ceil();

    List<SeriesPoint> curve(Amortization a) => [
      SeriesPoint(0, loan.asDouble),
      for (var y = 1; y <= years; y++)
        SeriesPoint(y.toDouble(), a.balanceAfterYears(y).asDouble),
    ];

    return CalcResult(
      primaryLabel: 'CHEAPER OVER $years YEARS',
      primaryValue: hdbWins ? 'HDB $hdbRate%' : 'Bank $bankRate%',
      secondary: [
        Metric('HDB instalment', hdb.instalment.sgd),
        Metric('Bank instalment', bank.instalment.sgd),
        Metric('HDB total interest', hdb.totalInterest.sgd0),
        Metric('Bank total interest', bank.totalInterest.sgd0),
      ],
      series: [
        Series('HDB', curve(hdb), tone: Tone.positive, xUnit: 'yr'),
        Series('Bank', curve(bank), tone: Tone.negative, xUnit: 'yr'),
      ],
      schedule: (hdbWins ? hdb : bank).rows,
      delta: DeltaNote(
        '${gap.sgd} less in total, and ${monthlyGap.sgd} a month lighter',
        tone: Tone.positive,
      ),
      explain: Explanation(
        formula: 'Compare  Σ payments  at each rate over the same tenor',
        substituted:
            'HDB   ${hdb.instalment.sgd} × ${hdb.months} = ${hdb.totalPaid.sgd0}\n'
            'Bank  ${bank.instalment.sgd} × ${bank.months} = ${bank.totalPaid.sgd0}\n'
            'Difference ${gap.sgd}',
        assumptions: [
          (label: 'HDB rate held', value: 'Flat for full tenor'),
          (label: 'Bank rate held', value: 'Flat for full tenor'),
          (label: 'Interest applied', value: 'Monthly rest'),
        ],
        footnote:
            'Bank packages usually reprice after the lock-in. Holding the rate flat understates a floating package.',
      ),
    );
  },
);

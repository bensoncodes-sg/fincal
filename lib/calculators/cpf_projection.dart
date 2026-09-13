import '../core/calculator.dart';
import '../core/calculator.dart' as calc;
import '../core/money.dart';
import '../rules/sg_rules.dart';

/// Projects CPF Ordinary, Special/Retirement and MediSave balances forward.
///
/// This models the rules that make a generic compound-interest tool wrong:
///
///   * contributions are capped at the Ordinary Wage ceiling;
///   * allocation between accounts shifts as the member crosses age bands;
///   * MediSave is capped at the Basic Healthcare Sum, and the excess
///     overflows — to SA below 55, to RA from 55, and on to OA once the
///     Retirement Account holds the Full Retirement Sum;
///   * at 55 the Special Account closes and a Retirement Account is formed
///     from SA first and then OA, up to the FRS;
///   * interest accrues monthly and is credited annually, including the extra
///     interest on the first tiers of combined balances.
///
/// Every rate and limit comes from the ruleset, which is primary-sourced.
class Accounts {
  double oa;
  double sa;
  double ma;
  double ra;
  Accounts(this.oa, this.sa, this.ma, this.ra);
  double get total => oa + sa + ma + ra;
}

/// Place one month of contribution, honouring the BHS and FRS ceilings.
void allocateContribution(Accounts a, double amount, int age, SgRules rules) {
  final share = rules.allocationForAge(age);
  final isPost55 = age >= 55;

  // MediSave first, capped at the Basic Healthcare Sum.
  var toMa = amount * share.ma;
  final maRoom = rules.cpfBasicHealthcareSum - a.ma;
  final room = maRoom > 0 ? maRoom : 0.0;
  final maOverflow = toMa > room ? toMa - room : 0.0;
  toMa -= maOverflow;
  a.ma += toMa;

  // The retirement leg: SA below 55, RA from 55 and capped at the FRS.
  var toRetirement = amount * share.sa + maOverflow;
  if (isPost55) {
    final raRoomRaw = rules.cpfFullRetirementSum - a.ra;
    final raRoom = raRoomRaw > 0 ? raRoomRaw : 0.0;
    final raOverflow = toRetirement > raRoom ? toRetirement - raRoom : 0.0;
    a.ra += toRetirement - raOverflow;
    toRetirement = raOverflow;
  } else {
    a.sa += toRetirement;
    toRetirement = 0;
  }

  // Whatever remains lands in the Ordinary Account, which has no ceiling.
  a.oa += amount * share.oa + toRetirement;
}

/// One month of interest, including the extra-interest tiers.
///
/// Extra interest applies to COMBINED balances in a fixed order — OA first,
/// subject to its own sub-cap, then the rest — which is what makes it tiered
/// rather than a flat bonus.
double monthlyInterest(Accounts a, int age, SgRules rules) {
  double m(double annualPct) => annualPct / 100 / 12;

  var interest =
      a.oa * m(rules.cpfOaInterestPct) +
      a.sa * m(rules.cpfSaInterestPct) +
      a.ma * m(rules.cpfMaInterestPct) +
      a.ra * m(rules.cpfSaInterestPct);

  final oaEligible = a.oa < rules.cpfExtraInterestOaCap
      ? a.oa
      : rules.cpfExtraInterestOaCap;
  final rest = a.sa + a.ra + a.ma;

  if (age < 55) {
    var room = rules.cpfExtraInterestCap;
    final fromOa = oaEligible < room ? oaEligible : room;
    room -= fromOa;
    final fromRest = rest < room ? rest : room;
    interest += (fromOa + fromRest) * m(rules.cpfExtraInterestPct);
  } else {
    // +2% on the first $30,000, then +1% on the next $30,000.
    final eligible = oaEligible + rest;
    final tier1 = eligible < rules.cpfExtraInterestCap55
        ? eligible
        : rules.cpfExtraInterestCap55;
    final remainingRaw = eligible - tier1;
    final remaining = remainingRaw > 0 ? remainingRaw : 0.0;
    final tier2 = remaining < rules.cpfExtraInterestCap55
        ? remaining
        : rules.cpfExtraInterestCap55;
    interest +=
        tier1 * m(rules.cpfExtraInterestPct55) +
        tier2 * m(rules.cpfExtraInterestPct);
  }
  return interest;
}

/// Move anything above the MediSave ceiling out to the retirement leg, then
/// to OA. The BHS caps the BALANCE, not just contributions, so interest
/// credited into MA is swept out too — without this MediSave drifts far above
/// the ceiling over a long projection.
void sweepAboveCeilings(Accounts a, int age, SgRules rules) {
  final excess = a.ma - rules.cpfBasicHealthcareSum;
  if (excess <= 0) return;
  a.ma = rules.cpfBasicHealthcareSum;

  if (age >= 55) {
    final raRoomRaw = rules.cpfFullRetirementSum - a.ra;
    final raRoom = raRoomRaw > 0 ? raRoomRaw : 0.0;
    final toRa = excess < raRoom ? excess : raRoom;
    a.ra += toRa;
    a.oa += excess - toRa;
  } else {
    a.sa += excess;
  }
}

/// Credit a year of interest in proportion to the balances that earned it.
void creditInterest(Accounts a, double interest) {
  final base = a.total;
  if (base <= 0) return;
  final oaShare = a.oa / base;
  final saShare = a.sa / base;
  final maShare = a.ma / base;
  final raShare = a.ra / base;
  a.oa += interest * oaShare;
  a.sa += interest * saShare;
  a.ma += interest * maShare;
  a.ra += interest * raShare;
}

/// At 55 the Special Account closes and the Retirement Account is formed from
/// SA first, then OA, up to the Full Retirement Sum.
void formRetirementAccount(Accounts a, SgRules rules) {
  final target = rules.cpfFullRetirementSum;
  final fromSa = a.sa < target ? a.sa : target;
  a.ra += fromSa;
  a.sa -= fromSa;
  final stillNeeded = target - a.ra;
  if (stillNeeded > 0) {
    final fromOa = a.oa < stillNeeded ? a.oa : stillNeeded;
    a.ra += fromOa;
    a.oa -= fromOa;
  }
  a.oa += a.sa;
  a.sa = 0;
}

final cpfProjectionCalculator = Calculator(
  id: 'cpf_projection',
  name: 'CPF OA / SA / MA projection',
  description: 'Balances by account, with BHS and FRS ceilings applied',
  question: Question.later,
  sgSpecific: true,
  inputs: [
    const CalcInput(
      key: 'age',
      label: 'Current age',
      kind: InputKind.integer,
      initial: 32.0,
      min: 16,
      max: 70,
      unit: 'years',
    ),
    CalcInput(
      key: 'salary',
      label: 'Monthly salary',
      kind: InputKind.money,
      initial: Money.tryParse('7000')!,
      min: 0,
    ),
    CalcInput(
      key: 'oa',
      label: 'Ordinary Account now',
      kind: InputKind.money,
      initial: Money.tryParse('48000')!,
      min: 0,
    ),
    CalcInput(
      key: 'sa',
      label: 'Special Account now',
      kind: InputKind.money,
      initial: Money.tryParse('32000')!,
      min: 0,
    ),
    CalcInput(
      key: 'ma',
      label: 'MediSave now',
      kind: InputKind.money,
      initial: Money.tryParse('26000')!,
      min: 0,
    ),
    const CalcInput(
      key: 'toAge',
      label: 'Project to age',
      kind: InputKind.integer,
      initial: 55.0,
      min: 20,
      max: 80,
      unit: 'years',
    ),
    const CalcInput(
      key: 'growth',
      label: 'Salary growth',
      kind: InputKind.percent,
      initial: 2.5,
      min: 0,
      max: 10,
      unit: '% p.a.',
    ),
  ],
  compute: (v, rules) {
    final age = v.integer('age');
    final toAge = v.integer('toAge');
    final growth = v.number('growth') / 100;
    var salary = v.money('salary').asDouble;

    if (toAge <= age) {
      return const CalcResult.failed(
        'Project to an age later than your current age.',
      );
    }

    final opening =
        v.money('oa').asDouble +
        v.money('sa').asDouble +
        v.money('ma').asDouble;
    final a = Accounts(
      v.money('oa').asDouble,
      v.money('sa').asDouble,
      v.money('ma').asDouble,
      0,
    );

    final oaCurve = <SeriesPoint>[];
    final retCurve = <SeriesPoint>[];
    final maCurve = <SeriesPoint>[];
    var contributed = 0.0;
    var interestEarned = 0.0;
    var bhsReachedAt = 0;

    for (var year = age; year < toAge; year++) {
      if (year == 55) formRetirementAccount(a, rules);

      final rates = rules.contributionForAge(year);
      final totalPct = (rates.employee + rates.employer) / 100;
      final capped = salary > rules.cpfOrdinaryWageCeiling
          ? rules.cpfOrdinaryWageCeiling
          : salary;

      var yearInterest = 0.0;
      for (var month = 0; month < 12; month++) {
        final contribution = capped * totalPct;
        contributed += contribution;
        allocateContribution(a, contribution, year, rules);
        sweepAboveCeilings(a, year, rules);
        yearInterest += monthlyInterest(a, year, rules);
      }
      creditInterest(a, yearInterest);
      sweepAboveCeilings(a, year, rules);
      interestEarned += yearInterest;

      if (bhsReachedAt == 0 && a.ma >= rules.cpfBasicHealthcareSum - 0.5) {
        bhsReachedAt = year;
      }

      final x = (year - age + 1).toDouble();
      oaCurve.add(SeriesPoint(x, a.oa));
      retCurve.add(SeriesPoint(x, a.sa + a.ra));
      maCurve.add(SeriesPoint(x, a.ma));

      salary *= 1 + growth;
    }

    final post55 = toAge > 55;
    final total = Money.fromDouble(a.total);

    return CalcResult(
      primaryBetter: Better.higher,
      primaryLabel: 'TOTAL CPF AT $toAge',
      primaryValue: total.sgd0,
      secondary: [
        Metric(
          'Ordinary Account',
          Money.fromDouble(a.oa).sgd0,
          better: Better.higher,
        ),
        Metric(
          post55 ? 'Retirement Account' : 'Special Account',
          Money.fromDouble(post55 ? a.ra : a.sa).sgd0,
          better: Better.higher,
        ),
        Metric('MediSave', Money.fromDouble(a.ma).sgd0, better: Better.higher),
        Metric(
          'Interest earned',
          Money.fromDouble(interestEarned).sgd0,
          tone: Tone.positive,
          better: Better.higher,
        ),
      ],
      series: [
        Series('OA', oaCurve, tone: Tone.neutral, xUnit: 'yr'),
        Series(
          post55 ? 'RA' : 'SA',
          retCurve,
          tone: Tone.positive,
          xUnit: 'yr',
        ),
        Series('MA', maCurve, tone: Tone.warn, xUnit: 'yr'),
      ],
      delta: DeltaNote(
        bhsReachedAt > 0
            ? 'MediSave hits the Basic Healthcare Sum at $bhsReachedAt; '
                  'contributions above it overflow to '
                  '${bhsReachedAt >= 55 ? "the Retirement Account" : "the Special Account"}'
            : '${Money.fromDouble(contributed).sgd0} contributed over '
                  '${toAge - age} years, '
                  '${Money.fromDouble(interestEarned).sgd0} from interest',
        tone: bhsReachedAt > 0 ? Tone.warn : Tone.positive,
      ),
      explain: Explanation(
        formula:
            'Each month: contribution → MA up to the BHS, overflow → SA '
            '(or RA up to the FRS from 55), remainder → OA.\n'
            'Interest accrues monthly and is credited yearly.',
        substituted:
            'Opening    ${Money.fromDouble(opening).sgd0}\n'
            'Contributed ${Money.fromDouble(contributed).sgd0}\n'
            'Interest   ${Money.fromDouble(interestEarned).sgd0}\n'
            'Closing    ${total.sgd0}',
        assumptions: [
          (
            label: 'Basic Healthcare Sum',
            value: Money.fromDouble(rules.cpfBasicHealthcareSum).sgd0,
          ),
          (
            label: 'Full Retirement Sum',
            value: Money.fromDouble(rules.cpfFullRetirementSum).sgd0,
          ),
          (label: 'BHS growth', value: 'Held flat'),
          (label: 'Interest', value: 'Monthly, credited yearly'),
          (label: 'Extra interest', value: 'First 60k, OA capped at 20k'),
          (
            label: 'Wage ceiling',
            value: Money.fromDouble(rules.cpfOrdinaryWageCeiling).sgd0,
          ),
        ],
        footnote:
            'The Basic Healthcare Sum is held flat here. CPF raises it '
            'most years, so real MediSave would run higher and less would '
            'overflow. Excludes housing withdrawals, top-ups and CPF LIFE. '
            'Rates last verified ${calc.monthYear(rules.verifiedOn)}.',
      ),
    );
  },
);

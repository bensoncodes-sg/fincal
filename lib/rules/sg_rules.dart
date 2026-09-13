/// Singapore statutory ruleset.
///
/// IMPORTANT: every figure here is DATA, not logic. It carries an effective
/// date and a verification date, it is surfaced to the user in Settings, and
/// it is overridable at runtime. Rates change; a calculator that is
/// confidently wrong about a statutory figure is worse than one that does
/// not offer the tool at all.
///
/// Before relying on these in production, re-verify against the primary
/// sources listed in [SgRules.sources] and update [verifiedOn].
library;

class Band {
  /// Upper bound of this band, or null for "and above".
  final double? upTo;
  final double ratePct;
  const Band(this.upTo, this.ratePct);
}

class SgRules {
  final String version;
  final DateTime effectiveFrom;
  final DateTime verifiedOn;

  // --- Lending ---
  final double tdsrCeilingPct;
  final double msrCeilingPct;
  final double stressTestFloorPct;

  /// LTV for a first housing loan from a bank, and the minimum share of the
  /// down payment that must be paid in cash.
  final double bankLtvPct;
  final double bankMinCashPct;

  /// The reduced LTV that applies when the loan runs too long or too late in
  /// life. Missing this rule is how an affordability tool quietly overstates
  /// what someone can borrow.
  final double reducedLtvPct;

  /// Full LTV requires the tenure to be at or under these limits AND the loan
  /// to finish by [ltvMaxEndAge].
  final double ltvMaxTenureYearsPrivate;
  final double ltvMaxTenureYearsHdb;
  final int ltvMaxEndAge;
  final double hdbLtvPct;
  final double hdbConcessionaryRatePct;

  // --- CPF ---
  final double cpfOrdinaryWageCeiling;
  final double cpfAnnualWageCeiling;
  final double cpfEmployeePct;
  final double cpfEmployerPct;
  final double cpfOaShare;
  final double cpfSaShare;
  final double cpfMaShare;
  final double cpfOaInterestPct;
  final double cpfSaInterestPct;
  final double cpfMaInterestPct;

  /// Basic Healthcare Sum — the MediSave ceiling. Contributions that would
  /// take MA above this overflow to SA (below 55) or RA (55 and above).
  final double cpfBasicHealthcareSum;

  /// Full Retirement Sum. From 55, contributions go to the Retirement Account
  /// up to the FRS and to the Ordinary Account thereafter.
  final double cpfFullRetirementSum;
  final double cpfBasicRetirementSum;

  /// Extra interest. Below 55: +1% on the first $60,000 of combined balances,
  /// of which at most $20,000 may come from OA. From 55: +2% on the first
  /// $30,000 and +1% on the next $30,000.
  final double cpfExtraInterestPct;
  final double cpfExtraInterestCap;
  final double cpfExtraInterestOaCap;
  final double cpfExtraInterestPct55;
  final double cpfExtraInterestCap55;

  // --- Tax ---
  final List<Band> incomeTaxBands;
  final double personalReliefCap;
  final double srsCapCitizen;
  final double srsCapForeigner;

  // --- Property ---
  final List<Band> bsdBands;
  final Map<String, List<double>> absdByProfile;

  // --- Consumption ---
  final double gstPct;

  const SgRules({
    required this.version,
    required this.effectiveFrom,
    required this.verifiedOn,
    required this.tdsrCeilingPct,
    required this.msrCeilingPct,
    required this.stressTestFloorPct,
    required this.bankLtvPct,
    required this.bankMinCashPct,
    required this.reducedLtvPct,
    required this.ltvMaxTenureYearsPrivate,
    required this.ltvMaxTenureYearsHdb,
    required this.ltvMaxEndAge,
    required this.hdbLtvPct,
    required this.hdbConcessionaryRatePct,
    required this.cpfOrdinaryWageCeiling,
    required this.cpfAnnualWageCeiling,
    required this.cpfEmployeePct,
    required this.cpfEmployerPct,
    required this.cpfOaShare,
    required this.cpfSaShare,
    required this.cpfMaShare,
    required this.cpfOaInterestPct,
    required this.cpfSaInterestPct,
    required this.cpfMaInterestPct,
    required this.cpfBasicHealthcareSum,
    required this.cpfFullRetirementSum,
    required this.cpfBasicRetirementSum,
    required this.cpfExtraInterestPct,
    required this.cpfExtraInterestCap,
    required this.cpfExtraInterestOaCap,
    required this.cpfExtraInterestPct55,
    required this.cpfExtraInterestCap55,
    required this.incomeTaxBands,
    required this.personalReliefCap,
    required this.srsCapCitizen,
    required this.srsCapForeigner,
    required this.bsdBands,
    required this.absdByProfile,
    required this.gstPct,
  });

  static const Map<String, String> sources = {
    'tdsr': 'mas.gov.sg — residential property loan rules',
    'ltv': 'mas.gov.sg — loan-to-value limits',
    'cpf':
        'cpf.gov.sg — CPFcontributionratesfrom1Jan2026.pdf and '
        'CPFAllocationRatesfromJanuary2026.pdf (primary, read 12 Sep 2026)',
    'cpfBhs':
        'moh.gov.sg newsroom — CPF interest rates from 1 Jan to 31 Mar '
        '2026 and Basic Healthcare Sum for 2026 (primary, read 13 Sep 2026)',
    'cpfFrs':
        'mom.gov.sg — Basic Retirement Sums for CPF Members Reaching '
        'Age 55 from 2023 to 2027 (primary, read 13 Sep 2026)',
    'incomeTax': 'iras.gov.sg — individual income tax rates',
    'stampDuty': 'iras.gov.sg — buyer stamp duty and ABSD',
    'gst': 'iras.gov.sg — goods and services tax',
  };

  /// Shipping defaults. Treat as a starting point, not an authority.
  static final SgRules defaults = SgRules(
    version: '2026.09',
    effectiveFrom: DateTime(2026, 1, 1),
    verifiedOn: DateTime(2026, 9, 12),

    tdsrCeilingPct: 55,
    msrCeilingPct: 30,
    stressTestFloorPct: 4.0,
    bankLtvPct: 75,
    bankMinCashPct: 5,
    reducedLtvPct: 55,
    ltvMaxTenureYearsPrivate: 30,
    ltvMaxTenureYearsHdb: 25,
    ltvMaxEndAge: 65,
    hdbLtvPct: 75,
    hdbConcessionaryRatePct: 2.6,

    cpfOrdinaryWageCeiling: 8000,
    cpfAnnualWageCeiling: 102000,
    cpfEmployeePct: 20,
    cpfEmployerPct: 17,
    // Allocation of the total contribution for members aged 35 and below.
    cpfOaShare: 0.6217,
    cpfSaShare: 0.1621,
    cpfMaShare: 0.2162,
    cpfOaInterestPct: 2.5,
    cpfSaInterestPct: 4.0,
    cpfMaInterestPct: 4.0,

    // PRIMARY: MOH/CPF release "CPF interest rates from 1 January to
    // 31 March 2026 and Basic Healthcare Sum for 2026", read 13 Sep 2026.
    cpfBasicHealthcareSum: 79000,
    cpfExtraInterestPct: 1.0,
    cpfExtraInterestCap: 60000,
    cpfExtraInterestOaCap: 20000,
    cpfExtraInterestPct55: 2.0,
    cpfExtraInterestCap55: 30000,

    // PRIMARY: MOM factsheet "Basic Retirement Sums for CPF Members
    // Reaching Age 55 from 2023 to 2027", read 13 Sep 2026. FRS is twice
    // the BRS. Figures are for the cohort reaching 55 in 2026.
    cpfBasicRetirementSum: 110200,
    cpfFullRetirementSum: 220400,

    incomeTaxBands: const [
      Band(20000, 0),
      Band(30000, 2),
      Band(40000, 3.5),
      Band(80000, 7),
      Band(120000, 11.5),
      Band(160000, 15),
      Band(200000, 18),
      Band(240000, 19),
      Band(280000, 19.5),
      Band(320000, 20),
      Band(500000, 22),
      Band(1000000, 23),
      Band(null, 24),
    ],
    personalReliefCap: 80000,
    srsCapCitizen: 15300,
    srsCapForeigner: 35700,

    bsdBands: const [
      Band(180000, 1),
      Band(360000, 2),
      Band(1000000, 3),
      Band(1500000, 4),
      Band(3000000, 5),
      Band(null, 6),
    ],
    absdByProfile: const {
      'Citizen': [0, 20, 30],
      'PR': [5, 30, 35],
      'Foreigner': [60, 60, 60],
    },

    gstPct: 9,
  );

  /// True when the ruleset has not been re-verified in over 180 days.
  bool get isStale => DateTime.now().difference(verifiedOn).inDays > 180;

  int get daysSinceVerified => DateTime.now().difference(verifiedOn).inDays;

  /// Progressive tax on a marginal-band table. Returns dollars.
  double taxOn(double chargeableIncome) {
    if (chargeableIncome <= 0) return 0;
    var tax = 0.0;
    var lower = 0.0;
    for (final b in incomeTaxBands) {
      final upper = b.upTo ?? double.infinity;
      if (chargeableIncome <= lower) break;
      final slice =
          (chargeableIncome < upper ? chargeableIncome : upper) - lower;
      if (slice > 0) tax += slice * b.ratePct / 100;
      lower = upper;
      if (!upper.isFinite) break;
    }
    return tax;
  }

  /// Marginal rate at a given chargeable income.
  double marginalRate(double chargeableIncome) {
    if (chargeableIncome <= 0) return 0;
    var lower = 0.0;
    for (final b in incomeTaxBands) {
      final upper = b.upTo ?? double.infinity;
      if (chargeableIncome > lower && chargeableIncome <= upper) {
        return b.ratePct;
      }
      lower = upper;
    }
    return incomeTaxBands.last.ratePct;
  }

  /// Buyer stamp duty on the higher of price or market value.
  double bsdOn(double price) {
    if (price <= 0) return 0;
    var duty = 0.0;
    var lower = 0.0;
    for (final b in bsdBands) {
      final upper = b.upTo ?? double.infinity;
      if (price <= lower) break;
      final slice = (price < upper ? price : upper) - lower;
      if (slice > 0) duty += slice * b.ratePct / 100;
      lower = upper;
      if (!upper.isFinite) break;
    }
    return duty;
  }

  /// ABSD rate for a buyer profile and the ordinal of the property.
  double absdRate(String profile, int propertyNumber) {
    final tiers = absdByProfile[profile] ?? const [0, 0, 0];
    final idx = (propertyNumber - 1).clamp(0, tiers.length - 1);
    return tiers[idx].toDouble();
  }

  /// Loan-to-value for a first housing loan, and why.
  ///
  /// Full LTV needs BOTH a short-enough tenure and a loan that finishes by
  /// [ltvMaxEndAge]. Fail either and the limit drops to [reducedLtvPct],
  /// which changes the maximum price substantially.
  ({double ltv, String reason}) ltvFor({
    required int age,
    required double tenureYears,
    required bool isHdb,
  }) {
    final maxTenure = isHdb ? ltvMaxTenureYearsHdb : ltvMaxTenureYearsPrivate;
    final endAge = age + tenureYears;
    final tooLong = tenureYears > maxTenure;
    final tooLate = endAge > ltvMaxEndAge;

    if (!tooLong && !tooLate) {
      return (ltv: bankLtvPct, reason: 'Full LTV');
    }
    if (tooLong && tooLate) {
      return (
        ltv: reducedLtvPct,
        reason:
            'Tenure over ${maxTenure.toStringAsFixed(0)} yrs and ends '
            'at ${endAge.toStringAsFixed(0)}',
      );
    }
    if (tooLong) {
      return (
        ltv: reducedLtvPct,
        reason: 'Tenure over ${maxTenure.toStringAsFixed(0)} yrs',
      );
    }
    return (
      ltv: reducedLtvPct,
      reason: 'Loan ends at ${endAge.toStringAsFixed(0)}, past $ltvMaxEndAge',
    );
  }

  /// CPF allocation shares by age band. Shares always sum to 1.
  /// PRIMARY SOURCE: CPF Board, "CPF Allocation Rates from 1 January 2026"
  /// (CPFAllocationRatesfromJanuary2026.pdf), read 12 Sep 2026.
  ///
  /// Bands read "above X to Y", so age 55 falls in "Above 50 - 55". From 55
  /// the second account is the Retirement Account rather than the Special
  /// Account; this model keeps the field name `sa` for both, which is a
  /// simplification worth knowing about.
  ({double oa, double sa, double ma}) allocationForAge(int age) {
    if (age <= 35) return (oa: 0.6217, sa: 0.1621, ma: 0.2162);
    if (age <= 45) return (oa: 0.5677, sa: 0.1891, ma: 0.2432);
    if (age <= 50) return (oa: 0.5136, sa: 0.2162, ma: 0.2702);
    if (age <= 55) return (oa: 0.4055, sa: 0.3108, ma: 0.2837);
    if (age <= 60) return (oa: 0.353, sa: 0.3382, ma: 0.3088);
    if (age <= 65) return (oa: 0.14, sa: 0.44, ma: 0.42);
    if (age <= 70) return (oa: 0.0607, sa: 0.303, ma: 0.6363);
    return (oa: 0.08, sa: 0.08, ma: 0.84);
  }

  /// Contribution rates by age, for monthly wages above $750.
  ///
  /// PRIMARY SOURCE: CPF Board, "CPF Contribution Rate Table from 1 January
  /// 2026" (CPFcontributionratesfrom1Jan2026.pdf), read 12 Sep 2026. The
  /// published table gives the TOTAL and the EMPLOYEE share; the employer
  /// share here is total minus employee.
  ///
  /// Band edges matter: the first band is "55 & below", so an employee who is
  /// exactly 55 contributes at 37%, not 34%.
  ({double employee, double employer}) contributionForAge(int age) {
    if (age <= 55) return (employee: 20, employer: 17); // total 37%
    if (age <= 60) return (employee: 18, employer: 16); // total 34%
    if (age <= 65) return (employee: 12.5, employer: 12.5); // total 25%
    if (age <= 70) return (employee: 7.5, employer: 9); // total 16.5%
    return (employee: 5, employer: 7.5); // total 12.5%
  }

  SgRules copyWith({
    double? tdsrCeilingPct,
    double? msrCeilingPct,
    double? stressTestFloorPct,
    double? gstPct,
    DateTime? verifiedOn,
  }) => SgRules(
    version: version,
    effectiveFrom: effectiveFrom,
    verifiedOn: verifiedOn ?? this.verifiedOn,
    tdsrCeilingPct: tdsrCeilingPct ?? this.tdsrCeilingPct,
    msrCeilingPct: msrCeilingPct ?? this.msrCeilingPct,
    stressTestFloorPct: stressTestFloorPct ?? this.stressTestFloorPct,
    bankLtvPct: bankLtvPct,
    bankMinCashPct: bankMinCashPct,
    reducedLtvPct: reducedLtvPct,
    ltvMaxTenureYearsPrivate: ltvMaxTenureYearsPrivate,
    ltvMaxTenureYearsHdb: ltvMaxTenureYearsHdb,
    ltvMaxEndAge: ltvMaxEndAge,
    hdbLtvPct: hdbLtvPct,
    hdbConcessionaryRatePct: hdbConcessionaryRatePct,
    cpfOrdinaryWageCeiling: cpfOrdinaryWageCeiling,
    cpfAnnualWageCeiling: cpfAnnualWageCeiling,
    cpfEmployeePct: cpfEmployeePct,
    cpfEmployerPct: cpfEmployerPct,
    cpfOaShare: cpfOaShare,
    cpfSaShare: cpfSaShare,
    cpfMaShare: cpfMaShare,
    cpfOaInterestPct: cpfOaInterestPct,
    cpfSaInterestPct: cpfSaInterestPct,
    cpfMaInterestPct: cpfMaInterestPct,
    cpfBasicHealthcareSum: cpfBasicHealthcareSum,
    cpfFullRetirementSum: cpfFullRetirementSum,
    cpfBasicRetirementSum: cpfBasicRetirementSum,
    cpfExtraInterestPct: cpfExtraInterestPct,
    cpfExtraInterestCap: cpfExtraInterestCap,
    cpfExtraInterestOaCap: cpfExtraInterestOaCap,
    cpfExtraInterestPct55: cpfExtraInterestPct55,
    cpfExtraInterestCap55: cpfExtraInterestCap55,
    incomeTaxBands: incomeTaxBands,
    personalReliefCap: personalReliefCap,
    srsCapCitizen: srsCapCitizen,
    srsCapForeigner: srsCapForeigner,
    bsdBands: bsdBands,
    absdByProfile: absdByProfile,
    gstPct: gstPct ?? this.gstPct,
  );
}

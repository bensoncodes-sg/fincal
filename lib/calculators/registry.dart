import '../core/calculator.dart';

import 'affordability.dart';
import 'cpf_projection.dart';
import 'hdb_vs_bank.dart';
import 'income_tax.dart';
import 'mortgage.dart';
import 'refinance.dart';
import 'stamp_duty.dart';
import 'tvm.dart';
import 'quick_math.dart';
import 'borrowing.dart';
import 'investing.dart';

/// Every calculator in the app. Adding the ninth means adding one import and
/// one list entry — no screen, no renderer, no export code changes.
final List<Calculator> allCalculators = [
  affordabilityCalculator,
  mortgageCalculator,
  hdbVsBankCalculator,
  refinanceCalculator,
  cpfProjectionCalculator,
  tvmCalculator,
  incomeTaxCalculator,
  stampDutyCalculator,
  ...borrowingCalculators,
  ...investingCalculators,
  ...quickMathCalculators,
];

Calculator? calculatorById(String id) {
  for (final c in allCalculators) {
    if (c.id == id) return c;
  }
  return null;
}

List<Calculator> calculatorsFor(Question q) =>
    allCalculators.where((c) => c.question == q).toList();

/// Tool counts shown on the home screen. These count what is BUILT, not what
/// is planned — a home screen that promises eleven tools and delivers four is
/// the first lie an app tells.
int builtCountFor(Question q) => calculatorsFor(q).length;

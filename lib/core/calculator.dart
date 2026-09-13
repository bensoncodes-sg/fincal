/// A calculator is DATA, not a screen.
///
/// Every tool in Basis is a [Calculator]: a list of typed inputs, a pure
/// compute function, and an explanation. One renderer walks this structure,
/// so save, chart, export, compare and "show the math" are each built once
/// and every calculator inherits them. Adding the 49th tool costs one file
/// and zero changes anywhere else.
library;

import 'finance.dart';
import 'money.dart';
import '../rules/sg_rules.dart';

/// `decimal` is a plain number that may need more than two decimal places,
/// such as an SGX share price of 0.955 — which `money` would round to cents.
enum InputKind { money, percent, years, months, integer, choice, date, decimal }

enum Tone { neutral, positive, negative, warn }

/// Which direction is better for a figure, when two scenarios are compared.
/// Declared by the calculator rather than inferred, because "lower is better"
/// is true of interest paid and false of interest earned, and guessing that
/// from a label is how a comparison screen starts lying.
enum Better { lower, higher, none }

/// The six intent groups. People arrive with a question, not a formula name.
enum Question {
  afford('Can I afford it?', 'What you can responsibly commit to'),
  loanCost('What will this loan cost?', 'The true price of borrowing'),
  later('Will I have enough later?', 'Projections to a future date'),
  worthIt('Is this investment worth it?', 'Returns, yields and comparisons'),
  takeHome('What do I actually take home?', 'Tax, CPF and net pay'),
  quick('Quick math', 'Everyday conversions');

  const Question(this.label, this.blurb);
  final String label;
  final String blurb;
}

class CalcInput {
  final String key;
  final String label;
  final InputKind kind;
  final String? unit;
  final double? min;
  final double? max;
  final Object initial;
  final List<String> choices;
  final String? hint;

  /// When set, this input is computed from the others and shown read-only.
  final bool derived;

  /// Show this input only while another choice input holds a given value,
  /// so a mode switch does not leave a field on screen that is being ignored.
  final ({String key, String value})? showWhen;

  bool appliesTo(Map<String, Object> values) =>
      showWhen == null || values[showWhen!.key]?.toString() == showWhen!.value;

  const CalcInput({
    required this.key,
    required this.label,
    required this.kind,
    required this.initial,
    this.unit,
    this.min,
    this.max,
    this.choices = const [],
    this.hint,
    this.derived = false,
    this.showWhen,
  });
}

class Metric {
  final String label;
  final String value;
  final Tone tone;
  final Better better;

  const Metric(
    this.label,
    this.value, {
    this.tone = Tone.neutral,
    this.better = Better.none,
  });
}

class SeriesPoint {
  final double x;
  final double y;
  const SeriesPoint(this.x, this.y);
}

class Series {
  final String name;
  final List<SeriesPoint> points;
  final Tone tone;

  /// Unit of the x axis, e.g. 'yr' or 'mo'. Charts used to assume years,
  /// which labelled a tax-against-income curve "160 yr". A series that is not
  /// measured in time leaves this null and the axis shows the bare number.
  final String? xUnit;

  const Series(this.name, this.points, {this.tone = Tone.neutral, this.xUnit});
}

class Explanation {
  final String formula;
  final String substituted;
  final List<({String label, String value})> assumptions;
  final String? footnote;

  const Explanation({
    required this.formula,
    required this.substituted,
    required this.assumptions,
    this.footnote,
  });
}

class DeltaNote {
  final String text;
  final Tone tone;
  const DeltaNote(this.text, {this.tone = Tone.positive});
}

class CalcResult {
  /// The one figure the user came for.
  final String primaryLabel;
  final String primaryValue;

  /// Direction of improvement for the headline figure, used by Compare.
  final Better primaryBetter;

  /// Up to four supporting metrics, shown at roughly half the size.
  final List<Metric> secondary;

  final List<Series> series;
  final List<ScheduleRow> schedule;
  final DeltaNote? delta;
  final Explanation? explain;

  /// Set when the inputs cannot produce an answer. When this is non-null the
  /// UI shows the message instead of a number — never a plausible guess.
  final String? error;

  const CalcResult({
    required this.primaryLabel,
    required this.primaryValue,
    this.primaryBetter = Better.none,
    this.secondary = const [],
    this.series = const [],
    this.schedule = const [],
    this.delta,
    this.explain,
    this.error,
  });

  const CalcResult.failed(String message)
    : primaryLabel = '',
      primaryValue = '—',
      primaryBetter = Better.none,
      secondary = const [],
      series = const [],
      schedule = const [],
      delta = null,
      explain = null,
      error = message;
}

/// Values keyed by [CalcInput.key]. Money inputs arrive as [Money], rates and
/// counts as [double], choices as [String].
typedef Inputs = Map<String, Object>;

class Calculator {
  final String id;
  final String name;
  final String description;
  final Question question;

  /// True for tools the US-centric incumbents structurally cannot offer.
  final bool sgSpecific;

  final List<CalcInput> inputs;
  final CalcResult Function(Inputs values, SgRules rules) compute;

  /// Optional: which input this tool solves for, e.g. TVM.
  final List<String> solveFor;

  const Calculator({
    required this.id,
    required this.name,
    required this.description,
    required this.question,
    required this.inputs,
    required this.compute,
    this.sgSpecific = false,
    this.solveFor = const [],
  });

  Inputs get defaults => {for (final i in inputs) i.key: i.initial};
}

// ---------------------------------------------------------------------------
// Typed readers — keep calculators free of casting noise
// ---------------------------------------------------------------------------

extension InputReader on Inputs {
  Money money(String key) {
    final v = this[key];
    if (v is Money) return v;
    if (v is num) return Money.fromDouble(v.toDouble());
    return Money.zero;
  }

  double number(String key) {
    final v = this[key];
    if (v is num) return v.toDouble();
    if (v is Money) return v.asDouble;
    return 0;
  }

  int integer(String key) => number(key).round();

  String choice(String key) => (this[key] ?? '').toString();

  DateTime date(String key) {
    final v = this[key];
    return v is DateTime ? v : DateTime.now();
  }
}

String pct(double v, {int dp = 2}) => '${v.toStringAsFixed(dp)}%';

String monthsAsTerm(int months) {
  final y = months ~/ 12;
  final m = months % 12;
  if (y == 0) return '$m mo';
  if (m == 0) return '$y yr';
  return '${y}y ${m}m';
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String monthYear(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';
String shortDate(DateTime d) =>
    '${_monthNames[d.month - 1]} ${d.year.toString().substring(2)}';

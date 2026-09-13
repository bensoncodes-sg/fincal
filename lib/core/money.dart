/// Money is stored as integer minor units (cents). Never a double.
///
/// Every arithmetic path in Basis runs through this type so that a 300-row
/// amortization schedule cannot accumulate binary-float drift.
library;

import 'dart:math' as math;

/// Immutable by construction: every field is final.
class Money implements Comparable<Money> {
  /// Signed minor units. S$3,312.39 is stored as 331239.
  final int cents;

  const Money(this.cents);

  static const Money zero = Money(0);

  /// Build from a decimal amount. Rounds half-even at construction.
  factory Money.fromDouble(double amount) =>
      Money(_roundHalfEven(amount * 100));

  /// Parse "1,234.56" / "S$ 1,234.56" / "-1234.5" without going through
  /// double for the fractional part.
  static Money? tryParse(String raw) {
    final s = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (s.isEmpty || s == '-' || s == '.') return null;
    // A minus sign is only meaningful once, at the front. Without this
    // "--5" parsed as 5 rather than being rejected.
    final firstMinus = s.indexOf('-');
    if (firstMinus > 0 || s.lastIndexOf('-') != firstMinus) return null;
    final neg = s.startsWith('-');
    final body = neg ? s.substring(1) : s;
    if (body.isEmpty) return null;
    final parts = body.split('.');
    if (parts.length > 2) return null;
    final whole = parts[0].isEmpty ? 0 : int.tryParse(parts[0]);
    if (whole == null) return null;
    var frac = 0;
    if (parts.length == 2) {
      var f = parts[1];
      if (f.length > 2) {
        // Round beyond cents using the same half-even rule as all other
        // Money construction paths. A tie only rounds up when the retained
        // cent value is odd; any non-zero tail makes it strictly above half.
        final retained = int.tryParse(f.substring(0, 2).padRight(2, '0')) ?? 0;
        final third = int.tryParse(f.substring(2, 3)) ?? 0;
        final tailNonZero = f.substring(3).split('').any((d) => d != '0');
        final up = third > 5 || (third == 5 && (tailNonZero || retained.isOdd));
        frac = retained + (up ? 1 : 0);
      } else {
        frac = int.tryParse(f.padRight(2, '0')) ?? 0;
      }
    }
    final normalizedWhole = whole + frac ~/ 100;
    final normalizedFrac = frac % 100;
    final total = normalizedWhole * 100 + normalizedFrac;
    return Money(neg ? -total : total);
  }

  double get asDouble => cents / 100;

  Money operator +(Money o) => Money(cents + o.cents);
  Money operator -(Money o) => Money(cents - o.cents);
  Money operator -() => Money(-cents);

  /// Multiply by a rate, rounding half-even back to whole cents.
  Money scaled(double rate) => Money(_roundHalfEven(cents * rate));

  bool get isNegative => cents < 0;
  bool get isZero => cents == 0;
  Money get abs => Money(cents.abs());

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);
  bool operator <(Money o) => cents < o.cents;
  bool operator <=(Money o) => cents <= o.cents;
  bool operator >(Money o) => cents > o.cents;
  bool operator >=(Money o) => cents >= o.cents;

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;
  @override
  int get hashCode => cents.hashCode;

  /// "3,312.39" — grouping only, no currency symbol.
  String format({int decimals = 2, bool group = true}) {
    final neg = cents < 0;
    final v = cents.abs();
    final whole = v ~/ 100;
    final frac = v % 100;
    var w = whole.toString();
    if (group) {
      final b = StringBuffer();
      for (var i = 0; i < w.length; i++) {
        if (i > 0 && (w.length - i) % 3 == 0) b.write(',');
        b.write(w[i]);
      }
      w = b.toString();
    }
    final sign = neg ? '-' : '';
    if (decimals == 0) {
      // Round to whole dollars for display only.
      final rounded = _roundHalfEven(v / 100);
      var r = rounded.toString();
      if (group) {
        final b = StringBuffer();
        for (var i = 0; i < r.length; i++) {
          if (i > 0 && (r.length - i) % 3 == 0) b.write(',');
          b.write(r[i]);
        }
        r = b.toString();
      }
      return '$sign$r';
    }
    return '$sign$w.${frac.toString().padLeft(2, '0')}';
  }

  /// "S$ 3,312.39"
  String get sgd => 'S\$ ${format()}';
  String get sgd0 => 'S\$ ${format(decimals: 0)}';

  @override
  String toString() => format();
}

/// Banker's rounding. Ties go to the even integer, which keeps a long
/// schedule from drifting upward the way half-up does.
int _roundHalfEven(num value) {
  final floor = value.floor();
  final diff = value - floor;
  if (diff > 0.5) return floor + 1;
  if (diff < 0.5) return floor;
  return floor.isEven ? floor : floor + 1;
}

/// Exposed for the solver and percentage maths.
int roundHalfEven(num value) => _roundHalfEven(value);

/// Round a rate/ratio to n decimal places, half-even.
double roundTo(double v, int places) {
  final f = math.pow(10, places);
  return _roundHalfEven(v * f) / f;
}

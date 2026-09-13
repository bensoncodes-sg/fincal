/// Root finding for rate problems (IRR, APR, implied rate).
///
/// Newton-Raphson converges fast but is not guaranteed on sign-changing
/// cash flows, so every call falls back to bisection. If neither converges
/// we return a failure rather than a plausible-looking wrong number —
/// that distinction is the whole point of this file.
library;

import 'dart:math' as math;

class SolveResult {
  final double? value;
  final int iterations;
  final String? failure;

  const SolveResult.success(this.value, this.iterations) : failure = null;
  const SolveResult.failed(this.failure) : value = null, iterations = 0;

  bool get converged => value != null;
}

const double kTolerance = 1e-10;
const int kMaxIterations = 100;

/// Solve f(x) = 0 near [guess], bracketed by [lo]..[hi].
SolveResult solveRoot(
  double Function(double) f, {
  double guess = 0.1,
  double lo = -0.9999,
  double hi = 10.0,
}) {
  // --- Newton-Raphson with a numeric derivative ---
  var x = guess;
  for (var i = 0; i < kMaxIterations; i++) {
    final fx = f(x);
    if (!fx.isFinite) break;
    if (fx.abs() < kTolerance) return SolveResult.success(x, i + 1);
    const h = 1e-7;
    final d = (f(x + h) - f(x - h)) / (2 * h);
    if (!d.isFinite || d.abs() < 1e-14) break;
    final next = x - fx / d;
    if (!next.isFinite) break;
    if ((next - x).abs() < kTolerance) return SolveResult.success(next, i + 1);
    if (next <= lo || next >= hi) break;
    x = next;
  }

  // --- Bisection fallback ---
  var a = lo, b = hi;
  var fa = f(a), fb = f(b);
  if (!fa.isFinite || !fb.isFinite) {
    return const SolveResult.failed(
      'Function is undefined across the search range.',
    );
  }
  if (fa.sign == fb.sign) {
    // Scan for a sign change before giving up.
    var found = false;
    const steps = 400;
    var prevX = a, prevF = fa;
    for (var i = 1; i <= steps; i++) {
      final cx = a + (b - a) * i / steps;
      final cf = f(cx);
      if (!cf.isFinite) continue;
      if (cf.sign != prevF.sign) {
        a = prevX;
        b = cx;
        fa = prevF;
        fb = cf;
        found = true;
        break;
      }
      prevX = cx;
      prevF = cf;
    }
    if (!found) {
      return const SolveResult.failed(
        'No rate satisfies these cash flows. Check the signs — you need at least one outflow and one inflow.',
      );
    }
  }

  for (var i = 0; i < 200; i++) {
    final m = (a + b) / 2;
    final fm = f(m);
    if (fm.abs() < kTolerance || (b - a).abs() < kTolerance) {
      return SolveResult.success(m, kMaxIterations + i + 1);
    }
    if (fm.sign == fa.sign) {
      a = m;
      fa = fm;
    } else {
      b = m;
      fb = fm;
    }
  }
  return const SolveResult.failed(
    'Did not converge within the iteration limit.',
  );
}

/// Compound factor (1 + i)^n, guarded for i = -1.
double pow1p(double i, num n) => math.pow(1 + i, n).toDouble();

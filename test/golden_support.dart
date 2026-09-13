import 'package:flutter_test/flutter_test.dart';

import 'package:basis/core/calculator.dart';
import 'package:basis/core/money.dart';

/// Shared by the file-based golden harness and the browser run. No
/// dart:io here, so it compiles for the web.

/// Turn JSON values into the typed [Inputs] a calculator expects, using the
/// calculator's own declaration to decide what each key should become.
Inputs coerceGoldenInputs(Calculator c, Map<String, Object?> json) {
  final out = Map<String, Object>.of(c.defaults);
  for (final entry in json.entries) {
    CalcInput? spec;
    for (final i in c.inputs) {
      if (i.key == entry.key) {
        spec = i;
        break;
      }
    }
    if (spec == null) {
      throw StateError(
        'Golden case sets "${entry.key}", which ${c.id} does not declare. '
        'Valid keys: ${c.inputs.map((i) => i.key).join(", ")}',
      );
    }
    final v = entry.value;
    out[entry.key] = switch (spec.kind) {
      InputKind.money =>
        v is num ? Money.fromDouble(v.toDouble()) : Money.tryParse('$v')!,
      InputKind.choice => '$v',
      InputKind.date => DateTime.parse('$v'),
      _ => (v as num).toDouble(),
    };
  }
  return out;
}

/// Compare two figures. Money-like strings are compared numerically so a
/// formatting difference between tools is not mistaken for a maths error.
void compareGoldenFigure({
  required String label,
  required String ours,
  required String theirs,
  required int toleranceCents,
  required String source,
}) {
  final a = Money.tryParse(ours);
  final b = Money.tryParse(theirs);

  // A source quoted beyond cents (a share price to 4dp) is compared as text,
  // because parsing it into Money would round away the digits being checked.
  final finerThanCents = RegExp(r'\.\d{3,}').hasMatch(theirs);

  if (!finerThanCents &&
      a != null &&
      b != null &&
      looksNumeric(ours) &&
      looksNumeric(theirs)) {
    final diff = (a.cents - b.cents).abs();
    expect(
      diff <= toleranceCents,
      isTrue,
      reason:
          'MISMATCH on "$label"\n'
          '    ours   : $ours\n'
          '    source : $theirs   ($source)\n'
          '    diff   : ${(diff / 100).toStringAsFixed(2)} '
          '(tolerance ${(toleranceCents / 100).toStringAsFixed(2)})\n'
          '    A gap larger than rounding usually means a convention '
          'disagreement — day count, rest basis, or when payments land. '
          'Investigate before widening the tolerance.',
    );
  } else {
    expect(
      ours.trim(),
      theirs.trim(),
      reason: 'MISMATCH on "$label" against $source',
    );
  }
}

bool looksNumeric(String s) => RegExp(r'\d').hasMatch(s);

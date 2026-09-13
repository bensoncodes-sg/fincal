import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/registry.dart';
import 'package:basis/core/calculator.dart';
import 'package:basis/rules/sg_rules.dart';

import 'golden_cases.g.dart';
import 'golden_support.dart';

/// Every golden case, runnable in a browser.
///
/// On the web a Dart `int` is a JavaScript number, `1.0.toString()` is "1",
/// and integer overflow behaves differently. None of that may move a figure.
/// Run with `flutter test --platform chrome test/web_parity_test.dart`; it
/// also runs on the VM as part of the normal suite.
void main() {
  final rules = SgRules.defaults;

  test('every calculator is embedded', () {
    for (final c in allCalculators) {
      expect(
        embeddedGoldens.containsKey(c.id),
        isTrue,
        reason: 'No embedded golden for ${c.id}',
      );
    }
  });

  for (final entry in embeddedGoldens.entries) {
    final doc = jsonDecode(entry.value) as Map<String, Object?>;
    final source = doc['source'] as String? ?? '';
    final cases = (doc['cases'] as List).cast<Map<String, Object?>>();

    group('parity · ${entry.key}', () {
      for (final cs in cases) {
        test(cs['note'] as String? ?? 'case', () {
          final calc = calculatorById(entry.key)!;
          final values = coerceGoldenInputs(
            calc,
            cs['inputs'] as Map<String, Object?>,
          );
          final result = calc.compute(values, rules);
          expect(result.error, isNull, reason: result.error);

          final expected = cs['expect'] as Map<String, Object?>;
          final tol = (cs['toleranceCents'] as num?)?.toInt() ?? 1;
          if (expected['primary'] != null) {
            compareGoldenFigure(
              label: 'primary',
              ours: result.primaryValue,
              theirs: expected['primary'].toString(),
              toleranceCents: tol,
              source: source,
            );
          }
          final sec = expected['secondary'] as Map<String, Object?>?;
          for (final e in (sec ?? const {}).entries) {
            final m = result.secondary.firstWhere(
              (m) => m.label.toLowerCase() == e.key.toLowerCase(),
              orElse: () => Metric(e.key, '<<missing>>'),
            );
            compareGoldenFigure(
              label: e.key,
              ours: m.value,
              theirs: e.value.toString(),
              toleranceCents: tol,
              source: source,
            );
          }
          if (expected['scheduleMonths'] != null) {
            expect(result.schedule.length, expected['scheduleMonths']);
          }
        });
      }
    });
  }

  test('seeded defaults compute without error or NaN for every calculator', () {
    for (final c in allCalculators) {
      final r = c.compute(c.defaults, rules);
      expect(r.error, isNull, reason: '${c.id}: ${r.error}');
      final text = [r.primaryValue, ...r.secondary.map((m) => m.value)];
      for (final t in text) {
        expect(
          t.contains('NaN') || t.contains('Infinity'),
          isFalse,
          reason: '${c.id} shows "$t"',
        );
      }
    }
  });
}

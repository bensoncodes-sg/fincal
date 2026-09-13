// Web parity check, runnable without a browser test runner.
//
// On the web, Dart compiles to JavaScript with dart2js: every int is a JS
// number and `1.0.toString()` is "1". This program prints every figure the
// calculators produce — each golden case and each calculator's seeded
// defaults — so the native and JavaScript outputs can be diffed exactly, and
// it checks each golden case against its expected value.
//
//   dart run tool/web_parity.dart > vm.txt
//   dart compile js -O2 -o build/parity.js tool/web_parity.dart
//   node -e "globalThis.self=globalThis;require('./build/parity.js')" > js.txt
//   diff vm.txt js.txt
// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:basis/calculators/registry.dart';
import 'package:basis/core/calculator.dart';
import 'package:basis/core/money.dart';
import 'package:basis/rules/sg_rules.dart';

import '../test/golden_cases.g.dart';

void main() {
  final rules = SgRules.defaults;
  var checked = 0;
  var failed = 0;

  void dump(String tag, CalcResult r) {
    print('$tag | ${r.error ?? ''} | ${r.primaryLabel} = ${r.primaryValue}');
    for (final m in r.secondary) {
      print('$tag |   ${m.label} = ${m.value}');
    }
    if (r.delta != null) print('$tag |   note: ${r.delta!.text}');
    if (r.explain != null) print('$tag |   math: ${r.explain!.substituted}');
    print('$tag |   schedule rows: ${r.schedule.length}');
    for (final s in r.series) {
      final last = s.points.isEmpty ? null : s.points.last;
      print('$tag |   series ${s.name}: ${s.points.length} pts, last '
          '${last == null ? '-' : '${last.x.toStringAsFixed(2)} ${last.y.toStringAsFixed(6)}'}');
    }
    if (r.schedule.isNotEmpty) {
      var paid = 0, principal = 0, interest = 0;
      for (final row in r.schedule) {
        paid += row.payment.cents;
        principal += row.principal.cents;
        interest += row.interest.cents;
      }
      final z = r.schedule.last;
      print('$tag |   schedule cents paid=$paid principal=$principal '
          'interest=$interest last=#${z.number} ${z.payment.cents} '
          '${z.balance.cents}');
    }
  }

  bool matches(String ours, String theirs, int tol) {
    final a = Money.tryParse(ours);
    final b = Money.tryParse(theirs);
    final finer = RegExp(r'\.\d{3,}').hasMatch(theirs);
    if (!finer && a != null && b != null && RegExp(r'\d').hasMatch(theirs)) {
      return (a.cents - b.cents).abs() <= tol;
    }
    return ours.trim() == theirs.trim();
  }

  for (final entry in embeddedGoldens.entries) {
    final doc = jsonDecode(entry.value) as Map<String, Object?>;
    final calc = calculatorById(entry.key)!;
    final cases = (doc['cases'] as List).cast<Map<String, Object?>>();
    for (var i = 0; i < cases.length; i++) {
      final cs = cases[i];
      final values = Map<String, Object>.of(calc.defaults);
      (cs['inputs'] as Map<String, Object?>).forEach((k, v) {
        final spec = calc.inputs.firstWhere((s) => s.key == k);
        values[k] = switch (spec.kind) {
          InputKind.money =>
            v is num ? Money.fromDouble(v.toDouble()) : Money.tryParse('$v')!,
          InputKind.choice => '$v',
          InputKind.date => DateTime.parse('$v'),
          _ => (v as num).toDouble(),
        };
      });
      final r = calc.compute(values, rules);
      dump('${entry.key}#$i', r);

      final expected = cs['expect'] as Map<String, Object?>;
      final tol = (cs['toleranceCents'] as num?)?.toInt() ?? 1;
      final pairs = <(String, String, String)>[
        if (expected['primary'] != null)
          ('primary', r.primaryValue, '${expected['primary']}'),
        for (final e in ((expected['secondary'] as Map?) ?? const {}).entries)
          (
            '${e.key}',
            r.secondary
                .firstWhere(
                  (m) => m.label.toLowerCase() == '${e.key}'.toLowerCase(),
                  orElse: () => const Metric('', '<<missing>>'),
                )
                .value,
            '${e.value}',
          ),
      ];
      if (r.error != null) {
        failed++;
        print('PARITY FAIL ${entry.key}#$i refused: ${r.error}');
      }
      for (final (label, ours, theirs) in pairs) {
        checked++;
        if (!matches(ours, theirs, tol)) {
          failed++;
          print('PARITY FAIL ${entry.key}#$i $label: ours "$ours" '
              'expected "$theirs"');
        }
      }
    }
  }

  for (final c in allCalculators) {
    dump('${c.id}@defaults', c.compute(c.defaults, rules));
  }

  print('SUMMARY figures checked: $checked, failed: $failed');
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/registry.dart';
import 'package:basis/core/calculator.dart';
import 'package:basis/rules/sg_rules.dart';

import 'golden_cases.g.dart';
import 'golden_support.dart';

/// Golden harness.
///
/// Every case here asserts our output against a number that came from OUTSIDE
/// this repository. That is the point: the rest of the suite can only show
/// that our arithmetic agrees with itself, and a wrong convention or a stale
/// statutory table would pass it happily.
///
/// Two design rules make this harness worth having:
///
///   1. A `pending` case never silently passes. It is reported, counted, and
///      listed by name, so an empty golden file cannot masquerade as
///      verification.
///   2. A `captured` case must name its source. A number with no provenance
///      is treated as a failure, not as evidence.
void main() {
  final rules = SgRules.defaults;
  final dir = Directory('test/golden');
  final files = dir.existsSync()
      ? (dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  test(
    'embedded golden copy matches test/golden (run tool/embed_goldens.py)',
    () {
      final onDisk = {
        for (final f in files)
          (jsonDecode(f.readAsStringSync()) as Map)['calculator'] as String:
              jsonDecode(f.readAsStringSync()),
      };
      final embedded = {
        for (final e in embeddedGoldens.entries) e.key: jsonDecode(e.value),
      };
      expect(
        jsonEncode(embedded.keys.toList()..sort()),
        jsonEncode(onDisk.keys.toList()..sort()),
        reason:
            'A golden file was added or removed without regenerating '
            'test/golden_cases.g.dart, so the browser run would test less.',
      );
      for (final id in onDisk.keys) {
        expect(
          jsonEncode(embedded[id]),
          jsonEncode(onDisk[id]),
          reason: '$id changed on disk but the embedded copy is stale.',
        );
      }
    },
  );

  final pending = <String>[];
  final captured = <String>[];
  final uncovered = <String>[];

  test('golden directory exists and holds at least one file', () {
    expect(
      files,
      isNotEmpty,
      reason: 'No golden files found in test/golden. See its README.',
    );
  });

  for (final file in files) {
    final raw = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final calcId = raw['calculator'] as String;
    final status = (raw['status'] as String? ?? 'pending').toLowerCase();
    final source = (raw['source'] as String? ?? '').trim();
    final cases = (raw['cases'] as List).cast<Map<String, Object?>>();
    final calc = calculatorById(calcId);

    group('golden · $calcId', () {
      test('declares a calculator that exists', () {
        expect(
          calc,
          isNotNull,
          reason: '${file.path} names unknown calculator "$calcId"',
        );
      });

      if (status == 'captured') {
        test('cites a source', () {
          expect(
            source,
            isNotEmpty,
            reason:
                '${file.path} is marked captured but names no source. '
                'A number without provenance is not evidence.',
          );
        });
      }

      for (var i = 0; i < cases.length; i++) {
        final cs = cases[i];
        final note = (cs['note'] as String? ?? 'case ${i + 1}');
        final caseStatus = ((cs['status'] as String?) ?? status).toLowerCase();
        final label = '$calcId · $note';

        if (caseStatus != 'captured') {
          pending.add(label);
          // Deliberately reported rather than skipped silently.
          test('$note  [PENDING — no external number yet]', () {
            expect(
              cs['inputs'],
              isNotNull,
              reason:
                  'A pending case still needs its inputs filled in so '
                  'there is something concrete to go and look up.',
            );
          });
          continue;
        }

        captured.add(label);

        test(note, () {
          final c = calc!;
          final values = coerceGoldenInputs(
            c,
            cs['inputs'] as Map<String, Object?>,
          );
          final result = c.compute(values, rules);

          expect(
            result.error,
            isNull,
            reason: 'Calculator refused these inputs: ${result.error}',
          );

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
          if (sec != null) {
            for (final entry in sec.entries) {
              final metric = result.secondary.firstWhere(
                (m) => m.label.toLowerCase() == entry.key.toLowerCase(),
                orElse: () => Metric(entry.key, '<<missing>>'),
              );
              compareGoldenFigure(
                label: entry.key,
                ours: metric.value,
                theirs: entry.value.toString(),
                toleranceCents: tol,
                source: source,
              );
            }
          }

          if (expected['scheduleMonths'] != null) {
            expect(
              result.schedule.length,
              expected['scheduleMonths'],
              reason: 'term length disagrees with $source',
            );
          }
        });
      }
    });
  }

  // -------------------------------------------------------------------------
  // Coverage report — the part that stops an empty harness looking healthy
  // -------------------------------------------------------------------------

  group('coverage', () {
    test('every calculator has a golden file', () {
      final covered = files
          .map(
            (f) =>
                (jsonDecode(f.readAsStringSync()) as Map)['calculator']
                    as String,
          )
          .toSet();
      for (final c in allCalculators) {
        if (!covered.contains(c.id)) uncovered.add(c.id);
      }
      expect(
        uncovered,
        isEmpty,
        reason: 'No golden file for: ${uncovered.join(", ")}',
      );
    });

    test('report', () {
      final total = pending.length + captured.length;
      final pctText = total == 0
          ? 'n/a'
          : '${(captured.length / total * 100).toStringAsFixed(0)}%';

      final buf = StringBuffer()
        ..writeln('')
        ..writeln('  GOLDEN COVERAGE')
        ..writeln('  ${'-' * 58}')
        ..writeln(
          '  externally verified : ${captured.length} of $total  ($pctText)',
        )
        ..writeln('  still pending       : ${pending.length}');

      if (pending.isNotEmpty) {
        buf.writeln('');
        buf.writeln('  These calculators have NO external verification yet.');
        buf.writeln('  Their numbers are only as good as the assumptions in');
        buf.writeln('  lib/rules/sg_rules.dart, which were not sourced.');
        buf.writeln('');
        for (final p in pending) {
          buf.writeln('    · $p');
        }
        buf.writeln('');
        buf.writeln('  Fill them in per test/golden/README.md.');
      }
      buf.writeln('  ${'-' * 58}');
      // ignore: avoid_print
      print(buf.toString());

      // Always passes. This is a report, not a gate — failing the build for
      // data that has not been gathered yet would just get the suite ignored.
      expect(true, isTrue);
    });
  });
}

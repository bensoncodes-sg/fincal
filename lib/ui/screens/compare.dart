import 'package:flutter/material.dart';

import '../../calculators/registry.dart';
import '../../core/calculator.dart';
import '../../core/money.dart';
import '../../state.dart';
import '../components.dart';
import '../theme.dart';
import 'export.dart';

/// Side-by-side comparison of saved scenarios.
///
/// Scenarios store their inputs, not a snapshot of their answer, so every
/// column is RECOMPUTED here against the current ruleset. A saved scenario
/// from before a rate change therefore shows today's figure rather than a
/// stale one — which is the whole reason the scenario stores inputs.
class CompareTab extends StatelessWidget {
  final AppState app;
  const CompareTab({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final picked = app.comparing;

    if (picked.length < 2) {
      return _Empty(
        title: 'Pick one more',
        body:
            'Comparing needs at least two saved scenarios. You have ${picked.length}. '
            'Open Saved and tap Compare on the ones you want side by side.',
      );
    }

    final columns = <_Column>[];
    for (final s in picked) {
      final calc = calculatorById(s.calculatorId);
      if (calc == null) continue;
      final inputs = s.inputs.isEmpty ? calc.defaults : s.inputs;
      columns.add(
        _Column(
          scenario: s,
          calculator: calc,
          result: calc.compute({...calc.defaults, ...inputs}, app.rules),
        ),
      );
    }

    if (columns.length < 2) {
      return const _Empty(
        title: 'These cannot be compared',
        body:
            'At least two of the selected scenarios use a tool that is no '
            'longer available.',
      );
    }

    final mixed = columns.map((e) => e.calculator.id).toSet().length > 1;
    final rows = _buildRows(columns);

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.margin, S.sm, S.margin, S.xl),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text('Compare', style: T.display.copyWith(color: c.ink)),
            ),
            Text(
              '${columns.length}',
              style: T.figure.copyWith(color: c.inkMute),
            ),
          ],
        ),
        const SizedBox(height: S.sm),
        Text(
          'Recomputed against the current ruleset, not the figures saved at '
          'the time.',
          style: T.bodySm.copyWith(color: c.inkMute),
        ),

        if (mixed) ...[
          const SizedBox(height: S.md),
          Container(
            padding: const EdgeInsets.all(S.md),
            decoration: BoxDecoration(
              borderRadius: R.input,
              color: c.warn.withValues(alpha: 0.08),
              border: Border(left: BorderSide(color: c.warn, width: 2)),
            ),
            child: Text(
              'These scenarios come from different calculators, so only rows '
              'they share can be lined up. Nothing here is marked best.',
              style: T.bodySm.copyWith(color: c.warn),
            ),
          ),
        ],

        const SizedBox(height: S.lg),
        _Headers(columns: columns),
        const SizedBox(height: S.sm),
        for (final r in rows) _Row(row: r, columns: columns, allowBest: !mixed),

        const SizedBox(height: S.lg),
        if (!mixed) _Verdict(columns: columns),

        const SizedBox(height: S.md),
        GestureDetector(
          onTap: () => showExportSheet(
            context,
            title: 'Compare',
            csv: _csv(columns, rows),
          ),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: R.input, color: c.accent),
            child: Text(
              'Export side-by-side',
              style: T.body.copyWith(
                color: c.ground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Union of metric labels, ordered by the first column, headline first.
  static List<_MetricRow> _buildRows(List<_Column> columns) {
    final rows = <_MetricRow>[
      _MetricRow(
        label: columns.first.result.primaryLabel,
        better: columns.first.result.primaryBetter,
        isPrimary: true,
      ),
    ];
    final seen = <String>{};
    for (final col in columns) {
      for (final m in col.result.secondary) {
        if (seen.add(m.label.toLowerCase())) {
          rows.add(_MetricRow(label: m.label, better: m.better));
        }
      }
    }
    return rows;
  }

  static String _csv(List<_Column> columns, List<_MetricRow> rows) {
    String esc(String v) =>
        v.contains(',') || v.contains('"') ? '"${v.replaceAll('"', '""')}"' : v;

    final b = StringBuffer()
      ..writeln(
        ['Metric', ...columns.map((c) => esc(c.scenario.name))].join(','),
      );
    for (final r in rows) {
      b.writeln(
        [
          esc(r.label),
          ...columns.map((c) => esc(_valueFor(c, r) ?? '')),
        ].join(','),
      );
    }
    return b.toString();
  }
}

String? _valueFor(_Column col, _MetricRow row) {
  if (row.isPrimary) return col.result.primaryValue;
  for (final m in col.result.secondary) {
    if (m.label.toLowerCase() == row.label.toLowerCase()) return m.value;
  }
  return null;
}

/// Numeric reading of a displayed figure, for picking a winner. Returns null
/// for anything that is not a number, so text rows are never "best".
double? _numeric(String? v) {
  if (v == null) return null;
  final m = Money.tryParse(v);
  if (m == null) return null;
  if (!RegExp(r'\d').hasMatch(v)) return null;
  return m.asDouble;
}

class _Column {
  final Scenario scenario;
  final Calculator calculator;
  final CalcResult result;
  const _Column({
    required this.scenario,
    required this.calculator,
    required this.result,
  });
}

class _MetricRow {
  final String label;
  final Better better;
  final bool isPrimary;
  const _MetricRow({
    required this.label,
    required this.better,
    this.isPrimary = false,
  });
}

class _Headers extends StatelessWidget {
  final List<_Column> columns;
  const _Headers({required this.columns});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final col in columns)
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: c.accentSoft, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    col.calculator.name,
                    style: T.bodySm.copyWith(color: c.inkMute, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    col.scenario.name,
                    style: T.body.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final _MetricRow row;
  final List<_Column> columns;
  final bool allowBest;

  const _Row({
    required this.row,
    required this.columns,
    required this.allowBest,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final values = columns.map((col) => _valueFor(col, row)).toList();

    int? bestIndex;
    if (allowBest && row.better != Better.none) {
      final nums = values.map(_numeric).toList();
      final usable = nums.where((n) => n != null).length;
      // A winner only means something when every column has a number and they
      // are not all identical.
      if (usable == nums.length && nums.toSet().length > 1) {
        var idx = 0;
        for (var i = 1; i < nums.length; i++) {
          final better = row.better == Better.lower
              ? nums[i]! < nums[idx]!
              : nums[i]! > nums[idx]!;
          if (better) idx = i;
        }
        bestIndex = idx;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.label,
                  style: T.bodySm.copyWith(color: c.inkMute),
                ),
              ),
              if (allowBest && row.better != Better.none)
                Text(
                  row.better == Better.lower
                      ? 'LOWER IS BETTER'
                      : 'HIGHER IS BETTER',
                  style: T.label.copyWith(
                    color: c.inkMute.withValues(alpha: 0.7),
                    fontSize: 9,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < columns.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Row(
                      children: [
                        if (i == bestIndex) ...[
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              values[i] ?? '—',
                              style: (row.isPrimary ? T.figure : T.figureSm)
                                  .copyWith(
                                    color: values[i] == null
                                        ? c.inkMute
                                        : (i == bestIndex ? c.accent : c.ink),
                                    fontWeight: i == bestIndex
                                        ? FontWeight.w600
                                        : null,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: S.sm),
          const Hairline(),
        ],
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  final List<_Column> columns;
  const _Verdict({required this.columns});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final better = columns.first.result.primaryBetter;
    if (better == Better.none) return const SizedBox.shrink();

    final nums = columns
        .map((col) => _numeric(col.result.primaryValue))
        .toList();
    if (nums.any((n) => n == null) || nums.toSet().length < 2) {
      return const SizedBox.shrink();
    }

    var idx = 0;
    for (var i = 1; i < nums.length; i++) {
      final wins = better == Better.lower
          ? nums[i]! < nums[idx]!
          : nums[i]! > nums[idx]!;
      if (wins) idx = i;
    }
    var worst = 0;
    for (var i = 1; i < nums.length; i++) {
      final loses = better == Better.lower
          ? nums[i]! > nums[worst]!
          : nums[i]! < nums[worst]!;
      if (loses) worst = i;
    }
    final gap = Money.fromDouble((nums[worst]! - nums[idx]!).abs());

    return Container(
      padding: const EdgeInsets.all(S.cardPad),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: R.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            columns[idx].result.primaryLabel.isEmpty
                ? 'BEST'
                : 'BEST ON ${columns[idx].result.primaryLabel}',
            style: T.label.copyWith(color: c.accent),
          ),
          const SizedBox(height: S.sm),
          Text(
            columns[idx].scenario.name,
            style: T.title.copyWith(color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '${gap.sgd} ${better == Better.lower ? "less" : "more"} than '
            '${columns[worst].scenario.name}.',
            style: T.bodySm.copyWith(color: c.ink),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String title;
  final String body;
  const _Empty({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(S.margin * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare_arrows, size: 56, color: c.line),
            const SizedBox(height: S.lg),
            Text(title, style: T.title.copyWith(color: c.ink)),
            const SizedBox(height: S.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: T.body.copyWith(color: c.inkMute),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/calculator.dart';
import '../../core/finance.dart';
import '../../core/money.dart';
import '../../state.dart';
import '../components.dart';
import '../theme.dart';
import 'export.dart';

/// THE renderer.
///
/// Every calculator in the app is this one screen, configured by its
/// [Calculator] declaration. That is the entire architectural bet: save,
/// chart, schedule, explain and export are built once here, and the 49th
/// calculator inherits all of them for free.
class CalculatorScreen extends StatefulWidget {
  final Calculator calculator;
  final AppState app;

  /// A saved scenario to reopen. Its inputs replace the defaults; without
  /// this, opening a saved scenario showed the example numbers instead.
  final Scenario? scenario;

  const CalculatorScreen({
    super.key,
    required this.calculator,
    required this.app,
    this.scenario,
  });

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  late Inputs _values;
  String? _focusedKey;

  /// Keys the user has actually edited. Everything else is still the seeded
  /// example, and is drawn translucent so it cannot be read as their own
  /// figure. This is the difference between a demo and a claim about someone's
  /// money, and it costs one Set to get right.
  final Set<String> _touched = {};

  @override
  void initState() {
    super.initState();
    _values = Map.of(widget.calculator.defaults);
    final saved = widget.scenario;
    if (saved != null) {
      for (final spec in widget.calculator.inputs) {
        final v = saved.inputs[spec.key];
        if (v == null) continue;
        _values[spec.key] = v;
        // The user's own saved figures are theirs, so they read as LIVE. A
        // seeded example reopened is still an example.
        if (!saved.isExample && spec.kind != InputKind.choice) {
          _touched.add(spec.key);
        }
      }
    }
  }

  CalcResult get _result =>
      widget.calculator.compute(_values, widget.app.rules);

  void _set(String key, Object v) => setState(() {
    _values[key] = v;
    _touched.add(key);
  });

  /// Change a value WITHOUT counting it as the user supplying a figure.
  /// Choosing which variable to solve for rearranges the question; it does
  /// not make the seeded numbers theirs, so the badge must stay EXAMPLE.
  void _setMode(String key, Object v) => setState(() => _values[key] = v);

  /// True while nothing at all has been edited.
  bool get _allExample => _touched.isEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final calc = widget.calculator;
    final result = _result;
    final solveKey = calc.solveFor.isNotEmpty ? 'solve' : null;

    return Scaffold(
      backgroundColor: c.ground,
      appBar: _bar(context, calc.name),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.margin, 0, S.margin, S.xl),
        children: [
          ResultStack(result: result, isExample: _allExample),

          if (solveKey != null) ...[
            const SizedBox(height: S.md),
            SolveForBar(
              options: calc.inputs.firstWhere((i) => i.key == solveKey).choices,
              selected: _values[solveKey].toString(),
              onChanged: (v) => _setMode(solveKey, v),
            ),
          ],

          // Always present, empty while the inputs cannot compute. If this
          // row came and went, the input card below would shift position in
          // the list, be rebuilt, and drop keyboard focus the moment a user
          // cleared a field on the way to typing a new number.
          const SizedBox(height: S.md),
          SizedBox(
            height: 28,
            child: result.explain == null
                ? null
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final a in result.explain!.assumptions.take(3))
                        AssumptionChip(a.value, onTap: () => _openMath(result)),
                    ],
                  ),
          ),

          const SizedBox(height: S.md),

          BasisCard(
            key: const ValueKey('inputs-card'),
            padding: const EdgeInsets.symmetric(horizontal: S.cardPad),
            child: Column(
              children: [
                for (var i = 0; i < _editable.length; i++)
                  InputRow(
                    key: ValueKey(_editable[i].key),
                    spec: _editable[i],
                    value: _values[_editable[i].key] ?? _editable[i].initial,
                    focused: _focusedKey == _editable[i].key,
                    last: i == _editable.length - 1,
                    isExample: !_touched.contains(_editable[i].key),
                    onFocus: () =>
                        setState(() => _focusedKey = _editable[i].key),
                    // Picking an option is not supplying a figure: with every
                    // number still seeded, the result is still an example.
                    onChanged: (v) => _editable[i].kind == InputKind.choice
                        ? _setMode(_editable[i].key, v)
                        : _set(_editable[i].key, v),
                  ),
              ],
            ),
          ),

          if (_focusedSpec != null && _focusedSpec!.kind == InputKind.percent)
            _slider(_focusedSpec!),

          if (result.delta != null) ...[
            const SizedBox(height: S.md),
            DeltaLineView(note: result.delta!),
          ],

          if (result.series.isNotEmpty) ...[
            // The heading follows the series too: "Over time" is wrong for a
            // curve plotted against income rather than a date.
            SectionLabel(
              result.series.first.xUnit == null ||
                      result.series.first.xUnit!.contains('income')
                  ? result.series.first.name
                  : 'Over time',
            ),
            BasisCard(
              child: SeriesChart(
                series: result.series,
                xStartLabel: _xStart(result),
                xEndLabel: _xEnd(result),
              ),
            ),
          ],

          if (result.schedule.isNotEmpty) ...[
            const SizedBox(height: S.md),
            _linkRow(
              context,
              'Payment schedule',
              '${result.schedule.length} rows',
              () => _openSchedule(result),
            ),
          ],

          if (result.explain != null) ...[
            const SizedBox(height: S.md),
            Center(
              child: TextButton(
                onPressed: () => _openMath(result),
                child: Text(
                  'Show the math',
                  style: T.body.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SaveBar(
        onSave: result.error != null ? null : () => _save(result),
        secondaryLabel: 'Export',
        onCompare: result.error != null
            ? null
            : () => showExportSheet(
                context,
                title: widget.calculator.name,
                csv: csvForResult(
                  calculatorName: widget.calculator.name,
                  inputs: widget.calculator.inputs
                      .where((i) => i.appliesTo(_values))
                      .toList(),
                  values: _values,
                  result: result,
                ),
              ),
      ),
    );
  }

  List<CalcInput> get _editable => widget.calculator.inputs
      .where((i) => i.key != 'solve' && i.appliesTo(_values))
      .toList();

  CalcInput? get _focusedSpec {
    if (_focusedKey == null) return null;
    for (final i in widget.calculator.inputs) {
      if (i.key == _focusedKey) return i;
    }
    return null;
  }

  Widget _slider(CalcInput spec) {
    final c = context.c;
    final v = (_values[spec.key] as num?)?.toDouble() ?? 0;
    final min = spec.min ?? 0;
    final max = spec.max ?? 10;
    return Padding(
      padding: const EdgeInsets.only(top: S.sm),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: c.accent,
              inactiveTrackColor: c.line,
              thumbColor: c.accent,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: v.clamp(min, max),
              min: min,
              max: max,
              onChanged: (nv) =>
                  _set(spec.key, double.parse(nv.toStringAsFixed(2))),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${min.toStringAsFixed(2)}%',
                style: T.figureSm.copyWith(color: c.inkMute),
              ),
              Text(
                spec.label.toUpperCase(),
                style: T.label.copyWith(color: c.inkMute, fontSize: 11),
              ),
              Text(
                '${max.toStringAsFixed(2)}%',
                style: T.figureSm.copyWith(color: c.inkMute),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _xStart(CalcResult r) =>
      r.schedule.isNotEmpty ? '${r.schedule.first.date.year}' : '0';

  String? _xEnd(CalcResult r) {
    if (r.schedule.isNotEmpty) return '${r.schedule.last.date.year}';
    if (r.series.isEmpty) return null;
    final s = r.series.first;
    final end = s.points.last.x.toStringAsFixed(0);
    // The series says what its x axis measures. Assuming years here is what
    // labelled a tax-against-income curve "160 yr".
    return s.xUnit == null ? end : '$end ${s.xUnit}';
  }

  Widget _linkRow(
    BuildContext context,
    String label,
    String meta,
    VoidCallback onTap,
  ) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: BasisCard(
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: T.body.copyWith(color: c.ink)),
            ),
            Text(meta, style: T.figureSm.copyWith(color: c.inkMute)),
            const SizedBox(width: S.sm),
            Icon(Icons.chevron_right, size: 18, color: c.inkMute),
          ],
        ),
      ),
    );
  }

  void _openMath(CalcResult r) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MathSheet(result: r, colors: context.c),
    );
  }

  void _openSchedule(CalcResult r) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ScheduleScreen(result: r, title: widget.calculator.name),
      ),
    );
  }

  Future<void> _save(CalcResult r) async {
    if (r.error != null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _NameDialog(colors: context.c),
    );
    if (name == null || !mounted) return;
    await widget.app.saveScenario(
      Scenario(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        calculatorId: widget.calculator.id,
        name: name,
        inputs: Map.of(_values),
        savedAt: DateTime.now(),
        headlineLabel: r.primaryLabel,
        headlineValue: r.primaryValue,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved', style: T.body),
        backgroundColor: context.c.ink,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

PreferredSizeWidget _bar(BuildContext context, String title) {
  final c = context.c;
  return AppBar(
    backgroundColor: c.ground,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
    titleSpacing: 0,
    leading: IconButton(
      icon: Icon(Icons.arrow_back, color: c.ink),
      onPressed: () => Navigator.of(context).maybePop(),
    ),
    title: Text(title, style: T.title.copyWith(color: c.ink)),
  );
}

// ---------------------------------------------------------------------------
// MathSheet — the formula, the substituted values, the assumptions
// ---------------------------------------------------------------------------

class MathSheet extends StatelessWidget {
  final CalcResult result;
  final BasisColors colors;

  const MathSheet({super.key, required this.result, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final e = result.explain!;
    return Container(
      decoration: BoxDecoration(color: c.ground, borderRadius: R.sheet),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      padding: const EdgeInsets.fromLTRB(S.margin, S.md, S.margin, S.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: c.line, borderRadius: R.pill),
            ),
          ),
          const SizedBox(height: S.lg),
          Text(
            'How this was worked out',
            style: T.title.copyWith(color: c.ink),
          ),
          const SizedBox(height: S.lg),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                Text('FORMULA', style: T.label.copyWith(color: c.inkMute)),
                const SizedBox(height: S.sm),
                _panel(c, e.formula),
                const SizedBox(height: S.lg),
                Text(
                  'WITH YOUR NUMBERS',
                  style: T.label.copyWith(color: c.inkMute),
                ),
                const SizedBox(height: S.sm),
                _panel(c, e.substituted, accent: c.accent),
                if (e.assumptions.isNotEmpty) ...[
                  const SizedBox(height: S.lg),
                  Text(
                    'ASSUMPTIONS',
                    style: T.label.copyWith(color: c.inkMute),
                  ),
                  const SizedBox(height: S.sm),
                  for (var i = 0; i < e.assumptions.length; i++)
                    Column(
                      children: [
                        SizedBox(
                          height: 44,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.assumptions[i].label,
                                  style: T.body.copyWith(color: c.ink),
                                ),
                              ),
                              Text(
                                e.assumptions[i].value,
                                style: T.figureSm.copyWith(color: c.inkMute),
                              ),
                            ],
                          ),
                        ),
                        if (i != e.assumptions.length - 1)
                          Container(height: 1, color: c.line),
                      ],
                    ),
                ],
                if (e.footnote != null) ...[
                  const SizedBox(height: S.lg),
                  Text(e.footnote!, style: T.bodySm.copyWith(color: c.inkMute)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(BasisColors c, String text, {Color? accent}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(S.md),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: R.input,
      border: Border.all(color: c.line),
    ),
    child: Text(
      text,
      style: T.figureSm.copyWith(color: accent ?? c.ink, height: 1.7),
    ),
  );
}

// ---------------------------------------------------------------------------
// ScheduleScreen
// ---------------------------------------------------------------------------

class ScheduleScreen extends StatelessWidget {
  final CalcResult result;
  final String title;

  const ScheduleScreen({super.key, required this.result, required this.title});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = result.schedule;
    final years = <int>{for (final r in rows) r.date.year}.toList()..sort();

    var totalPaid = Money.zero, totalInterest = Money.zero;
    for (final r in rows) {
      totalPaid = totalPaid + r.payment;
      totalInterest = totalInterest + r.interest;
    }

    return Scaffold(
      backgroundColor: c.ground,
      appBar: _bar(context, 'Payment schedule'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.margin, 0, S.margin, S.xl),
        children: [
          BasisCard(
            child: Row(
              children: [
                _stat(context, 'Total repaid', totalPaid.sgd0),
                _stat(
                  context,
                  'Total interest',
                  totalInterest.sgd0,
                  tone: Tone.negative,
                ),
                _stat(context, 'Payments', '${rows.length}'),
              ],
            ),
          ),
          const SizedBox(height: S.md),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: R.card,
              border: Border.all(color: c.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  color: c.surface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: S.md,
                    vertical: S.sm,
                  ),
                  child: Row(
                    children: [
                      _h(context, 'NO', 34),
                      _h(context, 'DATE', 56),
                      Expanded(
                        child: _h(context, 'PRINCIPAL', null, end: true),
                      ),
                      Expanded(child: _h(context, 'INTEREST', null, end: true)),
                      Expanded(child: _h(context, 'BALANCE', null, end: true)),
                    ],
                  ),
                ),
                Container(height: 1, color: c.line),
                for (final y in years) ..._yearBlock(context, y, rows),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _yearBlock(
    BuildContext context,
    int year,
    List<ScheduleRow> rows,
  ) {
    final c = context.c;
    final yr = rows.where((r) => r.date.year == year).toList();
    var p = Money.zero, i = Money.zero;
    for (final r in yr) {
      p = p + r.principal;
      i = i + r.interest;
    }
    return [
      Container(
        width: double.infinity,
        color: c.accentSoft,
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: 6),
        child: Text(
          '$year — ${yr.length} PAYMENTS · PRIN ${p.sgd0} · INT ${i.sgd0}',
          style: T.label.copyWith(color: c.accent, fontSize: 10.5),
        ),
      ),
      for (final r in yr)
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: S.md),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  r.number.toString().padLeft(3, '0'),
                  style: T.figureSm.copyWith(color: c.inkMute, fontSize: 11),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  shortDate(r.date),
                  style: T.figureSm.copyWith(color: c.inkMute, fontSize: 11),
                ),
              ),
              Expanded(
                child: Text(
                  r.principal.format(),
                  textAlign: TextAlign.right,
                  style: T.figureSm.copyWith(color: c.ink, fontSize: 11),
                ),
              ),
              Expanded(
                child: Text(
                  r.interest.format(),
                  textAlign: TextAlign.right,
                  style: T.figureSm.copyWith(color: c.negative, fontSize: 11),
                ),
              ),
              Expanded(
                child: Text(
                  r.balance.format(decimals: 0),
                  textAlign: TextAlign.right,
                  style: T.figureSm.copyWith(color: c.ink, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _h(BuildContext context, String t, double? w, {bool end = false}) {
    final style = T.label.copyWith(color: context.c.inkMute, fontSize: 10);
    final child = Text(
      t,
      style: style,
      textAlign: end ? TextAlign.right : TextAlign.left,
    );
    return w == null ? child : SizedBox(width: w, child: child);
  }

  Widget _stat(
    BuildContext context,
    String label,
    String value, {
    Tone tone = Tone.neutral,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: T.label.copyWith(color: context.c.inkMute, fontSize: 10),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: T.figure.copyWith(color: toneColor(context, tone)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  final BasisColors colors;
  const _NameDialog({required this.colors});
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return AlertDialog(
      backgroundColor: c.ground,
      shape: const RoundedRectangleBorder(borderRadius: R.card),
      title: Text('Name this scenario', style: T.title.copyWith(color: c.ink)),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        style: T.body.copyWith(color: c.ink),
        cursorColor: c.accent,
        decoration: InputDecoration(
          hintText: 'Punggol 4-room, 25 yr',
          hintStyle: T.body.copyWith(color: c.inkMute),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: c.line),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: c.accent),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: T.body.copyWith(color: c.inkMute)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _ctl.text.trim().isEmpty ? 'Untitled' : _ctl.text.trim(),
          ),
          child: Text(
            'Save',
            style: T.body.copyWith(
              color: c.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

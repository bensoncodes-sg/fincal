import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/calculator.dart';
import '../core/money.dart';
import 'theme.dart';

/// Colour for a charted series. A neutral tone means "carries no good/bad
/// meaning": for text that is ink, but for a plot line the design system puts
/// every stroke in accent. Legend swatches and strokes both read this, so the
/// two can never drift apart.
Color seriesColor(BuildContext ctx, Tone t) =>
    t == Tone.neutral ? ctx.c.accent : toneColor(ctx, t);

Color toneColor(BuildContext ctx, Tone t) => switch (t) {
  Tone.positive => ctx.c.positive,
  Tone.negative => ctx.c.negative,
  Tone.warn => ctx.c.warn,
  Tone.neutral => ctx.c.ink,
};

// ---------------------------------------------------------------------------

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: S.sm, top: S.lg),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: T.label.copyWith(color: context.c.inkMute),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class Hairline extends StatelessWidget {
  const Hairline({super.key});
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: context.c.line);
}

class BasisCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const BasisCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.cardPad),
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.c.surface,
      borderRadius: R.card,
      border: Border.all(color: context.c.line),
    ),
    padding: padding,
    child: child,
  );
}

// ---------------------------------------------------------------------------
// InputRow — 52px, label left, mono value right, hairline under
// ---------------------------------------------------------------------------

class InputRow extends StatefulWidget {
  final CalcInput spec;
  final Object value;
  final bool focused;
  final bool last;

  /// True while this row still shows its seeded example value. Such a value
  /// is rendered translucent, the way placeholder text is, so it can never be
  /// mistaken for a figure the user entered. It snaps to solid on first edit.
  final bool isExample;

  final ValueChanged<Object> onChanged;
  final VoidCallback? onFocus;

  const InputRow({
    super.key,
    required this.spec,
    required this.value,
    required this.onChanged,
    this.focused = false,
    this.last = false,
    this.isExample = false,
    this.onFocus,
  });

  @override
  State<InputRow> createState() => _InputRowState();
}

class _InputRowState extends State<InputRow> {
  late TextEditingController _ctl;
  final _node = FocusNode();

  /// Set when what was typed sits outside the allowed range. The app computes
  /// with the clamped value, so leaving the typed one on screen unannounced
  /// would show one number and calculate with another.
  String? _clampNote;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: _display());
    _node.addListener(() {
      if (_node.hasFocus) {
        widget.onFocus?.call();
        // Select the whole figure, so typing replaces it. Otherwise the caret
        // lands where the finger did, and "8,000.00" edited from the middle
        // becomes a wrong number. After the frame, because the tap that gave
        // focus places its own caret first.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_node.hasFocus) return;
          _ctl.selection =
              TextSelection(baseOffset: 0, extentOffset: _ctl.text.length);
        });
      } else {
        // On losing focus, snap the text back to the value actually in use.
        _ctl.text = _display();
        _clampNote = null;
      }
      setState(() {});
    });
  }

  String _display() {
    final v = widget.value;
    if (v is Money) return v.format();
    if (v is num) {
      // Explicit, because a whole double prints "3.0" natively but "3" on
      // the web. A rate keeps one decimal so it reads as a rate on both.
      if (v != v.roundToDouble()) return v.toString();
      return widget.spec.kind == InputKind.percent
          ? v.toStringAsFixed(1)
          : v.toInt().toString();
    }
    return v.toString();
  }

  @override
  void didUpdateWidget(InputRow old) {
    super.didUpdateWidget(old);
    if (!_node.hasFocus && _display() != _ctl.text) {
      _ctl.text = _display();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _node.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final s = widget.spec;
    if (s.kind == InputKind.money) {
      final m = Money.tryParse(raw);
      if (m != null) widget.onChanged(m);
    } else {
      final d = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.\-]'), ''));
      if (d != null) {
        final clamped = d
            .clamp(s.min ?? double.negativeInfinity, s.max ?? double.infinity)
            .toDouble();
        // Say so when the typed value is not the one being used.
        final note = clamped == d
            ? null
            : (d > clamped
                  ? 'Using the maximum, ${_trim(clamped)}${s.unit ?? ""}'
                  : 'Using the minimum, ${_trim(clamped)}${s.unit ?? ""}');
        if (note != _clampNote) setState(() => _clampNote = note);
        widget.onChanged(clamped);
      }
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.spec;
    final active = _node.hasFocus || widget.focused;

    if (s.kind == InputKind.choice) {
      return _ChoiceRow(
        spec: s,
        value: widget.value.toString(),
        last: widget.last,
        onChanged: widget.onChanged,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: S.rowHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.label,
                  style: T.body.copyWith(color: c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: S.sm),
              if (s.kind == InputKind.money || s.kind == InputKind.decimal)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    'SGD',
                    style: T.figureSm.copyWith(
                      color: widget.isExample
                          ? c.inkMute.withValues(alpha: 0.45)
                          : c.inkMute,
                    ),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: IntrinsicWidth(
                  child: TextField(
                    controller: _ctl,
                    focusNode: _node,
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                    ],
                    style: T.figure.copyWith(
                      color: widget.isExample
                          ? c.ink.withValues(alpha: 0.38)
                          : c.ink,
                    ),
                    cursorColor: c.accent,
                    cursorWidth: 1.5,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: _commit,
                  ),
                ),
              ),
              if (s.unit != null) ...[
                const SizedBox(width: 6),
                Text(
                  s.unit!,
                  style: T.figureSm.copyWith(
                    color: widget.isExample
                        ? c.inkMute.withValues(alpha: 0.45)
                        : c.inkMute,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_clampNote != null)
          Padding(
            padding: const EdgeInsets.only(bottom: S.sm),
            child: Text(
              _clampNote!,
              style: T.label.copyWith(color: c.warn, letterSpacing: 0),
            ),
          )
        else if (s.hint != null && active)
          Padding(
            padding: const EdgeInsets.only(bottom: S.sm),
            child: Text(
              s.hint!,
              style: T.label.copyWith(color: c.inkMute, letterSpacing: 0),
            ),
          ),
        if (!widget.last)
          Container(
            height: active ? 1.5 : 1,
            color: active ? c.accent : c.line,
          ),
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  final CalcInput spec;
  final String value;
  final bool last;
  final ValueChanged<Object> onChanged;

  const _ChoiceRow({
    required this.spec,
    required this.value,
    required this.last,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pills = [
      for (final opt in spec.choices)
        _Pill(label: opt, selected: opt == value, onTap: () => onChanged(opt)),
    ];
    // Two short options sit beside the label. Anything longer wraps onto its
    // own line: a sideways-scrolling row hid the first option off-screen.
    final inline =
        spec.choices.length <= 2 &&
        spec.choices.fold<int>(0, (n, o) => n + o.length) <= 16;
    final label = Text(spec.label, style: T.body.copyWith(color: c.ink));
    // Full width even without the hairline below it, or the last row
    // shrinks to its content and centres in the card.
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.md),
            child: inline
                ? Row(
                    children: [
                      Expanded(child: label),
                      const SizedBox(width: S.sm),
                      for (final p in pills)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: p,
                        ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label,
                      const SizedBox(height: S.sm),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final p in pills) IntrinsicWidth(child: p),
                        ],
                      ),
                    ],
                  ),
          ),
          if (!last) const Hairline(),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : Colors.transparent,
          borderRadius: R.pill,
          border: Border.all(color: selected ? c.accent : c.line),
        ),
        child: Text(
          label,
          style: T.figureSm.copyWith(
            color: selected ? c.accent : c.inkMute,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ResultStack — the figure you came for, twice the size of everything else
// ---------------------------------------------------------------------------

class ResultStack extends StatelessWidget {
  final CalcResult result;
  final bool live;

  /// True while every input still holds its seeded value, so the headline is
  /// worked out from an example rather than from anything the user gave us.
  /// Saying so is the difference between a demo and a claim about their money.
  final bool isExample;

  const ResultStack({
    super.key,
    required this.result,
    this.live = true,
    this.isExample = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    if (result.error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(S.cardPad),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: R.card,
          border: Border.all(color: c.negative),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CANNOT COMPUTE', style: T.label.copyWith(color: c.negative)),
            const SizedBox(height: S.sm),
            Text(result.error!, style: T.body.copyWith(color: c.ink)),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: R.card),
      padding: const EdgeInsets.all(S.cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result.primaryLabel,
                  style: T.label.copyWith(color: c.inkMute),
                ),
              ),
              if (live) _LivePill(isExample: isExample),
            ],
          ),
          const SizedBox(height: S.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              result.primaryValue,
              style: T.figureL.copyWith(color: c.ink),
            ),
          ),
          if (result.secondary.isNotEmpty) ...[
            const SizedBox(height: S.lg),
            Container(height: 1, color: c.line),
            const SizedBox(height: S.md),
            _SecondaryGrid(metrics: result.secondary),
          ],
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  final bool isExample;
  const _LivePill({this.isExample = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.ground.withValues(alpha: 0.6),
        borderRadius: R.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: isExample ? c.inkMute : c.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            isExample ? 'EXAMPLE' : 'LIVE',
            style: T.label.copyWith(
              color: isExample ? c.inkMute : c.accent,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryGrid extends StatelessWidget {
  final List<Metric> metrics;
  const _SecondaryGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < metrics.length; i += 2) {
      final a = metrics[i];
      final b = i + 1 < metrics.length ? metrics[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < metrics.length ? S.md : 0),
          // Equal heights, so a label that wraps on a narrow phone does not
          // push its value below the value beside it.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _MetricCell(a)),
                const SizedBox(width: S.md),
                Expanded(child: b == null ? const SizedBox() : _MetricCell(b)),
              ],
            ),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

class _MetricCell extends StatelessWidget {
  final Metric m;
  const _MetricCell(this.m);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          m.label.toUpperCase(),
          style: T.label.copyWith(color: c.inkMute, fontSize: 11),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            m.value,
            style: T.figure.copyWith(color: toneColor(context, m.tone)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// DeltaLine
// ---------------------------------------------------------------------------

class DeltaLineView extends StatelessWidget {
  final DeltaNote note;
  const DeltaLineView({super.key, required this.note});

  @override
  Widget build(BuildContext context) {
    final col = toneColor(context, note.tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.08),
        borderRadius: R.input,
        border: Border(left: BorderSide(color: col, width: 2)),
      ),
      child: Text(note.text, style: T.figureSm.copyWith(color: col)),
    );
  }
}

// ---------------------------------------------------------------------------
// AssumptionChip
// ---------------------------------------------------------------------------

class AssumptionChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const AssumptionChip(this.label, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        margin: const EdgeInsets.only(right: S.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: R.pill,
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: T.figureSm.copyWith(color: c.inkMute)),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, size: 14, color: c.inkMute),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SeriesChart — printed-plate aesthetic: baseline only, no gridlines
// ---------------------------------------------------------------------------

class SeriesChart extends StatelessWidget {
  final List<Series> series;
  final String? xStartLabel;
  final String? xEndLabel;
  final double height;

  const SeriesChart({
    super.key,
    required this.series,
    this.xStartLabel,
    this.xEndLabel,
    this.height = 160,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (series.isEmpty || series.every((s) => s.points.length < 2)) {
      return const SizedBox.shrink();
    }

    var maxY = 0.0;
    for (final s in series) {
      for (final p in s.points) {
        if (p.y > maxY) maxY = p.y;
      }
    }
    if (maxY <= 0) maxY = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (series.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: S.sm),
            child: Wrap(
              spacing: S.md,
              children: [
                for (final s in series)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 2,
                        color: seriesColor(context, s.tone),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        s.name,
                        style: T.label.copyWith(color: c.inkMute, fontSize: 11),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        // No CrossAxisAlignment.stretch here: inside an unbounded-height
        // parent it hands children an infinite height constraint and the
        // layout throws. Both children state their own height already.
        SizedBox(
          height: height,
          child: Row(
            children: [
              SizedBox(
                width: 62,
                height: height,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _axis(maxY),
                      style: T.figureSm.copyWith(
                        color: c.inkMute,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '0',
                      style: T.figureSm.copyWith(
                        color: c.inkMute,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: height,
                  child: CustomPaint(
                    painter: _ChartPainter(
                      series: series,
                      maxY: maxY,
                      lineColor: c.line,
                      colors: {
                        for (final s in series)
                          s.name: seriesColor(context, s.tone),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (xStartLabel != null || xEndLabel != null)
          Padding(
            padding: const EdgeInsets.only(left: 62, top: S.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  xStartLabel ?? '',
                  style: T.figureSm.copyWith(color: c.inkMute, fontSize: 11),
                ),
                Text(
                  xEndLabel ?? '',
                  style: T.figureSm.copyWith(color: c.inkMute, fontSize: 11),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _axis(double v) {
    if (v >= 1000000) return 'S\$ ${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return 'S\$ ${(v / 1000).toStringAsFixed(0)}k';
    return 'S\$ ${v.toStringAsFixed(0)}';
  }
}

class _ChartPainter extends CustomPainter {
  final List<Series> series;
  final double maxY;
  final Color lineColor;
  final Map<String, Color> colors;

  _ChartPainter({
    required this.series,
    required this.maxY,
    required this.lineColor,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Single baseline, per the design system. No grid.
    final base = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      base,
    );

    for (final s in series) {
      if (s.points.length < 2) continue;
      final col = colors[s.name] ?? lineColor;
      final maxX = s.points.last.x == 0 ? 1.0 : s.points.last.x;

      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final p = s.points[i];
        final dx = (p.x / maxX) * size.width;
        final dy = size.height - (p.y / maxY) * (size.height - 4);
        if (i == 0) {
          path.moveTo(dx, dy);
        } else {
          path.lineTo(dx, dy);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = col
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );

      // Emphasised endpoint — the same dot that rides the splash loader.
      final last = s.points.last;
      canvas.drawCircle(
        Offset(
          (last.x / maxX) * size.width,
          size.height - (last.y / maxY) * (size.height - 4),
        ),
        3,
        Paint()..color = col,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.maxY != maxY || old.series != series;
}

// ---------------------------------------------------------------------------
// SolveForBar
// ---------------------------------------------------------------------------

class SolveForBar extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  const SolveForBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: R.pill,
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(o),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: o == selected ? c.accent : Colors.transparent,
                    borderRadius: R.pill,
                  ),
                  child: Text(
                    o,
                    style: T.figureSm.copyWith(
                      color: o == selected ? c.ground : c.inkMute,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SaveBar
// ---------------------------------------------------------------------------

class SaveBar extends StatelessWidget {
  /// Null while there is nothing valid to save; the button then shows as
  /// disabled instead of looking tappable and silently doing nothing.
  final VoidCallback? onSave;
  final VoidCallback? onCompare;
  final String primaryLabel;
  final String secondaryLabel;

  /// When false the secondary button is not shown at all. When true but
  /// [onCompare] is null it stays in place, disabled, so the bar does not
  /// jump while a field is half-typed.
  final bool showSecondary;

  const SaveBar({
    super.key,
    required this.onSave,
    this.onCompare,
    this.primaryLabel = 'Save scenario',
    this.secondaryLabel = 'Compare',
    this.showSecondary = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final saveEnabled = onSave != null;
    final secondaryEnabled = onCompare != null;
    return Container(
      padding: EdgeInsets.fromLTRB(
        S.margin,
        S.md,
        S.margin,
        S.md + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: c.ground,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          if (showSecondary) ...[
            Expanded(
              flex: 2,
              child: Semantics(
                button: true,
                enabled: secondaryEnabled,
                child: GestureDetector(
                  onTap: onCompare,
                  child: Opacity(
                    opacity: secondaryEnabled ? 1 : 0.4,
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: R.input,
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        secondaryLabel,
                        style: T.body.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: S.md),
          ],
          Expanded(
            flex: 3,
            child: Semantics(
              button: true,
              enabled: saveEnabled,
              child: GestureDetector(
                onTap: onSave,
                child: Opacity(
                  opacity: saveEnabled ? 1 : 0.4,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: R.input,
                    ),
                    child: Text(
                      primaryLabel,
                      style: T.body.copyWith(
                        color: c.ground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

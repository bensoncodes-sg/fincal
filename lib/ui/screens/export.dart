import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/calculator.dart';
import '../theme.dart';
import '../../platform/save_text_io.dart'
    if (dart.library.js_interop) '../../platform/save_text_web.dart';

/// Export without plugins.
///
/// A share sheet or a PDF writer would both be plugins, and plugins cannot be
/// built on this machine. What is available without them is genuinely useful:
/// CSV on the clipboard, and a file on disk whose path is shown. Both are
/// real exports; neither pretends to be a share sheet.
String csvEscape(String v) =>
    v.contains(',') || v.contains('"') || v.contains('\n')
    ? '"${v.replaceAll('"', '""')}"'
    : v;

/// Full CSV for one calculation: inputs, headline, supporting figures,
/// assumptions, then the schedule if there is one.
String csvForResult({
  required String calculatorName,
  required List<CalcInput> inputs,
  required Inputs values,
  required CalcResult result,
}) {
  final b = StringBuffer()
    ..writeln('Basis export')
    ..writeln('Calculator,${csvEscape(calculatorName)}')
    ..writeln('Generated,${DateTime.now().toIso8601String()}')
    ..writeln()
    ..writeln('Inputs');
  for (final spec in inputs) {
    final v = values[spec.key];
    final text = switch (v) {
      null => '',
      // Whole numbers print the same natively and on the web.
      final num n when n == n.roundToDouble() => n.toInt().toString(),
      final Object o => o.toString(),
    };
    b.writeln(
      '${csvEscape(spec.label)},${csvEscape(text)}'
      '${spec.unit != null ? ',${csvEscape(spec.unit!)}' : ''}',
    );
  }

  b
    ..writeln()
    ..writeln('Result')
    ..writeln(
      '${csvEscape(result.primaryLabel)},'
      '${csvEscape(result.primaryValue)}',
    );
  for (final m in result.secondary) {
    b.writeln('${csvEscape(m.label)},${csvEscape(m.value)}');
  }

  final explain = result.explain;
  if (explain != null && explain.assumptions.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Assumptions');
    for (final a in explain.assumptions) {
      b.writeln('${csvEscape(a.label)},${csvEscape(a.value)}');
    }
  }

  if (result.schedule.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Schedule')
      ..writeln('No,Date,Payment,Principal,Interest,Balance');
    for (final r in result.schedule) {
      // Figures are grouped with commas, so every field must be escaped or
      // each row silently splits into ten columns instead of six.
      b.writeln(
        [
          '${r.number}',
          shortDate(r.date),
          r.payment.format(),
          r.principal.format(),
          r.interest.format(),
          r.balance.format(),
        ].map(csvEscape).join(','),
      );
    }
  }
  return b.toString();
}

Future<void> showExportSheet(
  BuildContext context, {
  required String title,
  required String csv,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ExportSheet(title: title, csv: csv, colors: context.c),
  );
}

class _ExportSheet extends StatefulWidget {
  final String title;
  final String csv;
  final BasisColors colors;
  const _ExportSheet({
    required this.title,
    required this.csv,
    required this.colors,
  });

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  String? _status;
  bool _failed = false;

  int get _rowCount => widget.csv.trim().split('\n').length;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.csv));
      setState(() {
        _failed = false;
        _status = 'Copied $_rowCount rows. Paste into a spreadsheet.';
      });
    } catch (e) {
      setState(() {
        _failed = true;
        _status = 'Could not reach the clipboard.';
      });
    }
  }

  Future<void> _writeFile() async {
    try {
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final name = widget.title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final message = await saveTextFile('$name-$stamp.csv', widget.csv);
      if (!mounted) return;
      setState(() {
        _failed = false;
        _status = message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _status = 'Could not write the file ($e).';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Container(
      decoration: BoxDecoration(color: c.ground, borderRadius: R.sheet),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
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
          Text('Export ${widget.title}', style: T.title.copyWith(color: c.ink)),
          const SizedBox(height: S.xs),
          Text(
            '$_rowCount rows of CSV, including the assumptions behind '
            'every figure.',
            style: T.bodySm.copyWith(color: c.inkMute),
          ),
          const SizedBox(height: S.lg),

          Text('PREVIEW', style: T.label.copyWith(color: c.inkMute)),
          const SizedBox(height: S.sm),
          Flexible(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(S.md),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: R.input,
                border: Border.all(color: c.line),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.csv.length > 1200
                      ? '${widget.csv.substring(0, 1200)}\n…'
                      : widget.csv,
                  style: T.figureSm.copyWith(color: c.ink, height: 1.5),
                ),
              ),
            ),
          ),

          if (_status != null) ...[
            const SizedBox(height: S.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(S.md),
              decoration: BoxDecoration(
                borderRadius: R.input,
                color: (_failed ? c.negative : c.accent).withValues(
                  alpha: 0.08,
                ),
                border: Border(
                  left: BorderSide(
                    color: _failed ? c.negative : c.accent,
                    width: 2,
                  ),
                ),
              ),
              child: SelectableText(
                _status!,
                style: T.figureSm.copyWith(
                  color: _failed ? c.negative : c.accent,
                ),
              ),
            ),
          ],

          const SizedBox(height: S.lg),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _writeFile,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: R.input,
                      border: Border.all(color: c.line),
                    ),
                    child: Text(
                      kSaveIsDownload ? 'Download CSV' : 'Save file',
                      style: T.body.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: S.md),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _copy,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: R.input,
                      color: c.accent,
                    ),
                    child: Text(
                      'Copy CSV',
                      style: T.body.copyWith(
                        color: c.ground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

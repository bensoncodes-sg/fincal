import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../feedback.dart';
import '../theme.dart';

/// The feedback form.
///
/// It tells the truth about what happened to the message: "Sent" only when an
/// endpoint actually accepted it, "Saved on this device" otherwise, with the
/// text offered for copying so the person is never left guessing.
Future<void> showFeedbackSheet(
  BuildContext context, {
  required FeedbackService service,
  required String rulesetVersion,
  String? calculatorId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _FeedbackSheet(
        service: service,
        rulesetVersion: rulesetVersion,
        calculatorId: calculatorId,
        colors: context.c,
      ),
    ),
  );
}

class _FeedbackSheet extends StatefulWidget {
  final FeedbackService service;
  final String rulesetVersion;
  final String? calculatorId;
  final BasisColors colors;

  const _FeedbackSheet({
    required this.service,
    required this.rulesetVersion,
    required this.calculatorId,
    required this.colors,
  });

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _controller = TextEditingController();
  FeedbackCategory _category = FeedbackCategory.wrongNumber;
  int? _rating;
  bool _busy = false;
  FeedbackOutcome? _outcome;
  FeedbackItem? _submitted;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSend => _controller.text.trim().isNotEmpty && !_busy;

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() => _busy = true);

    final item = FeedbackItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      category: _category,
      rating: _rating,
      message: _controller.text.trim(),
      calculatorId: widget.calculatorId,
      rulesetVersion: widget.rulesetVersion,
      createdAt: DateTime.now(),
    );

    final outcome = await widget.service.submit(item);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
      _submitted = item;
    });
  }

  Future<void> _copy() async {
    final item = _submitted;
    if (item == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: item.asText()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied', style: T.body),
          backgroundColor: widget.colors.ink,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      // Clipboard is unavailable; the text is still on screen to select.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Container(
      decoration: BoxDecoration(color: c.ground, borderRadius: R.sheet),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(S.margin, S.md, S.margin, S.xl),
      child: SingleChildScrollView(
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

            if (_outcome == null) ..._form(c) else ..._done(c),
          ],
        ),
      ),
    );
  }

  List<Widget> _form(BasisColors c) => [
    Text('Send feedback', style: T.title.copyWith(color: c.ink)),
    const SizedBox(height: S.xs),
    Text(
      'A wrong number is the most useful thing you can report. Tell us '
      'what you entered and what you expected.',
      style: T.bodySm.copyWith(color: c.inkMute),
    ),
    const SizedBox(height: S.lg),

    Text('WHAT IS THIS ABOUT', style: T.label.copyWith(color: c.inkMute)),
    const SizedBox(height: S.sm),
    Wrap(
      spacing: S.sm,
      runSpacing: S.sm,
      children: [
        for (final cat in FeedbackCategory.values)
          GestureDetector(
            onTap: () => setState(() => _category = cat),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cat == _category ? c.accentSoft : c.surface,
                borderRadius: R.pill,
                border: Border.all(color: cat == _category ? c.accent : c.line),
              ),
              child: Text(
                cat.label,
                style: T.figureSm.copyWith(
                  color: cat == _category ? c.accent : c.inkMute,
                  fontWeight: cat == _category
                      ? FontWeight.w600
                      : FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    ),

    const SizedBox(height: S.lg),
    Row(
      children: [
        Expanded(
          child: Text(
            'HOW IS IT WORKING FOR YOU',
            style: T.label.copyWith(color: c.inkMute),
          ),
        ),
        Text(
          _rating == null ? 'Optional' : '$_rating/5',
          style: T.figureSm.copyWith(color: c.inkMute),
        ),
      ],
    ),
    const SizedBox(height: S.sm),
    Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _rating = _rating == i ? null : i),
              child: Container(
                height: 40,
                margin: EdgeInsets.only(right: i == 5 ? 0 : S.sm),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (_rating ?? 0) >= i ? c.accentSoft : c.surface,
                  borderRadius: R.input,
                  border: Border.all(
                    color: (_rating ?? 0) >= i ? c.accent : c.line,
                  ),
                ),
                child: Text(
                  '$i',
                  style: T.figure.copyWith(
                    color: (_rating ?? 0) >= i ? c.accent : c.inkMute,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),

    const SizedBox(height: S.lg),
    Text('MESSAGE', style: T.label.copyWith(color: c.inkMute)),
    const SizedBox(height: S.sm),
    Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: R.input,
        border: Border.all(color: c.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: S.md),
      child: TextField(
        controller: _controller,
        maxLines: 5,
        minLines: 4,
        style: T.body.copyWith(color: c.ink),
        cursorColor: c.accent,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'A 25-year loan of 500,000 at 3.5% showed…',
          hintStyle: T.body.copyWith(color: c.inkMute),
        ),
      ),
    ),

    const SizedBox(height: S.md),
    Text(
      'Sent with your message: the ruleset revision '
      '(${widget.rulesetVersion})'
      '${widget.calculatorId != null ? " and which calculator you were on" : ""}. '
      'Nothing that identifies you, and none of your figures.',
      style: T.label.copyWith(
        color: c.inkMute,
        letterSpacing: 0,
        fontSize: 11.5,
      ),
    ),

    const SizedBox(height: S.lg),
    GestureDetector(
      onTap: _send,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: R.input,
          color: _canSend ? c.accent : c.line,
        ),
        child: Text(
          _busy ? 'Sending…' : 'Send feedback',
          style: T.body.copyWith(
            color: _canSend ? c.ground : c.inkMute,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  ];

  List<Widget> _done(BasisColors c) {
    final sent = _outcome == FeedbackOutcome.sent;
    final rejected = _outcome == FeedbackOutcome.rejected;
    final tone = rejected ? c.negative : (sent ? c.accent : c.warn);

    return [
      Text(
        rejected
            ? 'Nothing to send'
            : sent
            ? 'Sent — thank you'
            : 'Saved on this device',
        style: T.title.copyWith(color: c.ink),
      ),
      const SizedBox(height: S.sm),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(S.md),
        decoration: BoxDecoration(
          borderRadius: R.input,
          color: tone.withValues(alpha: 0.08),
          border: Border(left: BorderSide(color: tone, width: 2)),
        ),
        child: Text(
          rejected
              ? 'The message was empty.'
              : sent
              ? 'Your message reached us. Nothing else to do.'
              : 'There is no feedback endpoint configured in this build, '
                    'so your message is queued on this device. Copy it below '
                    'and send it however you like — it will also go out '
                    'automatically once an endpoint is set.',
          style: T.bodySm.copyWith(color: tone),
        ),
      ),
      if (_submitted != null) ...[
        const SizedBox(height: S.lg),
        Text('YOUR MESSAGE', style: T.label.copyWith(color: c.inkMute)),
        const SizedBox(height: S.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(S.md),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: R.input,
            border: Border.all(color: c.line),
          ),
          child: SelectableText(
            _submitted!.asText(),
            style: T.figureSm.copyWith(color: c.ink, height: 1.5),
          ),
        ),
      ],
      const SizedBox(height: S.lg),
      Row(
        children: [
          if (!sent && !rejected) ...[
            Expanded(
              child: GestureDetector(
                onTap: _copy,
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: R.input,
                    border: Border.all(color: c.line),
                  ),
                  child: Text(
                    'Copy',
                    style: T.body.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: S.md),
          ],
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: R.input,
                  color: c.accent,
                ),
                child: Text(
                  'Done',
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
    ];
  }
}

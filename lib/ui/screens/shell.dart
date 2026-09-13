import 'package:flutter/material.dart';

import '../../calculators/registry.dart';
import '../../core/calculator.dart';
import '../../core/money.dart';
import '../../state.dart';
import '../components.dart';
import '../theme.dart';
import 'calculator_screen.dart';
import 'compare.dart';
import 'feedback_sheet.dart';
import 'splash.dart';

class Shell extends StatefulWidget {
  final AppState app;
  const Shell({super.key, required this.app});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedBuilder(
      animation: widget.app,
      builder: (context, _) => Scaffold(
        backgroundColor: c.ground,
        body: SafeArea(
          bottom: false,
          child: switch (_tab) {
            1 => SavedTab(app: widget.app),
            2 => CompareTab(app: widget.app),
            3 => SettingsTab(app: widget.app),
            _ => HomeTab(app: widget.app),
          },
        ),
        bottomNavigationBar: _TabBar(
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _TabBar({required this.index, required this.onChanged});

  static const _items = [
    (Icons.calculate_outlined, 'Home'),
    (Icons.bookmark_border, 'Saved'),
    (Icons.compare_arrows, 'Compare'),
    (Icons.tune, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
        top: 6,
      ),
      decoration: BoxDecoration(
        color: c.ground,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < _items.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.md,
                  vertical: 6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _items[i].$1,
                      size: 20,
                      color: i == index ? c.accent : c.inkMute,
                    ),
                    const SizedBox(height: S.xs),
                    Text(
                      _items[i].$2.toUpperCase(),
                      style: T.label.copyWith(
                        fontSize: 10,
                        color: i == index ? c.accent : c.inkMute,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home — the question hub
// ---------------------------------------------------------------------------

class HomeTab extends StatelessWidget {
  final AppState app;
  const HomeTab({super.key, required this.app});

  static const _icons = {
    Question.afford: Icons.home_outlined,
    Question.loanCost: Icons.account_balance_outlined,
    Question.later: Icons.timeline_outlined,
    Question.worthIt: Icons.trending_up,
    Question.takeHome: Icons.receipt_long_outlined,
    Question.quick: Icons.bolt_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final recent = app.scenarios.take(2).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.margin, S.sm, S.margin, S.xl),
      children: [
        Row(
          children: [
            const BasisMark(size: 30),
            const SizedBox(width: S.sm),
            Expanded(
              child: Text('Basis', style: T.title.copyWith(color: c.ink)),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.line),
              ),
              alignment: Alignment.center,
              child: Text('B', style: T.figureSm.copyWith(color: c.inkMute)),
            ),
          ],
        ),
        const SizedBox(height: S.lg),
        Text(
          'What are you working out today?',
          style: T.body.copyWith(color: c.inkMute),
        ),
        const SizedBox(height: S.lg),
        for (final q in Question.values)
          Padding(
            padding: const EdgeInsets.only(bottom: S.gutter),
            child: _QuestionCard(
              question: q,
              icon: _icons[q]!,
              count: builtCountFor(q),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CategoryScreen(question: q, app: app),
                ),
              ),
            ),
          ),
        if (recent.isNotEmpty) ...[
          const SectionLabel('Recent'),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recent.length,
              separatorBuilder: (_, _) => const SizedBox(width: S.gutter),
              itemBuilder: (_, i) => _RecentCard(scenario: recent[i], app: app),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final Question question;
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  const _QuestionCard({
    required this.question,
    required this.icon,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: S.cardPad),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: R.card,
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: R.input,
              ),
              child: Icon(icon, size: 19, color: c.accent),
            ),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    question.label,
                    style: T.title.copyWith(color: c.ink, fontSize: 17),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    count == 0
                        ? 'COMING SOON'
                        : '$count ${count == 1 ? "TOOL" : "TOOLS"}',
                    style: T.label.copyWith(
                      color: count == 0 ? c.inkMute : c.inkMute,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: c.inkMute),
          ],
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final Scenario scenario;
  final AppState app;
  const _RecentCard({required this.scenario, required this.app});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final calc = calculatorById(scenario.calculatorId);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: calc == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CalculatorScreen(
                  calculator: calc,
                  app: app,
                  scenario: scenario,
                ),
              ),
            ),
      child: _recentBody(c),
    );
  }

  Widget _recentBody(BasisColors c) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(S.cardPad),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: R.card,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  scenario.headlineLabel,
                  style: T.label.copyWith(color: c.inkMute, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Seeded demo scenarios are labelled here exactly as they are in
              // Saved. A figure on the home screen that looks like the user's
              // own history, but isn't, is the same lie in a smaller font.
              if (scenario.isExample)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: R.pill,
                    border: Border.all(color: c.line),
                  ),
                  child: Text(
                    'EXAMPLE',
                    style: T.label.copyWith(color: c.inkMute, fontSize: 9),
                  ),
                ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              scenario.headlineValue,
              style: T.figure.copyWith(
                color: scenario.isExample
                    ? c.ink.withValues(alpha: 0.45)
                    : c.ink,
                fontSize: 22,
              ),
            ),
          ),
          Text(
            scenario.relativeTime,
            style: T.figureSm.copyWith(color: c.inkMute, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category
// ---------------------------------------------------------------------------

class CategoryScreen extends StatelessWidget {
  final Question question;
  final AppState app;
  const CategoryScreen({super.key, required this.question, required this.app});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tools = calculatorsFor(question);

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.ground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.ink),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.margin, 0, S.margin, S.xl),
        children: [
          Text(question.label, style: T.display.copyWith(color: c.ink)),
          const SizedBox(height: S.sm),
          Text(
            tools.isEmpty
                ? 'Not built yet.'
                : '${tools.length} ${tools.length == 1 ? "tool" : "tools"}. Every result saves.',
            style: T.body.copyWith(color: c.inkMute),
          ),
          const SizedBox(height: S.lg),
          for (final t in tools)
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CalculatorScreen(calculator: t, app: app),
                ),
              ),
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      t.name,
                                      style: T.body.copyWith(
                                        color: c.ink,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (t.sgSpecific) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: c.accentSoft,
                                        borderRadius: R.pill,
                                      ),
                                      child: Text(
                                        'SG',
                                        style: T.label.copyWith(
                                          color: c.accent,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t.description,
                                style: T.label.copyWith(
                                  color: c.inkMute,
                                  fontSize: 11,
                                  letterSpacing: 0,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: c.inkMute),
                      ],
                    ),
                  ),
                  const Hairline(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saved
// ---------------------------------------------------------------------------

class SavedTab extends StatelessWidget {
  final AppState app;
  const SavedTab({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final all = app.scenarios;

    if (all.isEmpty) {
      return _Empty(
        icon: Icons.description_outlined,
        title: 'Nothing saved yet',
        body:
            "Work something out and tap Save. It'll be here when you come back.",
      );
    }

    final thisWeek = all.where((s) => s.isThisWeek).toList();
    final earlier = all.where((s) => !s.isThisWeek).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.margin, S.sm, S.margin, S.xl),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Saved', style: T.display.copyWith(color: c.ink)),
            const SizedBox(width: S.sm),
            Text('${all.length}', style: T.figure.copyWith(color: c.inkMute)),
          ],
        ),
        if (thisWeek.isNotEmpty) ...[
          const SectionLabel('This week'),
          for (final s in thisWeek) _ScenarioCard(scenario: s, app: app),
        ],
        if (earlier.isNotEmpty) ...[
          const SectionLabel('Earlier'),
          for (final s in earlier) _ScenarioCard(scenario: s, app: app),
        ],
      ],
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  final Scenario scenario;
  final AppState app;
  const _ScenarioCard({required this.scenario, required this.app});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final selected = app.compareIds.contains(scenario.id);
    final calc = calculatorById(scenario.calculatorId);
    final isExample = scenario.isExample;

    return Padding(
      padding: const EdgeInsets.only(bottom: S.gutter),
      child: Dismissible(
        key: ValueKey(scenario.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: S.cardPad),
          decoration: BoxDecoration(color: c.negative, borderRadius: R.card),
          child: Text(
            'Delete',
            style: T.body.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        onDismissed: (_) => app.deleteScenario(scenario.id),
        child: Container(
          padding: const EdgeInsets.all(S.cardPad),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: R.card,
            border: Border.all(color: selected ? c.accent : c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      calc?.name.toUpperCase() ??
                          scenario.calculatorId.toUpperCase(),
                      style: T.label.copyWith(color: c.inkMute, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isExample)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: R.pill,
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        'EXAMPLE',
                        style: T.label.copyWith(color: c.inkMute, fontSize: 9),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: S.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      scenario.name,
                      style: T.body.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(width: S.sm),
                  Text(
                    scenario.headlineValue,
                    style: T.figure.copyWith(color: c.ink),
                  ),
                ],
              ),
              const SizedBox(height: S.md),
              const Hairline(),
              const SizedBox(height: S.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      scenario.relativeTime,
                      style: T.figureSm.copyWith(
                        color: c.inkMute,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => app.toggleCompare(scenario.id),
                    child: Text(
                      selected ? 'In compare' : 'Compare',
                      style: T.label.copyWith(
                        color: selected ? c.accent : c.accent,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: S.lg),
                  if (calc != null)
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CalculatorScreen(
                            calculator: calc,
                            app: app,
                            scenario: scenario,
                          ),
                        ),
                      ),
                      child: Text(
                        'OPEN',
                        style: T.label.copyWith(color: c.accent, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compare
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class SettingsTab extends StatelessWidget {
  final AppState app;
  const SettingsTab({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = app.rules;

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.margin, S.sm, S.margin, S.xl),
      children: [
        Text('Settings', style: T.display.copyWith(color: c.ink)),
        const SectionLabel('Singapore rules'),
        BasisCard(
          padding: const EdgeInsets.symmetric(horizontal: S.cardPad),
          child: Column(
            children: [
              _RuleRow('TDSR ceiling', pct(r.tdsrCeilingPct, dp: 0)),
              _RuleRow('MSR ceiling (HDB/EC)', pct(r.msrCeilingPct, dp: 0)),
              _RuleRow('Stress-test floor', pct(r.stressTestFloorPct, dp: 2)),
              _RuleRow(
                'CPF wage ceiling',
                Money.fromDouble(r.cpfOrdinaryWageCeiling).sgd0,
              ),
              _RuleRow('GST', pct(r.gstPct, dp: 0), last: true),
            ],
          ),
        ),
        const SizedBox(height: S.md),
        Container(
          padding: const EdgeInsets.all(S.md),
          decoration: BoxDecoration(
            borderRadius: R.input,
            color: c.warn.withValues(alpha: 0.08),
            border: Border(left: BorderSide(color: c.warn, width: 2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule, size: 15, color: c.warn),
              const SizedBox(width: S.sm),
              Expanded(
                child: Text(
                  'Rules last verified ${r.verifiedOn.day} '
                  '${monthYear(r.verifiedOn)} (${r.daysSinceVerified} days ago). '
                  'Check MAS, IRAS and the CPF Board before relying on these.',
                  style: T.bodySm.copyWith(color: c.warn),
                ),
              ),
            ],
          ),
        ),
        const SectionLabel('Defaults'),
        BasisCard(
          padding: const EdgeInsets.symmetric(horizontal: S.cardPad),
          child: Column(
            children: const [
              _RuleRow('Rounding', 'Half-even, 2 d.p.'),
              _RuleRow('Day count', '30/360'),
              _RuleRow('Compounding', 'Monthly'),
              _RuleRow('Rate convention', 'Nominal ÷ 12'),
              _RuleRow('Currency', 'SGD', last: true),
            ],
          ),
        ),
        const SectionLabel('Appearance'),
        BasisCard(
          padding: const EdgeInsets.symmetric(
            horizontal: S.cardPad,
            vertical: S.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('Theme', style: T.body.copyWith(color: c.ink)),
              ),
              for (final m in BasisThemeMode.values)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () => app.setBasisThemeMode(m),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: app.themeMode == m
                            ? c.accentSoft
                            : Colors.transparent,
                        borderRadius: R.pill,
                        border: Border.all(
                          color: app.themeMode == m ? c.accent : c.line,
                        ),
                      ),
                      child: Text(
                        m.name,
                        style: T.figureSm.copyWith(
                          color: app.themeMode == m ? c.accent : c.inkMute,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SectionLabel('About'),
        Text(
          'Basis computes in integer cents and solves rates with Newton–Raphson '
          'backed by bisection. Where a value cannot be determined it says so '
          'rather than showing a plausible number.',
          style: T.bodySm.copyWith(color: c.inkMute),
        ),
        const SizedBox(height: S.sm),
        Text(
          'SG RULESET · REV ${r.version}',
          style: T.figureSm.copyWith(color: c.inkMute, fontSize: 11),
        ),

        const SectionLabel('Feedback'),
        Text(
          'If a number looks wrong, that is the most useful thing you can '
          'tell us. Say what you entered and what you expected.',
          style: T.bodySm.copyWith(color: c.inkMute),
        ),
        const SizedBox(height: S.md),
        GestureDetector(
          onTap: () => showFeedbackSheet(
            context,
            service: app.feedback,
            rulesetVersion: r.version,
          ),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: R.input,
              border: Border.all(color: c.accent),
              color: c.accentSoft,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 17, color: c.accent),
                const SizedBox(width: S.sm),
                Text(
                  'Send feedback',
                  style: T.body.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: S.sm),
        FutureBuilder<int>(
          future: app.feedback.pending().then((p) => p.length),
          builder: (context, snap) {
            final n = snap.data ?? 0;
            if (n == 0) return const SizedBox.shrink();
            // Saying "sent" when nothing left the device would be a lie, so
            // the queue is shown instead.
            return Text(
              '$n message${n == 1 ? "" : "s"} waiting on this device — no '
              'feedback endpoint is configured in this build.',
              style: T.label.copyWith(
                color: c.warn,
                letterSpacing: 0,
                fontSize: 11.5,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  final String label;
  final String value;
  final bool last;
  const _RuleRow(this.label, this.value, {this.last = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        SizedBox(
          height: S.rowHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: T.body.copyWith(color: c.ink)),
              ),
              Text(value, style: T.figure.copyWith(color: c.ink)),
            ],
          ),
        ),
        if (!last) const Hairline(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Empty({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(S.margin * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: c.line),
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

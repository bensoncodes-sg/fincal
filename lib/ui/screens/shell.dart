import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../calculators/registry.dart';
import '../../core/calculator.dart';
import '../../core/money.dart';
import '../../state.dart';
import '../components.dart';
import '../theme.dart';
import 'calculator_screen.dart';
import 'compare.dart';
import 'feedback_sheet.dart';
import '../glossary.dart';
import '../tour.dart';
import '../visuals.dart';

class Shell extends StatefulWidget {
  final AppState app;
  const Shell({super.key, required this.app});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  TourController? _tour;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tour = TourScope.maybeOf(context);
    _tour?.selectTab = _selectTab;
  }

  @override
  void dispose() {
    if (_tour?.selectTab == _selectTab) _tour?.selectTab = null;
    super.dispose();
  }

  void _selectTab(int i) {
    if (mounted) setState(() => _tab = i);
  }

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
        bottomNavigationBar: _TabBar(index: _tab, onChanged: _selectTab),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _TabBar({required this.index, required this.onChanged});

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.bookmark_border_rounded, Icons.bookmark_rounded, 'Saved'),
    (Icons.compare_arrows_rounded, Icons.compare_arrows_rounded, 'Compare'),
    (Icons.tune_rounded, Icons.tune_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 4,
        top: 8,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < _items.length; i++)
            TourTarget(
              id: 'tab.$i',
              child: Semantics(
                button: true,
                selected: i == index,
                label: _items[i].$3,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (i != index) HapticFeedback.selectionClick();
                    onChanged(i);
                  },
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 56,
                          height: 30,
                          decoration: BoxDecoration(
                            color: i == index
                                ? c.accentSoft
                                : Colors.transparent,
                            borderRadius: R.pill,
                          ),
                          child: Icon(
                            i == index ? _items[i].$2 : _items[i].$1,
                            size: 22,
                            color: i == index ? c.accent : c.inkMute,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _items[i].$3,
                          style: T.bodySm.copyWith(
                            fontSize: 12,
                            color: i == index ? c.accent : c.inkMute,
                            fontWeight: i == index
                                ? FontWeight.w600
                                : FontWeight.w500,
                            fontVariations: [
                              FontVariation('wght', i == index ? 600 : 500),
                            ],
                          ),
                        ),
                      ],
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
// Home — the question hub
// ---------------------------------------------------------------------------

class HomeTab extends StatefulWidget {
  final AppState app;
  const HomeTab({super.key, required this.app});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Every word typed must appear somewhere: the name, the description, the
  /// question group, or the everyday words people use for it.
  List<Calculator> _matches() {
    final words = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];
    return allCalculators.where((calc) {
      final haystack = [
        calc.name,
        calc.description,
        calc.question.label,
        calculatorKeywords[calc.id] ?? '',
      ].join(' ').toLowerCase();
      return words.every(haystack.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = widget.app;
    final recent = app.scenarios.take(2).toList();
    final searching = _query.trim().isNotEmpty;
    final matches = _matches();
    final tour = TourScope.maybeOf(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.margin, S.md, S.margin, S.xl),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Row(
          children: [
            const _BrandTile(),
            const SizedBox(width: S.sm),
            Expanded(
              child: Text(
                'Basis',
                style: T.title.copyWith(color: c.ink, fontSize: 20),
              ),
            ),
            if (tour != null)
              IconButton(
                tooltip: 'Show me around',
                onPressed: tour.start,
                icon: Icon(Icons.help_outline_rounded, color: c.inkMute),
              ),
          ],
        ),
        const SizedBox(height: S.lg),
        Text(
          greetingFor(DateTime.now()),
          style: T.body.copyWith(color: c.inkMute),
        ),
        const SizedBox(height: 2),
        Text(
          'What are you working out today?',
          style: T.display.copyWith(color: c.ink, fontSize: 28, height: 1.15),
        ),
        const SizedBox(height: S.lg),
        _SearchField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          onClear: () {
            _search.clear();
            setState(() => _query = '');
          },
        ),
        const SizedBox(height: S.lg),
        if (searching) ...[
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.xl),
              child: Column(
                children: [
                  Icon(Icons.search_off_rounded, size: 36, color: c.inkMute),
                  const SizedBox(height: S.md),
                  Text(
                    'No calculator matches "${_query.trim()}"',
                    style: T.body.copyWith(color: c.ink),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: S.xs),
                  Text(
                    'Try a word like loan, CPF, tax or savings.',
                    style: T.bodySm.copyWith(color: c.inkMute),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else ...[
            Text(
              '${matches.length} ${matches.length == 1 ? "calculator" : "calculators"}',
              style: T.bodySm.copyWith(color: c.inkMute),
            ),
            const SizedBox(height: S.sm),
            for (final calc in matches)
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: ToolTile(calculator: calc, app: app),
              ),
          ],
        ] else ...[
          TourTarget(
            id: 'home.questions',
            child: Column(
              children: [
                for (final q in Question.values)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: q == Question.values.last ? 0 : S.md,
                    ),
                    child: _QuestionCard(
                      question: q,
                      count: builtCountFor(q),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CategoryScreen(question: q, app: app),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (recent.isNotEmpty) ...[
            const SectionLabel('Recent'),
            TourTarget(
              id: 'home.recent',
              child: SizedBox(
                height: 118,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: recent.length,
                  separatorBuilder: (_, _) => const SizedBox(width: S.md),
                  itemBuilder: (_, i) =>
                      _RecentCard(scenario: recent[i], app: app),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: T.body.copyWith(color: c.ink),
      cursorColor: c.accent,
      decoration: InputDecoration(
        hintText: 'Search calculators, e.g. loan, CPF, tax',
        hintStyle: T.body.copyWith(color: c.inkMute),
        prefixIcon: Icon(Icons.search_rounded, color: c.inkMute),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                onPressed: onClear,
                icon: Icon(Icons.close_rounded, color: c.inkMute, size: 20),
              ),
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: R.pill,
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: R.pill,
          borderSide: BorderSide(color: c.accent, width: 1.6),
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final Question question;
  final int count;
  final VoidCallback onTap;

  const _QuestionCard({
    required this.question,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hue = questionHue(context, question);
    return Semantics(
      button: true,
      label: '${question.label}, $count ${count == 1 ? "tool" : "tools"}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: BasisCard(
          padding: const EdgeInsets.all(S.lg - 2),
          child: Row(
            children: [
              IconTile(icon: questionIcons[question]!, hue: hue, size: 48),
              const SizedBox(width: S.md + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question.label,
                      style: T.title.copyWith(color: c.ink, fontSize: 17),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      question.blurb,
                      style: T.bodySm.copyWith(color: c.inkMute),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: S.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hue.tile,
                  borderRadius: R.pill,
                ),
                child: Text(
                  '$count',
                  style: T.figureSm.copyWith(color: hue.ink),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 22, color: c.inkMute),
            ],
          ),
        ),
      ),
    );
  }
}

/// One calculator in a list: icon, name, what it does.
class ToolTile extends StatelessWidget {
  final Calculator calculator;
  final AppState app;
  const ToolTile({super.key, required this.calculator, required this.app});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = calculator;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CalculatorScreen(calculator: t, app: app),
        ),
      ),
      child: BasisCard(
        padding: const EdgeInsets.all(S.md + 2),
        child: Row(
          children: [
            IconTile(
              icon: calculatorIcon(t),
              hue: questionHue(context, t.question),
              size: 42,
            ),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        t.name,
                        style: T.body.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                          fontVariations: const [FontVariation('wght', 600)],
                        ),
                      ),
                      if (t.sgSpecific) const _SgChip(),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.description,
                    style: T.bodySm.copyWith(color: c.inkMute),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: S.xs),
            Icon(Icons.chevron_right_rounded, size: 22, color: c.inkMute),
          ],
        ),
      ),
    );
  }
}

class _SgChip extends StatelessWidget {
  const _SgChip();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: 'Uses Singapore rules',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: c.accentSoft, borderRadius: R.pill),
        child: Text(
          'SG',
          style: T.label.copyWith(color: c.accent, fontSize: 10),
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
                  scenario.name,
                  style: T.bodySm.copyWith(color: c.inkMute),
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
    final hue = questionHue(context, question);

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.ground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: c.ink),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.margin, 0, S.margin, S.xl),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconTile(icon: questionIcons[question]!, hue: hue, size: 52),
          ),
          const SizedBox(height: S.md),
          Text(
            question.label,
            style: T.display.copyWith(color: c.ink, fontSize: 30, height: 1.15),
          ),
          const SizedBox(height: S.xs),
          Text(
            tools.isEmpty
                ? 'Not built yet.'
                : '${question.blurb}. ${tools.length} ${tools.length == 1 ? "calculator" : "calculators"}.',
            style: T.body.copyWith(color: c.inkMute),
          ),
          const SizedBox(height: S.xl),
          for (final t in tools)
            Padding(
              padding: const EdgeInsets.only(bottom: S.md),
              child: ToolTile(calculator: t, app: app),
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
      padding: const EdgeInsets.fromLTRB(S.margin, S.md, S.margin, S.xl),
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
        const SizedBox(height: S.xs),
        Text(
          'Tap Compare on two or three to see them side by side. '
          'Swipe left to delete.',
          style: T.bodySm.copyWith(color: c.inkMute),
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
            border: Border.all(
              color: selected ? c.accent : c.line,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: softShadow(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (calc != null) ...[
                    IconTile(
                      icon: calculatorIcon(calc),
                      hue: questionHue(context, calc.question),
                      size: 30,
                    ),
                    const SizedBox(width: S.sm),
                  ],
                  Expanded(
                    child: Text(
                      calc?.name ?? scenario.calculatorId,
                      style: T.bodySm.copyWith(color: c.inkMute),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isExample)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
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
              const SizedBox(height: S.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      scenario.name,
                      style: T.body.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w600,
                        fontVariations: const [FontVariation('wght', 600)],
                      ),
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(width: S.sm),
                  Text(
                    scenario.headlineValue,
                    style: T.figure.copyWith(
                      color: isExample ? c.ink.withValues(alpha: 0.55) : c.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      scenario.relativeTime,
                      style: T.bodySm.copyWith(color: c.inkMute),
                    ),
                  ),
                  _SmallPill(
                    label: selected ? 'In compare' : 'Compare',
                    icon: selected ? Icons.check_rounded : Icons.add_rounded,
                    active: selected,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      app.toggleCompare(scenario.id);
                    },
                  ),
                  if (calc != null) ...[
                    const SizedBox(width: S.sm),
                    _SmallPill(
                      label: 'Open',
                      icon: Icons.arrow_forward_rounded,
                      filled: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CalculatorScreen(
                            calculator: calc,
                            app: app,
                            scenario: scenario,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool filled;
  const _SmallPill({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = filled
        ? (context.isDark ? c.ground : Colors.white)
        : (active ? c.accent : c.ink);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: filled ? c.accent : (active ? c.accentSoft : c.surface),
            borderRadius: R.pill,
            border: filled
                ? null
                : Border.all(color: active ? c.accent : c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 4),
              Text(
                label,
                style: T.bodySm.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontVariations: const [FontVariation('wght', 600)],
                ),
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

    // Settings is short, so it is built all at once rather than lazily: the
    // tour's last step points at the feedback section near the bottom, which
    // a lazy list would not have created yet.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(S.margin, S.sm, S.margin, S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
            padding: const EdgeInsets.all(S.md + 2),
            decoration: BoxDecoration(
              borderRadius: R.input,
              color: c.warn.withValues(alpha: context.isDark ? 0.14 : 0.08),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: c.warn),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Text(
                    'Rules last verified ${r.verifiedOn.day} '
                    '${monthYear(r.verifiedOn)} (${r.daysSinceVerified} ${r.daysSinceVerified == 1 ? "day" : "days"} ago). '
                    'Check MAS, IRAS and the CPF Board before relying on these.',
                    style: T.bodySm.copyWith(color: c.ink, height: 1.45),
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
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
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
                          '${m.name[0].toUpperCase()}${m.name.substring(1)}',
                          style: T.bodySm.copyWith(
                            color: app.themeMode == m ? c.accent : c.ink,
                            fontWeight: app.themeMode == m
                                ? FontWeight.w600
                                : FontWeight.w500,
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
            'Basis works to the exact cent and never guesses. If a figure '
            'cannot be worked out from what you entered, it tells you why '
            'instead of showing a number that only looks right.',
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
          TourTarget(
            id: 'settings.help',
            child: Column(
              children: [
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
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 17,
                          color: c.accent,
                        ),
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
                if (TourScope.maybeOf(context) != null) ...[
                  const SizedBox(height: S.sm),
                  GestureDetector(
                    onTap: () => TourScope.maybeOf(context)?.start(),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: R.input,
                        border: Border.all(color: c.line),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.explore_outlined, size: 17, color: c.ink),
                          const SizedBox(width: S.sm),
                          Text(
                            'Replay the app tour',
                            style: T.body.copyWith(
                              color: c.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
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
      ),
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
                child: Row(
                  children: [
                    Flexible(
                      child: Text(label, style: T.body.copyWith(color: c.ink)),
                    ),
                    if (glossaryFor(label) case final term?) InfoButton(term),
                  ],
                ),
              ),
              const SizedBox(width: S.sm),
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
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: c.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: c.accent),
            ),
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

/// The app-icon mark: a green rounded square with a "B".
class _BrandTile extends StatelessWidget {
  const _BrandTile();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        'B',
        style: T.title.copyWith(
          fontSize: 17,
          height: 1,
          color: context.isDark ? c.ground : Colors.white,
          fontWeight: FontWeight.w700,
          fontVariations: const [FontVariation('wght', 700)],
        ),
      ),
    );
  }
}

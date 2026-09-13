import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calculators/registry.dart';
import '../prefs.dart';
import '../state.dart';
import 'screens/calculator_screen.dart';
import 'theme.dart';

/// First-run tour: dims the app, spotlights one real element at a time, and
/// explains it in a small card with Back / Next / Skip.
///
/// It walks the whole app — Home, a calculator, Saved, Compare and Settings —
/// by switching tabs and opening a calculator itself, so every tip points at
/// the thing it describes rather than at a screenshot of it.
///
/// Elements opt in with [TourTarget]. A target that is not on screen does not
/// break the tour: its card is shown centred instead.

enum TourPlace { home, calculator, saved, compare, settings }

@immutable
class TourStep {
  final TourPlace place;
  final String? target;
  final String title;
  final String body;

  const TourStep({
    required this.place,
    required this.title,
    required this.body,
    this.target,
  });
}

/// Calculator the tour opens to demonstrate results, inputs and the math.
const String kTourCalculatorId = 'mortgage';

const List<TourStep> kTourSteps = [
  TourStep(
    place: TourPlace.home,
    title: 'Welcome to Basis',
    body:
        'Singapore money questions, answered with the working shown. '
        'This quick tour takes about a minute.',
  ),
  TourStep(
    place: TourPlace.home,
    target: 'home.questions',
    title: 'Start with your question',
    body:
        'Calculators are grouped by what you want to know, not by formula '
        'name. Tap a group to see its tools.',
  ),
  TourStep(
    place: TourPlace.home,
    target: 'home.recent',
    title: 'Pick up where you left off',
    body: 'Recent scenarios sit here. Tap one to reopen it with its numbers.',
  ),
  TourStep(
    place: TourPlace.calculator,
    target: 'calc.result',
    title: 'The answer comes first',
    body:
        'The headline figure, with supporting numbers beneath. EXAMPLE means '
        'these are sample figures, not yours.',
  ),
  TourStep(
    place: TourPlace.calculator,
    target: 'calc.inputs',
    title: 'Type your own numbers',
    body:
        'Tap any figure to replace it. The result updates as you type, and '
        'the badge changes to LIVE.',
  ),
  TourStep(
    place: TourPlace.calculator,
    target: 'calc.math',
    title: 'Every figure shows its working',
    body:
        'Show the math lists the formula, the numbers used and each '
        'assumption, so you can check it yourself.',
  ),
  TourStep(
    place: TourPlace.calculator,
    target: 'calc.savebar',
    title: 'Save or export',
    body:
        'Save a scenario to come back to it later, or export the figures as '
        'a spreadsheet file.',
  ),
  TourStep(
    place: TourPlace.saved,
    target: 'tab.1',
    title: 'Your saved scenarios',
    body:
        'Everything you save lives here, on this device. Tap Compare on two '
        'or three to line them up.',
  ),
  TourStep(
    place: TourPlace.compare,
    target: 'tab.2',
    title: 'Compare side by side',
    body:
        'Scenarios are recalculated with the current rules. When they come '
        'from the same calculator, the better figure in each row is marked.',
  ),
  TourStep(
    place: TourPlace.settings,
    target: 'settings.help',
    title: 'Spot something wrong?',
    body:
        'Send feedback from here. You can also replay this tour any time '
        'from Settings.',
  ),
];

// ---------------------------------------------------------------------------
// Remembering that the tour was seen
// ---------------------------------------------------------------------------

abstract class TourMemory {
  Future<bool> hasSeen();
  Future<void> markSeen();
}

class InMemoryTourMemory implements TourMemory {
  InMemoryTourMemory({this.seen = false});
  bool seen;

  @override
  Future<bool> hasSeen() async => seen;

  @override
  Future<void> markSeen() async => seen = true;
}

class PrefsTourMemory implements TourMemory {
  PrefsTourMemory(this.prefs);
  final PrefsStore prefs;

  /// Bump the version when the tour changes enough to be worth re-showing.
  static const key = 'tour.v1.seen';

  @override
  Future<bool> hasSeen() async => (await prefs.read(key)) == 'true';

  @override
  Future<void> markSeen() => prefs.write(key, 'true');
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class TourController extends ChangeNotifier {
  TourController({
    required this.app,
    required this.navigatorKey,
    required this.memory,
    this.steps = kTourSteps,
  });

  final AppState app;
  final GlobalKey<NavigatorState> navigatorKey;
  final TourMemory memory;
  final List<TourStep> steps;

  /// Registered by the Shell so the tour can switch tabs.
  ValueChanged<int>? selectTab;

  final Map<String, BuildContext> _targets = {};
  Route<void>? _calculatorRoute;

  bool _active = false;
  bool _moving = false;
  int _index = 0;
  Rect? _rect;
  int _generation = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get isActive => _active;

  /// True while the tour is navigating or scrolling to the next target.
  bool get isMoving => _moving;
  int get index => _index;
  TourStep get step => steps[_index];
  bool get isFirst => _index == 0;
  bool get isLast => _index == steps.length - 1;

  /// Where the current target is on screen, or null to centre the card.
  Rect? get targetRect => _rect;

  void register(String id, BuildContext context) => _targets[id] = context;

  void unregister(String id, BuildContext context) {
    if (identical(_targets[id], context)) _targets.remove(id);
  }

  Future<void> startIfFirstRun() async {
    if (_active || await memory.hasSeen()) return;
    await start();
  }

  Future<void> start() async {
    _active = true;
    await _show(0);
  }

  Future<void> next() async {
    if (!_active || _moving) return;
    if (isLast) return finish();
    await _show(_index + 1);
  }

  Future<void> back() async {
    if (!_active || _moving || isFirst) return;
    await _show(_index - 1);
  }

  /// Ends the tour, from Done or Skip, and remembers it was seen.
  Future<void> finish() async {
    if (!_active) return;
    _generation++;
    _active = false;
    _moving = false;
    _rect = null;
    _notify();
    await memory.markSeen();
  }

  /// Re-measure after the screen size changes, e.g. on rotation.
  void remeasure() {
    if (_disposed || !_active || _moving) return;
    _rect = _measure(step.target);
    _notify();
  }

  Future<void> _show(int i) async {
    final generation = ++_generation;
    _index = i;
    _moving = true;
    _notify();

    await _goTo(steps[i].place);
    if (_disposed || generation != _generation || !_active) return;
    await _reveal(steps[i].target);
    if (_disposed || generation != _generation || !_active) return;

    _moving = false;
    _notify();
  }

  Future<void> _goTo(TourPlace place) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    if (place == TourPlace.calculator) {
      if (_calculatorRoute?.isActive ?? false) return;
      final calc = calculatorById(kTourCalculatorId);
      if (calc == null) return;
      nav.popUntil((r) => r.isFirst);
      selectTab?.call(0);
      final route = MaterialPageRoute<void>(
        // The app's navigator hears the back button before the tour does, so
        // this route hands it to the tour while the tour is running instead
        // of closing the screen the current step is pointing at.
        builder: (_) => ListenableBuilder(
          listenable: this,
          builder: (context, child) => PopScope(
            canPop: !_active,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _active) back();
            },
            child: child!,
          ),
          child: CalculatorScreen(calculator: calc, app: app),
        ),
      );
      _calculatorRoute = route;
      unawaited(nav.push(route));
      await _settle(const Duration(milliseconds: 450));
      return;
    }

    final moved = nav.canPop();
    if (moved) nav.popUntil((r) => r.isFirst);
    _calculatorRoute = null;
    selectTab?.call(switch (place) {
      TourPlace.saved => 1,
      TourPlace.compare => 2,
      TourPlace.settings => 3,
      _ => 0,
    });
    await _settle(Duration(milliseconds: moved ? 450 : 60));
  }

  Future<void> _reveal(String? id) async {
    final context = id == null ? null : _targets[id];
    if (context == null || !context.mounted) {
      _rect = null;
      return;
    }
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    await Scrollable.ensureVisible(
      context,
      alignment: 0.2,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
    await _settle(const Duration(milliseconds: 40));
    _rect = _measure(id);
  }

  Rect? _measure(String? id) {
    final context = id == null ? null : _targets[id];
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _settle(Duration d) async {
    await Future<void>.delayed(d);
    await WidgetsBinding.instance.endOfFrame;
  }
}

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

/// Makes the tour reachable from any screen, including pushed routes.
class TourScope extends InheritedNotifier<TourController> {
  const TourScope({
    super.key,
    required TourController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Null outside the app (for example in widget tests of a single screen),
  /// in which case targets and the replay button simply do nothing.
  static TourController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TourScope>()?.notifier;
}

/// Marks a widget the tour can spotlight.
class TourTarget extends StatefulWidget {
  final String id;
  final Widget child;
  const TourTarget({super.key, required this.id, required this.child});

  @override
  State<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends State<TourTarget> {
  TourController? _tour;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tour = TourScope.maybeOf(context);
    if (!identical(tour, _tour)) {
      _tour?.unregister(widget.id, context);
      _tour = tour;
    }
    _tour?.register(widget.id, context);
  }

  @override
  void didUpdateWidget(TourTarget old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _tour?.unregister(old.id, context);
      _tour?.register(widget.id, context);
    }
  }

  @override
  void dispose() {
    _tour?.unregister(widget.id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------------------------------------------------------------------
// Overlay
// ---------------------------------------------------------------------------

class TourOverlay extends StatefulWidget {
  final TourController controller;
  const TourOverlay({super.key, required this.controller});

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> with WidgetsBindingObserver {
  final _focus = FocusNode(debugLabel: 'tour');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    if (widget.controller.isActive && !_focus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.controller.isActive) _focus.requestFocus();
      });
    }
  }

  /// The system back button (or browser back) steps the tour back instead of
  /// closing the screen underneath it.
  @override
  Future<bool> didPopRoute() async {
    final t = widget.controller;
    if (!t.isActive) return false;
    if (t.isFirst) {
      await t.finish();
    } else {
      await t.back();
    }
    return true;
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.remeasure();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final t = widget.controller;
        if (!t.isActive) return const IgnorePointer(child: SizedBox.shrink());

        final c = context.c;
        final media = MediaQuery.of(context);
        final reduceMotion = media.disableAnimations;

        // The overlay sits above the Navigator, outside any screen's
        // Material, so it supplies its own; without it text renders with the
        // yellow "no Material" underline.
        return Material(
          type: MaterialType.transparency,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowRight): t.next,
              const SingleActivator(LogicalKeyboardKey.enter): t.next,
              const SingleActivator(LogicalKeyboardKey.arrowLeft): t.back,
              const SingleActivator(LogicalKeyboardKey.escape): t.finish,
            },
            child: Focus(
              focusNode: _focus,
              autofocus: true,
              child: BlockSemantics(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final size = box.biggest;
                    // No target: a zero-size hole at the centre, so the
                    // spotlight shrinks away instead of the tween having no end.
                    final hole =
                        t.targetRect?.inflate(6) ??
                        Rect.fromCenter(
                          center: size.center(Offset.zero),
                          width: 0,
                          height: 0,
                        );
                    return Stack(
                      children: [
                        // Swallows taps so nothing underneath changes mid-tour.
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {},
                            child: TweenAnimationBuilder<Rect?>(
                              tween: RectTween(begin: hole, end: hole),
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              builder: (context, rect, _) => CustomPaint(
                                size: size,
                                painter: _SpotlightPainter(
                                  hole: rect,
                                  dim: Colors.black.withValues(
                                    alpha: context.isDark ? 0.72 : 0.6,
                                  ),
                                  ring: c.accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _positionedCard(context, t, size, media, reduceMotion),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _positionedCard(
    BuildContext context,
    TourController t,
    Size size,
    MediaQueryData media,
    bool reduceMotion,
  ) {
    const gap = 14.0;
    const estimate = 210.0;
    final width = (size.width - 32).clamp(0.0, 380.0);
    final left = (size.width - width) / 2;
    final top = media.padding.top + 12;
    final bottom = media.padding.bottom + 16;
    final rect = t.targetRect;

    final card = AnimatedOpacity(
      opacity: t.isMoving ? 0.0 : 1.0,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 160),
      child: IgnorePointer(
        ignoring: t.isMoving,
        child: _TourCard(controller: t, width: width),
      ),
    );

    if (rect == null) {
      return Positioned(
        left: left,
        width: width,
        top: 0,
        bottom: 0,
        child: Center(child: card),
      );
    }
    final spaceBelow = size.height - rect.bottom - bottom;
    final spaceAbove = rect.top - top;
    if (spaceBelow >= estimate + gap) {
      return Positioned(
        left: left,
        width: width,
        top: rect.bottom + gap,
        child: card,
      );
    }
    if (spaceAbove >= estimate + gap) {
      return Positioned(
        left: left,
        width: width,
        bottom: size.height - rect.top + gap,
        child: card,
      );
    }
    // A tall target: sit the card at the bottom edge, over the target.
    return Positioned(left: left, width: width, bottom: bottom, child: card);
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  final Color dim;
  final Color ring;
  const _SpotlightPainter({
    required this.hole,
    required this.dim,
    required this.ring,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    final path = Path()..addRect(screen);
    RRect? cut;
    if (hole != null && hole!.width >= 1 && hole!.height >= 1) {
      cut = RRect.fromRectAndRadius(
        hole!.intersect(screen),
        const Radius.circular(14),
      );
      path
        ..addRRect(cut)
        ..fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, Paint()..color = dim);
    if (cut != null) {
      canvas.drawRRect(
        cut,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.dim != dim || old.ring != ring;
}

class _TourCard extends StatelessWidget {
  final TourController controller;
  final double width;
  const _TourCard({required this.controller, required this.width});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = controller;
    final step = t.step;
    final total = t.steps.length;

    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Tour step ${t.index + 1} of $total',
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          color: c.ground,
          borderRadius: R.card,
          border: Border.all(color: c.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'STEP ${t.index + 1} OF $total',
                  style: T.label.copyWith(color: c.inkMute, fontSize: 10),
                ),
                const Spacer(),
                for (var i = 0; i < total; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(left: 4),
                    width: i == t.index ? 14 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: i <= t.index ? c.accent : c.line,
                      borderRadius: R.pill,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: S.md),
            Text(step.title, style: T.title.copyWith(color: c.ink)),
            const SizedBox(height: S.sm),
            Text(step.body, style: T.body.copyWith(color: c.inkMute)),
            const SizedBox(height: S.lg),
            Row(
              children: [
                if (!t.isLast)
                  _TourButton(label: 'Skip', kind: _Kind.text, onTap: t.finish),
                const Spacer(),
                if (!t.isFirst) ...[
                  _TourButton(
                    label: 'Back',
                    kind: _Kind.outline,
                    onTap: t.back,
                  ),
                  const SizedBox(width: S.sm),
                ],
                _TourButton(
                  label: t.isLast ? 'Done' : (t.isFirst ? 'Show me' : 'Next'),
                  kind: _Kind.filled,
                  onTap: t.next,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _Kind { text, outline, filled }

class _TourButton extends StatelessWidget {
  final String label;
  final _Kind kind;
  final VoidCallback onTap;
  const _TourButton({
    required this.label,
    required this.kind,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          constraints: const BoxConstraints(minWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kind == _Kind.filled ? c.accent : null,
            borderRadius: R.input,
            border: kind == _Kind.outline ? Border.all(color: c.line) : null,
          ),
          child: Text(
            label,
            style: T.body.copyWith(
              fontWeight: FontWeight.w600,
              color: switch (kind) {
                _Kind.filled => c.ground,
                _Kind.outline => c.ink,
                _Kind.text => c.inkMute,
              },
            ),
          ),
        ),
      ),
    );
  }
}

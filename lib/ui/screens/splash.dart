import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// The mark: a ledger with one highlighted row and an endpoint dot — the same
/// dot that terminates every SeriesChart in the app.
class BasisMark extends StatelessWidget {
  final double size;
  final Color? tile;
  final Color? bar;
  final Color? accent;

  const BasisMark({
    super.key,
    this.size = 76,
    this.tile,
    this.bar,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CustomPaint(
      size: Size(size, size),
      painter: _MarkPainter(
        tile: tile ?? c.surface,
        line: c.line,
        bar: bar ?? c.ink,
        accent: accent ?? c.accent,
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color tile, line, bar, accent;
  _MarkPainter({
    required this.tile,
    required this.line,
    required this.bar,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 72;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5 * s, 0.5 * s, 71 * s, 71 * s),
      Radius.circular(17.5 * s),
    );
    canvas.drawRRect(rect, Paint()..color = tile);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    void drawBar(double y, double w, Color col) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(16 * s, y * s, w * s, 5 * s),
          Radius.circular(2.5 * s),
        ),
        Paint()..color = col,
      );
    }

    drawBar(21, 40, bar);
    drawBar(33, 40, bar);
    drawBar(45, 26, accent);
    canvas.drawCircle(
      Offset(52.5 * s, 47.5 * s),
      3.5 * s,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter o) =>
      o.tile != tile || o.bar != bar || o.accent != accent;
}

/// Splash. No spinner — the design system forbids celebratory animation, so
/// the loader is the ledger's third row filling, with the endpoint dot riding
/// the end of it.
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  Timer? _timer;
  bool _done = false;
  String _status = 'Loading ruleset';

  static const _width = 212.0;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _ctl.addListener(() {
      final v = _ctl.value;
      final next = v < 0.3
          ? 'Loading ruleset'
          : v < 0.65
          ? 'Rates · 3 Sep 2026'
          : v < 0.99
          ? '8 calculators ready'
          : 'Ready';
      if (next != _status) setState(() => _status = next);
    });
    _ctl.forward();

    // The hand-off runs on a timer, never on animation completion. A ticker
    // can be throttled (backgrounded tab, reduced-motion, a stalled frame)
    // and if the transition hung off it the user would be stranded on the
    // splash forever. The animation is decorative; this is what advances.
    _timer = Timer(const Duration(milliseconds: 1660), _finish);
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.ground,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: Stack(
          children: [
            // Faint ledger rules — a printed plate behind the mark.
            Positioned.fill(child: CustomPaint(painter: _RulesPainter(c.line))),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BasisMark(size: 76),
                  const SizedBox(height: S.xl),
                  Text('Basis', style: T.display.copyWith(color: c.ink)),
                  const SizedBox(height: S.sm),
                  Text(
                    'FINANCIAL CALCULATORS · SINGAPORE',
                    style: T.label.copyWith(color: c.inkMute),
                  ),
                  const SizedBox(height: 40),
                  AnimatedBuilder(
                    animation: _ctl,
                    builder: (_, _) => SizedBox(
                      width: _width,
                      height: 7,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: 3,
                            child: Container(
                              width: _width,
                              height: 1,
                              color: c.line,
                            ),
                          ),
                          Positioned(
                            top: 3,
                            child: Container(
                              width: _width * _ctl.value,
                              height: 1,
                              color: c.accent,
                            ),
                          ),
                          Positioned(
                            left: _width * _ctl.value - 3,
                            top: 0,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: c.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: S.lg),
                  Text(_status, style: T.figureSm.copyWith(color: c.inkMute)),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: Column(
                children: [
                  Text(
                    'SG RULESET · REV 2026.09',
                    style: T.figureSm.copyWith(color: c.inkMute),
                  ),
                  const SizedBox(height: S.xs),
                  Text(
                    'Verified 3 Sep 2026 · MAS · IRAS · CPF',
                    style: T.figureSm.copyWith(
                      color: c.inkMute.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RulesPainter extends CustomPainter {
  final Color color;
  _RulesPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var y = 52.0; y < size.height; y += 52) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_RulesPainter o) => o.color != color;
}

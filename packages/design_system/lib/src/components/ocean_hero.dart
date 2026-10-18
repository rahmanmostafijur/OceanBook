import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/app_motion.dart';
import '../tokens/app_shapes.dart';
import '../tokens/app_spacing.dart';

/// Gradient behind the hero text. Light theme deepens `primary` toward the scrim; in the dark theme
/// `primary` is light and `onPrimary` dark, so the gradient must not darken toward the scrim there, or
/// the text would lose contrast at the start of the gradient.
List<Color> oceanHeroGradient(ColorScheme scheme) {
  if (scheme.brightness == Brightness.dark) {
    return [scheme.primary, Color.lerp(scheme.primary, scheme.onPrimary, 0.2)!];
  }
  return [Color.lerp(scheme.primary, scheme.scrim, 0.45)!, scheme.primary];
}

/// The landing hero: a deep-ocean gradient with slow layered waves, drifting bubbles and a warm coral
/// glow in one corner. It is the app's 30 % (teal) surface with a touch of the 10 % accent.
///
/// Everything painted is decorative and excluded from semantics. The waves stand still when the user
/// has reduced motion on. Content sits on [oceanHeroGradient], so [ColorScheme.onPrimary] text keeps at
/// least 4.5:1 contrast over the whole gradient in both themes.
class OceanHero extends StatefulWidget {
  const OceanHero({required this.child, this.minHeight = 300, this.bottomInset = AppSpacing.huge, super.key});

  final Widget child;
  final double minHeight;

  /// Extra space under the content, for an element that overlaps the hero's lower edge.
  final double bottomInset;

  @override
  State<OceanHero> createState() => _OceanHeroState();
}

class _OceanHeroState extends State<OceanHero> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _controller
        ..stop()
        ..value = 0.25;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // System bar icons follow the hero's tone: light icons on the dark ocean, dark ones on the light one.
    final overlay = ThemeData.estimateBrightnessForColor(oceanHeroGradient(scheme).first) == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(statusBarColor: Colors.transparent),
      child: _hero(scheme),
    );
  }

  Widget _hero(ColorScheme scheme) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppShapes.extraLarge + 12)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: oceanHeroGradient(scheme),
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      painter: _OceanPainter(
                        phase: _controller.value,
                        foam: scheme.onPrimary,
                        glow: scheme.tertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: widget.minHeight),
              child: Padding(
                padding: EdgeInsets.only(bottom: widget.bottomInset),
                child: SafeArea(bottom: false, child: widget.child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OceanPainter extends CustomPainter {
  _OceanPainter({required this.phase, required this.foam, required this.glow});

  final double phase;
  final Color foam;
  final Color glow;

  static const _bubbles = <(double, double, double)>[
    (0.12, 0.30, 7),
    (0.30, 0.18, 4),
    (0.58, 0.28, 9),
    (0.82, 0.22, 5),
    (0.70, 0.46, 3),
    (0.20, 0.52, 5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // The accent: one warm glow, like low sun on the water, in the top-right corner.
    final center = Offset(size.width * 0.88, size.height * 0.08);
    canvas.drawCircle(
      center,
      size.width * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [glow.withValues(alpha: 0.55), glow.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.55)),
    );

    for (final (x, y, r) in _bubbles) {
      final drift = math.sin((phase + x) * math.pi * 2) * 6;
      canvas.drawCircle(
        Offset(size.width * x, size.height * y + drift),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = foam.withValues(alpha: 0.28),
      );
    }

    _wave(canvas, size, base: 0.72, amplitude: 14, cycles: 1.4, offset: phase, alpha: 0.07);
    _wave(canvas, size, base: 0.80, amplitude: 11, cycles: 1.9, offset: -phase * 1.3 + 0.3, alpha: 0.09);
    _wave(canvas, size, base: 0.88, amplitude: 9, cycles: 2.6, offset: phase * 1.7 + 0.6, alpha: 0.12);
  }

  void _wave(
    Canvas canvas,
    Size size, {
    required double base,
    required double amplitude,
    required double cycles,
    required double offset,
    required double alpha,
  }) {
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width; x += 4) {
      final t = x / size.width * cycles + offset;
      path.lineTo(x, size.height * base + math.sin(t * math.pi * 2) * amplitude);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = foam.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(_OceanPainter old) => old.phase != phase || old.foam != foam || old.glow != glow;
}

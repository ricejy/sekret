import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

abstract final class SekretBrand {
  static const background = Color(0xFF101B21);
  static const surface = Color(0xFF1B2A31);
  static const accent = Color(0xFF72DECD);
  static const foreground = Color(0xFFF1F6F5);
  static const secondary = Color(0xFFB0C2C6);
  static const line = Color(0xFF31454D);

  static const theme = CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: accent,
    primaryContrastingColor: background,
    scaffoldBackgroundColor: background,
    barBackgroundColor: background,
    textTheme: CupertinoTextThemeData(
      primaryColor: accent,
      textStyle: TextStyle(
        inherit: false,
        fontFamily: 'CupertinoSystemText',
        fontSize: 17,
        letterSpacing: -0.41,
        color: foreground,
        decoration: TextDecoration.none,
      ),
    ),
  );
}

/// Decorative brand art; nearby headings carry the screen's accessible meaning.
class TuckMascot extends StatelessWidget {
  const TuckMascot({super.key, this.size = 144});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/tuck.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );
}

/// Launch animation: Tuck hops and waddles in place while the ground scrolls
/// past. Still under Reduce Motion. Announces [label] once.
class TuckRunning extends StatefulWidget {
  const TuckRunning({
    super.key,
    this.size = 120,
    this.label = 'Opening Sekret',
  });
  final double size;
  final String label;

  @override
  State<TuckRunning> createState() => _TuckRunningState();
}

class _TuckRunningState extends State<TuckRunning>
    with SingleTickerProviderStateMixin {
  // One stride: two hops, one waddle each way.
  late final _stride = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _stride.stop();
      _stride.value = 0;
    } else if (!_stride.isAnimating) {
      _stride.repeat();
    }
  }

  @override
  void dispose() {
    _stride.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final tuck = Image.asset(
      'assets/brand/tuck.png',
      width: size,
      height: size,
      cacheWidth: pixels,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: SizedBox(
        width: size * 1.6,
        height: size * 1.25,
        child: AnimatedBuilder(
          animation: _stride,
          child: tuck,
          builder: (context, tuck) {
            final t = _stride.value;
            final phase = t * 2 * math.pi;
            // Two hops per stride (|sin| peaks twice), one waddle cycle.
            final hop = (math.sin(phase)).abs();
            return Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GroundPainter(t, landing: 1 - hop),
                  ),
                ),
                Positioned(
                  bottom: size * 0.14 + hop * size * 0.10,
                  child: Transform.rotate(
                    angle: math.sin(phase) * 0.07 - 0.05,
                    alignment: Alignment.bottomCenter,
                    child: tuck,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Dashes scroll right-to-left under Tuck; a soft shadow shrinks mid-hop.
class _GroundPainter extends CustomPainter {
  _GroundPainter(this.t, {required this.landing});
  final double t;
  final double landing;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * 0.88;
    final shadow = Paint()..color = SekretBrand.line.withValues(alpha: 0.9);
    final shadowWidth = size.width * (0.30 + 0.08 * landing);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, y),
        width: shadowWidth,
        height: size.height * 0.05,
      ),
      shadow,
    );
    final dash = Paint()
      ..color = SekretBrand.accent.withValues(alpha: 0.55)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final spacing = size.width / 4;
    final offset = t * spacing * 2;
    for (var x = -spacing - offset % spacing; x < size.width; x += spacing) {
      // Fade dashes out toward both edges.
      final edge = (1 - ((x + spacing / 4) / size.width - 0.5).abs() * 2).clamp(
        0.0,
        1.0,
      );
      dash.color = SekretBrand.accent.withValues(alpha: 0.55 * edge);
      canvas.drawLine(
        Offset(x, y + 8),
        Offset(x + spacing * 0.45, y + 8),
        dash,
      );
    }
  }

  @override
  bool shouldRepaint(_GroundPainter old) =>
      old.t != t || old.landing != landing;
}

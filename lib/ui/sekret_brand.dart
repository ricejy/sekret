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

/// Knowledge Vault tab icon: a safe with a dial and handle. Follows the
/// ambient [IconTheme] like a font icon; the tab label carries its meaning.
class VaultIcon extends StatelessWidget {
  const VaultIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _VaultPainter(
            (theme.color ?? CupertinoColors.label).withValues(
              alpha: theme.opacity ?? 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultPainter extends CustomPainter {
  const _VaultPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;
    // Body and inner door.
    final body = Rect.fromLTWH(s * 0.10, s * 0.12, s * 0.80, s * 0.68);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(s * 0.12)),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        body.deflate(s * 0.11),
        Radius.circular(s * 0.05),
      ),
      stroke..strokeWidth = s * 0.05,
    );
    // Dial with a pointer, and the handle on the opening side.
    final dial = Offset(s * 0.44, body.center.dy);
    canvas.drawCircle(dial, s * 0.11, stroke);
    canvas.drawCircle(dial, s * 0.03, fill);
    canvas.drawLine(
      Offset(s * 0.70, body.center.dy - s * 0.10),
      Offset(s * 0.70, body.center.dy + s * 0.10),
      stroke..strokeWidth = s * 0.075,
    );
    // Feet.
    for (final x in [s * 0.24, s * 0.76]) {
      canvas.drawLine(Offset(x, s * 0.84), Offset(x, s * 0.90), stroke);
    }
  }

  @override
  bool shouldRepaint(_VaultPainter old) => old.color != color;
}

/// App-switcher cover: a large Tuck keeping the screen private.
class TuckPrivacy extends StatelessWidget {
  const TuckPrivacy({super.key});

  // Placeholder pose until a dedicated shushing Tuck is supplied.
  static const asset = 'assets/brand/tuck-shell.png';

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: 0.9,
    child: Image.asset(asset, fit: BoxFit.contain, excludeFromSemantics: true),
  );
}

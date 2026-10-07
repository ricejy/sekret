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

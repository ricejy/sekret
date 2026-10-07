import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('all iOS icon sizes are opaque and correctly packaged', () {
    const directory = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final manifest =
        jsonDecode(File('$directory/Contents.json').readAsStringSync())
            as Map<String, dynamic>;
    for (final entry in manifest['images'] as List<dynamic>) {
      final size =
          (double.parse((entry['size'] as String).split('x').first) *
                  double.parse((entry['scale'] as String).replaceAll('x', '')))
              .round();
      final icon = image.decodePng(
        File('$directory/${entry['filename']}').readAsBytesSync(),
      )!;
      expect(icon.width, size);
      expect(icon.height, size);
      expect(icon.hasAlpha, isFalse);
    }
  });

  test(
    'Tuck retains transparency and Windows includes small and large icons',
    () {
      for (final asset in [
        'tuck.png',
        'tuck-curious.png',
        'tuck-ready.png',
        'tuck-shell.png',
      ]) {
        final mascot = image.decodePng(
          File('assets/brand/$asset').readAsBytesSync(),
        )!;
        expect(mascot.hasAlpha, isTrue, reason: asset);
        expect(mascot.getPixel(0, 0).a, 0, reason: asset);
      }
      final icon = image.decodeIco(
        File('windows/runner/resources/app_icon.ico').readAsBytesSync(),
      )!;
      expect(icon.frames.map((frame) => frame.width), [
        16,
        24,
        32,
        48,
        64,
        128,
        256,
      ]);
    },
  );
}

// Packages the approved artwork into platform sizes; does not redesign it.
// Run from the repository root: dart run tool/generate_brand_icons.dart
import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as image;

void main() {
  final icon = image.decodePng(
    File('assets/brand/tuck-app-icon.png').readAsBytesSync(),
  )!;
  final mascot = image.decodePng(
    File('assets/brand/tuck.png').readAsBytesSync(),
  )!;
  for (final pixel in icon) {
    if (pixel.a != pixel.maxChannelValue) {
      throw StateError('The app icon must be fully opaque.');
    }
  }
  // Apple's marketing icon must not contain an alpha channel.
  final opaque = icon.convert(numChannels: 3);
  const appIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final manifest =
      jsonDecode(File('$appIcons/Contents.json').readAsStringSync())
          as Map<String, dynamic>;
  for (final entry in manifest['images'] as List<dynamic>) {
    final pointSize = double.parse((entry['size'] as String).split('x').first);
    final scale = double.parse((entry['scale'] as String).replaceAll('x', ''));
    final pixels = (pointSize * scale).round();
    File('$appIcons/${entry['filename']}').writeAsBytesSync(
      image.encodePng(
        image.copyResize(
          opaque,
          width: pixels,
          height: pixels,
          interpolation: image.Interpolation.average,
        ),
      ),
    );
  }
  const launch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
  for (var scale = 1; scale <= 3; scale++) {
    final suffix = scale == 1 ? '' : '@${scale}x';
    File('$launch/LaunchImage$suffix.png').writeAsBytesSync(
      image.encodePng(
        image.copyResize(
          mascot,
          width: 160 * scale,
          height: 160 * scale,
          interpolation: image.Interpolation.average,
        ),
      ),
    );
  }
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(
    image.IcoEncoder().encodeImages([
      for (final size in [16, 24, 32, 48, 64, 128, 256])
        image.copyResize(
          opaque,
          width: size,
          height: size,
          interpolation: image.Interpolation.average,
        ),
    ]),
  );
}

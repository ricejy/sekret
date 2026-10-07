import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'all iPhone configurations use the canonical app and test identities',
    () {
      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final identifiers = RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
      ).allMatches(project).map((match) => match.group(1)).toList();
      expect(identifiers, hasLength(6));
      expect(
        identifiers.where((id) => id == 'com.ricejy.sekret'),
        hasLength(3),
      );
      expect(
        identifiers.where((id) => id == 'com.ricejy.sekret.RunnerTests'),
        hasLength(3),
      );
    },
  );

  test(
    'both production startup paths open the canonical database filename',
    () {
      for (final path in ['lib/main.dart', 'lib/ui/sekret_chat_app.dart']) {
        expect(File(path).readAsStringSync(), contains('sekret.sqlite3'));
      }
    },
  );
}

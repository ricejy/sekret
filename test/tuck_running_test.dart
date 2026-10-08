import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/ui/sekret_brand.dart';

void main() {
  Widget app({required bool reduceMotion}) => MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: const CupertinoApp(
      home: CupertinoPageScaffold(child: Center(child: TuckRunning())),
    ),
  );

  testWidgets('Tuck runs and announces that Sekret is opening', (tester) async {
    await tester.pumpWidget(app(reduceMotion: false));
    expect(find.bySemanticsLabel('Opening Sekret'), findsOneWidget);
    final start = tester.getTopLeft(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.getTopLeft(find.byType(Image)), isNot(start));
    expect(tester.hasRunningAnimations, true);
  });

  testWidgets('Reduce Motion keeps Tuck still', (tester) async {
    await tester.pumpWidget(app(reduceMotion: true));
    final start = tester.getTopLeft(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.getTopLeft(find.byType(Image)), start);
    expect(tester.hasRunningAnimations, false);
    expect(find.bySemanticsLabel('Opening Sekret'), findsOneWidget);
  });
}

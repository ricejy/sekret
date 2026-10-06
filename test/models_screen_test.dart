import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/platform/llm_backend.dart';
import 'package:sekret/ui/models/models_screen.dart';
import 'package:sekret/ui/sekret_brand.dart';

class _Model implements LlmBackend {
  LlmAvailability status = const Available();
  bool fails = false;
  Completer<LlmAvailability>? pending;

  @override
  Future<LlmAvailability> availability() async {
    if (fails) throw StateError('unavailable');
    if (pending != null) return pending!.future;
    return status;
  }

  @override
  Stream<String> generate({
    required String question,
    required List<String> evidence,
    required String prompt,
  }) => const Stream.empty();
}

void main() {
  Future<void> show(
    WidgetTester tester,
    _Model model, {
    Future<void> Function()? settings,
    double textScale = 1,
  }) => tester.pumpWidget(
    CupertinoApp(
      theme: SekretBrand.theme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: ModelsScreen(
          model: model,
          openSystemSettings: settings ?? () async {},
        ),
      ),
    ),
  );

  testWidgets('reports actual Apple readiness without fake local actions', (
    tester,
  ) async {
    await show(tester, _Model());
    await tester.pumpAndSettle();
    expect(find.text('Ready · On-device Apple Intelligence'), findsOneWidget);
    expect(find.text('Apple Intelligence'), findsOneWidget);
    expect(find.text('Qwen3-4B-Instruct-2507'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Apple Intelligence')).dy,
      lessThan(tester.getTopLeft(find.text('Qwen3-4B-Instruct-2507')).dy),
    );
    expect(find.textContaining('General text chat only'), findsOneWidget);
    expect(find.text('Not available in this version'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
    expect(find.text('Use'), findsNothing);
    expect(find.text('Open iOS Settings'), findsNothing);
  });

  testWidgets('opens Settings only for recoverable Apple setup status', (
    tester,
  ) async {
    final model = _Model()..status = const AppleIntelligenceNotEnabled();
    var opened = 0;
    await show(
      tester,
      model,
      settings: () async {
        opened++;
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open iOS Settings'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    model.status = const DeviceNotEligible();
    await tester.tap(find.text('Check readiness'));
    await tester.pumpAndSettle();
    expect(find.text('Open iOS Settings'), findsNothing);
  });

  testWidgets('failed readiness clears stale ready status and can retry', (
    tester,
  ) async {
    final model = _Model();
    await show(tester, model);
    await tester.pumpAndSettle();
    model.fails = true;
    await tester.tap(find.text('Check readiness'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not check model readiness. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Ready · On-device Apple Intelligence'), findsNothing);
    model.fails = false;
    await tester.tap(find.text('Check readiness'));
    await tester.pumpAndSettle();
    expect(find.text('Ready · On-device Apple Intelligence'), findsOneWidget);
  });

  testWidgets('late availability from replaced adapter does not win', (
    tester,
  ) async {
    final first = _Model()..pending = Completer<LlmAvailability>();
    await show(tester, first);
    await show(tester, _Model()..status = const DeviceNotEligible());
    await tester.pumpAndSettle();
    first.pending!.complete(const Available());
    await tester.pumpAndSettle();
    expect(find.text('Ready · On-device Apple Intelligence'), findsNothing);
    expect(
      find.text(
        'This device or OS does not support the required on-device model.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('large text remains scrollable without overflow', (tester) async {
    await show(tester, _Model(), textScale: 2);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Custom model imports'),
      300,
    );
    expect(tester.takeException(), isNull);
  });
}

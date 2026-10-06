import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/platform/llm_backend.dart';
import 'package:sekret/ui/models/models_screen.dart';
import 'package:sekret/ui/sekret_brand.dart';
import 'package:sekret/core/models/model_store.dart';
import 'model_store_test.dart' show Policy, Transport, fixture;

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
  testWidgets(
    'download requires consent, verifies, and removal requires confirmation',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('sekret-model-ui-'),
      ))!;
      final transport = Transport();
      final store = ModelStore(
        directory: directory,
        policy: Policy(),
        transport: transport,
        model: fixture,
      );
      await tester.runAsync(store.initialize);
      addTearDown(
        () => tester.runAsync(() => directory.delete(recursive: true)),
      );
      await tester.pumpWidget(
        CupertinoApp(
          theme: SekretBrand.theme,
          home: ModelsScreen(
            model: _Model(),
            openSystemSettings: () async {},
            store: store,
            supportsLocalModel: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(transport.calls, 0);
      await tester.scrollUntilVisible(find.text('Download · 2.08 GB'), 300);
      await tester.ensureVisible(find.text('Download · 2.08 GB'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download · 2.08 GB'));
      await tester.pumpAndSettle();
      expect(find.textContaining('IP address'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(transport.calls, 0);
      await tester.tap(find.text('Download · 2.08 GB'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      for (
        var i = 0;
        i < 100 && store.state.phase != ModelInstallPhase.installed;
        i++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await tester.pumpAndSettle();
      expect(store.state.phase, ModelInstallPhase.installed);
      expect(transport.calls, 1);
      // Publication is followed by closing transport/staging handles. Pump both
      // real I/O and widget microtasks until the UI operation has completed.
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
      await tester.scrollUntilVisible(
        find.text('Remove downloaded files'),
        200,
      );
      await tester.ensureVisible(find.text('Remove downloaded files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove downloaded files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.state.phase, ModelInstallPhase.installed);
      await tester.tap(find.text('Remove downloaded files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      for (
        var i = 0;
        i < 100 && store.state.phase != ModelInstallPhase.absent;
        i++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await tester.pumpAndSettle();
      expect(store.state.phase, ModelInstallPhase.absent);
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      // Keep closure in the fake clock that owns the install/remove futures.
      // Moving this into runAsync teardown deadlocks even after UI completion.
      await store.close();
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

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

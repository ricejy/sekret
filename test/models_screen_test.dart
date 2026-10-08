import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/platform/llm_backend.dart';
import 'package:sekret/core/models/model_catalogue.dart';
import 'package:sekret/core/models/model_selection.dart';
import 'package:sekret/core/chat/chat_engine.dart';
import 'package:sekret/core/chat/chat_workspace.dart';
import 'package:sekret/core/platform/apple_foundation_models.dart';
import 'package:sekret/core/storage/local_data_vault.dart';
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
      await tester.scrollUntilVisible(
        find.text('Download · 2.08 GB'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
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
        find.bySemanticsLabel('Remove downloaded files'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.bySemanticsLabel('Remove downloaded files'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Remove downloaded files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.state.phase, ModelInstallPhase.installed);
      await tester.tap(find.bySemanticsLabel('Remove downloaded files'));
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
    // This exercises real filesystem I/O and several animated confirmations.
    // It is a behavior check, not a 15-second host-performance requirement.
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets('selected Qwen removal requires explicit switch confirmation', (
    tester,
  ) async {
    final fixtureResources = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'sekret-model-selection-ui-',
      );
      final store = ModelStore(
        directory: directory,
        policy: Policy(),
        transport: Transport(),
        model: fixture,
      );
      await store.initialize();
      final vault = await openLocalDataVault(databasePath: ':memory:');
      final workspace = await ChatWorkspace.open(vault);
      final apple = AppleFoundationModels(events: const Stream.empty());
      final engine = ChatEngine(
        workspace: workspace,
        backend: apple,
        contextProbe: apple,
        groundedBackend: apple,
        model: const ModelSnapshot(
          identifier: 'apple-foundation-models',
          revision: 'test',
        ),
      );
      final selection = ModelSelection(
        store: store,
        engine: engine,
        apple: apple,
      );
      await File(
        '${directory.path}/selected-model',
      ).writeAsString(ModelCatalogue.qwen.id);
      await selection.restore();
      await store.install();
      return (
        directory: directory,
        store: store,
        vault: vault,
        workspace: workspace,
        engine: engine,
        selection: selection,
      );
    }))!;
    final selection = fixtureResources.selection;
    expect(selection.hasLocalLease, false);
    await tester.pumpWidget(
      CupertinoApp(
        theme: SekretBrand.theme,
        home: ModelsScreen(
          model: _Model()..status = const ModelNotReady(),
          openSystemSettings: () async {},
          store: fixtureResources.store,
          selection: selection,
          supportsLocalModel: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selectQwen = find.descendant(
      of: find.bySemanticsLabel('Select Qwen3-4B-Instruct-2507'),
      matching: find.byType(CupertinoButton),
    );
    expect(tester.widget<CupertinoButton>(selectQwen).onPressed, isNotNull);
    await tester.tap(selectQwen);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(selection.hasLocalLease, true);
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
    final trash = find.descendant(
      of: find.bySemanticsLabel('Remove downloaded files'),
      matching: find.byType(CupertinoButton),
    );
    expect(tester.widget<CupertinoButton>(trash).onPressed, isNotNull);
    await tester.ensureVisible(trash);
    await tester.pumpAndSettle();
    await tester.tap(trash);
    await tester.pumpAndSettle();
    expect(find.text('Switch & remove'), findsOneWidget);
    expect(
      find.textContaining('Apple Intelligence is not ready'),
      findsOneWidget,
    );
    expect(find.textContaining('Switch to Apple Intelligence'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(selection.selected, ModelCatalogue.qwen.id);
    expect(selection.hasLocalLease, isTrue);
    expect(fixtureResources.store.state.phase, ModelInstallPhase.installed);
    // A failed persisted switch must not remove the active model.
    final choicePath = '${fixtureResources.directory.path}/selected-model';
    await tester.runAsync(() async {
      await File(choicePath).delete();
      await Directory(choicePath).create();
    });
    await tester.tap(trash);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch & remove'));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(selection.selected, ModelCatalogue.qwen.id);
    expect(selection.hasLocalLease, isTrue);
    expect(fixtureResources.store.state.phase, ModelInstallPhase.installed);
    expect(find.textContaining('Could not finish.'), findsOneWidget);
    await tester.runAsync(() async {
      await Directory(choicePath).delete();
      await File(choicePath).writeAsString(ModelCatalogue.qwen.id);
    });
    await tester.ensureVisible(trash);
    await tester.pumpAndSettle();
    await tester.tap(trash);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch & remove'));
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(selection.selected, ModelCatalogue.apple.id);
    expect(selection.hasLocalLease, isFalse);
    expect(fixtureResources.store.state.phase, ModelInstallPhase.absent);
    expect(find.text('Download · 2.08 GB'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    var cleaned = false;
    final cleanup = () async {
      await fixtureResources.engine.dispose();
      await selection.close();
      await fixtureResources.store.close();
      await fixtureResources.workspace.dispose();
      await fixtureResources.vault.close();
      await fixtureResources.directory.delete(recursive: true);
      cleaned = true;
    }();
    // Resources created in the real-I/O zone are disposed after widget
    // callbacks in the fake clock. Drive both queues until they drain.
    for (var i = 0; i < 50 && !cleaned; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(cleaned, isTrue);
    await cleanup;
  });

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

  testWidgets(
    'shows held-out measured ratings and leaves resources unmeasured',
    (tester) async {
      await show(tester, _Model());
      await tester.pumpAndSettle();
      Finder rating(String id, String label) => find.descendant(
        of: find.byKey(ValueKey(id)),
        matching: find.bySemanticsLabel(label),
      );
      expect(
        rating(
          ModelCatalogue.apple.id,
          'Answer quality: 3 out of 5, held-out test',
        ),
        findsOneWidget,
      );
      expect(
        rating(ModelCatalogue.apple.id, 'Speed: 5 out of 5, held-out test'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(ValueKey(ModelCatalogue.qwen.id)));
      await tester.pumpAndSettle();
      expect(
        rating(
          ModelCatalogue.qwen.id,
          'Answer quality: 3 out of 5, held-out test',
        ),
        findsOneWidget,
      );
      expect(
        rating(ModelCatalogue.qwen.id, 'Speed: 4 out of 5, held-out test'),
        findsOneWidget,
      );
      expect(find.text('Not measured'), findsNWidgets(4));
      await tester.ensureVisible(find.text('How ratings work'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('How ratings work'));
      await tester.pumpAndSettle();
      expect(find.text('Rating scale'), findsOneWidget);
      expect(
        find.textContaining('exact output-format instructions'),
        findsOneWidget,
      );
    },
  );

  testWidgets('ready Apple check is disabled and clearly labelled', (
    tester,
  ) async {
    await show(tester, _Model());
    await tester.pumpAndSettle();
    final button = find.widgetWithText(CupertinoButton, 'Ready');
    expect(button, findsOneWidget);
    expect(tester.widget<CupertinoButton>(button).onPressed, isNull);
  });

  testWidgets('reports actual Apple readiness without fake local actions', (
    tester,
  ) async {
    await show(tester, _Model());
    await tester.pumpAndSettle();
    expect(find.text('Built into iOS'), findsOneWidget);
    expect(find.text('Apple Intelligence'), findsOneWidget);
    expect(find.text('Qwen3-4B-Instruct-2507'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Apple Intelligence')).dy,
      lessThan(tester.getTopLeft(find.text('Qwen3-4B-Instruct-2507')).dy),
    );
    // Only Apple Intelligence answers photo questions; Qwen stays text-only.
    expect(
      find.descendant(
        of: find.byKey(ValueKey(ModelCatalogue.apple.id)),
        matching: find.text('Text and photos (iOS 27)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey(ModelCatalogue.qwen.id)),
        matching: find.text('Text only'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Photo questions supported on iOS 27'),
      findsOneWidget,
    );
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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      find.text('Could not check model readiness. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Built into iOS'), findsNothing);
    model.fails = false;
    await tester.tap(find.text('Check readiness'));
    await tester.pumpAndSettle();
    expect(find.text('Built into iOS'), findsOneWidget);
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
    expect(find.text('Built into iOS'), findsNothing);
    expect(
      find.text(
        'This device or OS does not support the required on-device model.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('intro says every model is local and choice is free', (
    tester,
  ) async {
    await show(tester, _Model());
    await tester.pumpAndSettle();
    expect(find.text('Choose your model'), findsOneWidget);
    for (final label in ['Offline', 'Free', 'Private']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('search filters models and handles no matches', (tester) async {
    await show(tester, _Model());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoSearchTextField), 'QWEN');
    await tester.pumpAndSettle();
    expect(find.text('Apple Intelligence'), findsNothing);
    expect(find.text('Qwen3-4B-Instruct-2507'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoSearchTextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No matching models'), findsOneWidget);
  });

  testWidgets('checking state is visible and disabled until completion', (
    tester,
  ) async {
    final model = _Model()..pending = Completer<LlmAvailability>();
    await show(tester, model);
    await tester.pump();
    expect(find.text('Checking…'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoButton>(
            find.widgetWithText(CupertinoButton, 'Checking…'),
          )
          .onPressed,
      isNull,
    );
    model.pending!.complete(const Available());
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('large text remains scrollable without overflow', (tester) async {
    await show(tester, _Model(), textScale: 2);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Qwen3-4B-Instruct-2507'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}

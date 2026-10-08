import 'dart:async';
import 'dart:io';
import 'package:sekret/core/models/model_store.dart';
import 'model_store_test.dart' show Policy, Transport, fixture;
import 'app_protection_test.dart' show FakeDeviceProtection;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/chat/chat_engine.dart';
import 'package:sekret/core/chat/chat_workspace.dart';
import 'package:sekret/core/knowledge/knowledge_base.dart';
import 'package:sekret/core/platform/apple_foundation_models.dart';
import 'package:sekret/core/storage/local_data_vault.dart';
import 'package:sekret/demo/fake_native_capabilities.dart';
import 'package:sekret/ui/sekret_chat_app.dart';
import 'package:sekret/ui/sekret_brand.dart';
import 'chat_screen_test.dart' show UiModel;

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pumpAndSettle();
  }

  Future<void> waitForIo(WidgetTester tester, bool Function() completed) async {
    final elapsed = Stopwatch()..start();
    while (!completed()) {
      expect(
        elapsed.elapsed,
        lessThan(const Duration(seconds: 10)),
        reason: 'Real I/O did not finish while pumping widget microtasks',
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  for (final lock in [false, true]) {
    testWidgets('model download survives background with app lock $lock', (
      tester,
    ) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('sekret-lock-download-'),
      ))!;
      final chunks = StreamController<List<int>>();
      final transport = Transport()..source = () => chunks.stream;
      final store = ModelStore(
        directory: directory,
        policy: Policy(),
        transport: transport,
        model: fixture,
      );
      await tester.runAsync(store.initialize);
      final vault = await openLocalDataVault(databasePath: ':memory:');
      await vault.settings.update(
        retentionPolicy: RetentionPolicy.manual,
        biometricLockEnabled: lock,
        lockDelay: AppLockDelay.immediate,
        onboardingComplete: true,
      );
      final workspace = await ChatWorkspace.open(vault);
      final knowledge = await KnowledgeBase.open(
        vault: vault,
        embedder: const FakeEmbedder(),
        tokenCounter: const FakeTokenCounter(),
      );
      final model = UiModel();
      final engine = ChatEngine(
        workspace: workspace,
        backend: model,
        contextProbe: model,
        knowledgeBase: knowledge,
        model: const ModelSnapshot(identifier: 'test', revision: '1'),
      );
      final app = ChatAppResources(
        vault,
        workspace,
        knowledge,
        engine,
        AppleFoundationModels(events: const Stream.empty()),
        device: FakeDeviceProtection(),
        modelStore: store,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(SekretChatApp(openResources: () async => app));
      await settle(tester);
      await app.protection.unlock();
      Object? failure;
      var finished = false;
      final install = store
          .install()
          .catchError((Object error) {
            failure = error;
          })
          .whenComplete(() => finished = true);
      await waitForIo(tester, () => transport.calls > 0 || finished);
      expect(transport.calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester);
      expect(find.byType(TuckPrivacy), findsOneWidget);
      expect(store.state.phase, ModelInstallPhase.downloading);
      // A slow completion must not be mistaken for cancellation or failure.
      // Real time deliberately exceeds the old 150 ms polling budget.
      await tester.runAsync(() async {
        unawaited(
          Future<void>.delayed(const Duration(seconds: 1)).then((_) {
            chunks.add([1, 2, 3, 4]);
            unawaited(chunks.close());
          }),
        );
      });
      // Await the operation, including verification and cleanup, rather than
      // assuming a fixed number of short host-time delays is enough.
      await waitForIo(tester, () => finished);
      await install;
      expect(failure, isNull);
      expect(store.state.phase, ModelInstallPhase.installed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.runAsync(() => directory.delete(recursive: true));
    });
  }

  testWidgets(
    'tabs keep generation alive, while backgrounding obscures and interrupts',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final vault = await openLocalDataVault(databasePath: ':memory:');
      await vault.settings.update(
        retentionPolicy: RetentionPolicy.manual,
        biometricLockEnabled: false,
        lockDelay: AppLockDelay.immediate,
        onboardingComplete: true,
      );
      final workspace = await ChatWorkspace.open(vault);
      final knowledge = await KnowledgeBase.open(
        vault: vault,
        embedder: const FakeEmbedder(),
        tokenCounter: const FakeTokenCounter(),
      );
      final model = UiModel()..stream = StreamController<String>();
      final engine = ChatEngine(
        workspace: workspace,
        backend: model,
        contextProbe: model,
        groundedBackend: model,
        knowledgeBase: knowledge,
        model: const ModelSnapshot(identifier: 'fixture', revision: '1'),
      );
      final resources = ChatAppResources(
        vault,
        workspace,
        knowledge,
        engine,
        AppleFoundationModels(events: const Stream.empty()),
      );
      await tester.pumpWidget(
        SekretChatApp(openResources: () async => resources),
      );
      await settle(tester);
      final pageContext = tester.element(
        find.byType(CupertinoPageScaffold).first,
      );
      expect(CupertinoTheme.of(pageContext).brightness, Brightness.dark);
      expect(MediaQuery.platformBrightnessOf(pageContext), Brightness.dark);
      expect(
        CupertinoTheme.of(pageContext).scaffoldBackgroundColor,
        SekretBrand.background,
      );
      expect(
        tester
            .widget<CupertinoTabBar>(find.byType(CupertinoTabBar))
            .items
            .map((item) => item.label),
        ['Chat', 'Models', 'Knowledge Vault', 'Settings'],
      );
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoTabBar),
          matching: find.text('Models'),
        ),
      );
      await settle(tester);
      expect(find.text('Not available in this version'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoTabBar),
          matching: find.text('Chat'),
        ),
      );
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Add sources'));
      await settle(tester);
      // Text sources are imported in Knowledge; the paperclip selects them.
      await tester.runAsync(
        () => knowledge.importText(
          title: 'Fixture source',
          text: 'The fictional museum opens at noon.',
        ),
      );
      await tester.tap(find.text('Choose from Knowledge Vault'));
      await settle(tester);
      await tester.tap(find.text('Fixture source'));
      await tester.tap(find.text('Done'));
      await settle(tester);
      final imported = (await knowledge.catalogue()).single.item;
      expect(imported.title, 'Fixture source');
      expect((await workspace.history()).single.selectedSourceIds, [
        imported.id,
      ]);
      expect((await workspace.history()).single.mode, ChatMode.knowledgeBase);
      await tester.tap(find.bySemanticsLabel('Remove Fixture source'));
      await settle(tester);
      expect((await workspace.history()).single.mode, ChatMode.general);
      expect((await knowledge.catalogue()).single.item.id, imported.id);
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is CupertinoTextField && w.placeholder == 'Message',
        ),
        'Start a response',
      );
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Send'));
      await settle(tester);
      final chatId = workspace.currentChatId!;
      model.stream!.add('Private partial response');
      await settle(tester);
      expect(engine.isGenerating, isTrue);
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoTabBar),
          matching: find.text('Knowledge Vault'),
        ),
      );
      await settle(tester);
      expect(engine.isGenerating, isTrue);
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoTabBar),
          matching: find.text('Chat'),
        ),
      );
      await settle(tester);
      expect(find.text('Private partial response'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(find.text('Private partial response').hitTestable(), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester);
      expect(engine.isGenerating, isFalse);
      expect(
        (await workspace.transcript(chatId)).single.outcome,
        TurnOutcome.interrupted,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(
        find.text('Interrupted · Regenerate to try again'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.runAsync(model.stream!.close);
    },
  );

  testWidgets('startup failure explains that existing data is not reset', (
    tester,
  ) async {
    await tester.pumpWidget(
      SekretChatApp(
        openResources: () async =>
            throw const UnrecognizedVaultSchemaException(['documents']),
      ),
    );
    await settle(tester);
    expect(
      find.textContaining('Existing data has not been reset.'),
      findsOneWidget,
    );
    expect(find.byType(CupertinoTabBar), findsNothing);
  });
}

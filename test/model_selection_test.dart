import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/chat/chat_engine.dart';
import 'package:sekret/core/chat/chat_workspace.dart';
import 'package:sekret/core/models/model_catalogue.dart';
import 'package:sekret/core/models/model_selection.dart';
import 'package:sekret/core/models/model_store.dart';
import 'package:sekret/core/platform/apple_foundation_models.dart';
import 'package:sekret/core/platform/llm_backend.dart';
import 'package:sekret/core/storage/local_data_vault.dart';
import 'dart:async';

import 'model_store_test.dart' show Hasher, Policy, Transport, fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ModelStore store;
  late LocalDataVault vault;
  late ChatWorkspace workspace;
  late ChatEngine engine;
  late ModelSelection selection;
  late AppleFoundationModels apple;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sekret-model-choice-');
    store = ModelStore(
      directory: directory,
      policy: Policy(),
      transport: Transport(),
      model: fixture,
    );
    await store.initialize();
    vault = await openLocalDataVault(databasePath: ':memory:');
    workspace = await ChatWorkspace.open(vault);
    apple = AppleFoundationModels(events: const Stream.empty());
    engine = ChatEngine(
      workspace: workspace,
      backend: apple,
      contextProbe: apple,
      groundedBackend: apple,
      model: const ModelSnapshot(
        identifier: 'apple-foundation-models',
        revision: 'test',
      ),
    );
    selection = ModelSelection(store: store, engine: engine, apple: apple);
  });
  tearDown(() async {
    await engine.dispose();
    await selection.close();
    await store.close();
    await workspace.dispose();
    await vault.close();
    await directory.delete(recursive: true);
  });
  test(
    'selection is explicit, persisted, idle-only, and guards model removal',
    () async {
      await selection.restore();
      expect(selection.selected, ModelCatalogue.apple.id);
      await expectLater(selection.select('unreviewed'), throwsStateError);
      await expectLater(
        selection.select(ModelCatalogue.qwen.id),
        throwsStateError,
      );
      await store.install();
      await selection.select(ModelCatalogue.qwen.id);
      expect(engine.modelIdentifier, ModelCatalogue.qwen.id);
      expect(engine.supportsKnowledgeBase, false);
      expect(engine.outputTokenReserve, 256);
      await expectLater(store.remove(), throwsStateError);
      await selection.select(ModelCatalogue.apple.id);
      expect(engine.supportsKnowledgeBase, true);
      expect(engine.outputTokenReserve, 512);
      await store.remove();
      expect(
        await File('${directory.path}/selected-model').readAsString(),
        ModelCatalogue.apple.id,
      );
    },
  );
  test('missing saved Qwen never silently falls back to Apple', () async {
    await File(
      '${directory.path}/selected-model',
    ).writeAsString(ModelCatalogue.qwen.id);
    await selection.restore();
    expect(selection.selected, ModelCatalogue.qwen.id);
    expect(engine.modelIdentifier, ModelCatalogue.qwen.id);
    expect(await engine.availability(), isA<ModelNotReady>());
    expect(engine.supportsKnowledgeBase, false);
    expect(selection.hasLocalLease, false);
    await store.install();
    await selection.select(ModelCatalogue.qwen.id);
    expect(selection.hasLocalLease, true);
    await selection.select(ModelCatalogue.apple.id);
    expect(engine.modelIdentifier, ModelCatalogue.apple.id);
  });
  test(
    'saved Qwen waits for startup verification instead of answering',
    () async {
      await store.install();
      await File(
        '${directory.path}/selected-model',
      ).writeAsString(ModelCatalogue.qwen.id);
      final hasher = Hasher()..gate = Completer<void>();
      final restarted = ModelStore(
        directory: directory,
        policy: Policy(),
        transport: Transport(),
        hasher: hasher,
        model: fixture,
      );
      final restored = ModelSelection(
        store: restarted,
        engine: engine,
        apple: apple,
      );
      final storeReady = restarted.initialize();
      await restored.restore(storeReady: storeReady);
      for (
        var i = 0;
        i < 100 && restarted.state.phase != ModelInstallPhase.verifying;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(restarted.state.phase, ModelInstallPhase.verifying);
      expect(restored.selected, ModelCatalogue.qwen.id);
      expect(engine.modelIdentifier, isNot(ModelCatalogue.apple.id));
      expect(await engine.availability(), isA<ModelLoading>());
      expect(restored.hasLocalLease, false);

      hasher.gate!.complete();
      await storeReady;
      for (var i = 0; i < 100 && !restored.hasLocalLease; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(engine.modelIdentifier, ModelCatalogue.qwen.id);
      expect(restored.hasLocalLease, true);
      await restored.select(ModelCatalogue.apple.id);
      await restored.close();
      await restarted.close();
    },
  );
  test('corrupt choice fails closed but explicit selection recovers', () async {
    await File('${directory.path}/selected-model').writeAsString('unknown');
    await selection.restore();
    expect(selection.selected, 'unavailable');
    expect(await engine.availability(), isA<ModelNotReady>());
    await selection.select(ModelCatalogue.apple.id);
    expect(selection.selected, ModelCatalogue.apple.id);
  });
  test(
    'failed persistence preserves prior backend and releases new lease',
    () async {
      await store.install();
      (store.policy as Policy).fail = true;
      await expectLater(
        selection.select(ModelCatalogue.qwen.id),
        throwsStateError,
      );
      expect(engine.modelIdentifier, ModelCatalogue.apple.id);
      expect(engine.supportsKnowledgeBase, true);
      expect(selection.selected, ModelCatalogue.apple.id);
      await store.remove();
    },
  );
}

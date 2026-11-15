import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/chat/chat_engine.dart';
import 'package:sekret/core/chat/chat_workspace.dart';
import 'package:sekret/core/models/model_catalogue.dart';
import 'package:sekret/core/models/model_library.dart';
import 'package:sekret/core/models/model_selection.dart';
import 'package:sekret/core/models/model_store.dart';
import 'package:sekret/core/platform/apple_foundation_models.dart';
import 'package:sekret/core/platform/llm_backend.dart';
import 'package:sekret/core/storage/local_data_vault.dart';
import 'dart:async';

import 'package:crypto/crypto.dart';

import 'model_store_test.dart'
    show Hasher, Policy, Transport, fixture, payload, revision;

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
    selection = ModelSelection(
      library: ModelLibrary(directory: store.directory, stores: [store]),
      engine: engine,
      apple: apple,
    );
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
        library: ModelLibrary(
          directory: restarted.directory,
          stores: [restarted],
        ),
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
  test('provenance records each new model\'s own profile and files', () {
    final templates = <String>{};
    for (final model in [
      ModelCatalogue.qwen35FourB,
      ModelCatalogue.qwen35TwoB,
      ModelCatalogue.miniCpm5TwoB,
      ModelCatalogue.miniCpm5OneB,
      ModelCatalogue.granite41ThreeB,
    ]) {
      final profile = model.profile!;
      final metadata = localModelProvenance(model);
      expect(metadata, {
        'artifactSHA256': model.weights!.sha256,
        'artifactSHA256s': [for (final file in model.artifacts) file.sha256],
        'quantization': profile.quantization,
        'runtime': 'llama.cpp-b11429',
        'context': 2048,
        'outputCap': 256,
        'template': profile.template,
        'localInstructions': 'local-general-v1',
      });
      expect(
        metadata['template'],
        isNot(ModelCatalogue.qwen.profile!.template),
      );
      templates.add(profile.template);
    }
    expect(templates, hasLength(3));
    expect(localModelProvenance(ModelCatalogue.qwen), {
      'artifactSHA256':
          '9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9',
      'quantization': 'Q3_K_M',
      'runtime': 'llama.cpp-b11429',
      'context': 2048,
      'outputCap': 256,
      'template': 'chatml-general-json-v1',
      'localInstructions': 'local-general-v1',
    });
  });
  test(
    'a new chat model is selectable, General only, with its own limits',
    () async {
      final base = ModelCatalogue.granite41ThreeB;
      final model = CatalogueModel(
        id: base.id,
        name: base.name,
        kind: base.kind,
        runtime: base.runtime,
        capabilities: base.capabilities,
        summary: base.summary,
        profile: base.profile,
        notice: base.notice,
        isNew: true,
        artifacts: [
          for (final (index, path) in ['README.md', 'model.gguf'].indexed)
            ModelArtifact(
              repository: 'test/model',
              revision: revision,
              path: path,
              bytes: payload.length,
              sha256: sha256.convert(payload).toString(),
              role: index == 0 ? ArtifactRole.license : ArtifactRole.weights,
            ),
        ],
      );
      final local = ModelStore(
        directory: directory,
        policy: Policy(),
        transport: Transport(),
        model: model,
      );
      await local.initialize();
      final chooser = ModelSelection(
        library: ModelLibrary(directory: directory, stores: [store, local]),
        engine: engine,
        apple: apple,
        catalogue: [ModelCatalogue.apple, fixture, model],
      );
      await expectLater(chooser.select(model.id), throwsStateError);
      await local.install();
      await chooser.select(model.id);
      expect(chooser.selected, model.id);
      expect(engine.modelIdentifier, model.id);
      expect(engine.supportsKnowledgeBase, isFalse);
      expect(await engine.supportsPhotoQuestions(), isFalse);
      expect(engine.outputTokenReserve, 256);
      expect(
        await File('${directory.path}/selected-model').readAsString(),
        model.id,
      );
      await expectLater(local.remove(), throwsStateError);
      await chooser.select(ModelCatalogue.apple.id);
      await local.remove();
      await chooser.close();
      await local.close();
    },
  );
}

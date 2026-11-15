import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/chat/chat_engine.dart';
import 'package:sekret/core/chat/chat_workspace.dart';
import 'package:sekret/core/models/background_model_download.dart';
import 'package:sekret/core/models/model_catalogue.dart';
import 'package:sekret/core/models/model_download.dart';
import 'package:sekret/core/models/model_library.dart';
import 'package:sekret/core/models/model_selection.dart';
import 'package:sekret/core/models/model_store.dart';
import 'package:sekret/core/platform/apple_foundation_models.dart';
import 'package:sekret/core/storage/local_data_vault.dart';

import 'model_store_test.dart' show Download, Policy, fixture, revision;

/// Fictional bytes for each repository path.
final contents = <String, List<int>>{
  'Encoder.mlmodelc/weights/weight.bin': [1, 1, 1, 1, 1],
  'Encoder.mlmodelc/model.mil': [2, 2],
  'vocab.json': [3, 3, 3],
  'voice.bin': [4, 4, 4, 4],
  'test.gguf': [1, 2, 3, 4], // The legacy fixture's payload.
};

ModelArtifact file(String path, {ArtifactRole role = ArtifactRole.weights}) =>
    ModelArtifact(
      repository: 'fixture/speech',
      revision: revision,
      path: path,
      bytes: contents[path]!.length,
      sha256: sha256.convert(contents[path]!).toString(),
      role: role,
    );

final voiceFixture = CatalogueModel(
  id: 'fixture-voice-input',
  name: 'Fixture Voice',
  kind: ModelKind.voiceInput,
  runtime: ModelRuntime.fluidAudio,
  capabilities: const {},
  summary: 'Turns fictional speech into text.',
  isNew: true,
  notice: const ModelNotice(
    license: 'CC-BY-4.0',
    credit: 'Fixture Voice by Fixture Lab',
    attribution: 'Fixture Voice © Fixture Lab, CC BY 4.0',
  ),
  artifacts: [
    file('Encoder.mlmodelc/weights/weight.bin'),
    file('Encoder.mlmodelc/model.mil', role: ArtifactRole.config),
    file('vocab.json', role: ArtifactRole.tokenizer),
  ],
);

final readAloudFixture = CatalogueModel(
  id: 'fixture-read-aloud',
  name: 'Fixture Reader',
  kind: ModelKind.readAloud,
  runtime: ModelRuntime.fluidAudio,
  capabilities: const {},
  summary: 'Reads fictional answers aloud.',
  artifacts: [file('voice.bin', role: ArtifactRole.voice)],
);

class PathTransport implements ModelTransport {
  final calls = <String>[];
  final failing = <String>{};
  final silent = <String, StreamController<List<int>>>{};
  @override
  Future<ModelDownload> open(
    ModelArtifact artifact,
    ModelCancellation cancel,
  ) async {
    calls.add(artifact.path);
    if (failing.contains(artifact.path)) {
      return Download(Stream.error(const SocketException('offline')));
    }
    final held = silent[artifact.path];
    return Download(held?.stream ?? Stream.value(contents[artifact.path]!));
  }
}

/// One native transfer at a time, like the iOS background session.
class SharedBackground implements BackgroundModelDownload {
  String? running;
  int cancellations = 0;
  Completer<void>? gate;
  @override
  Future<bool> hasPending(File destination) async =>
      running == destination.path;
  @override
  Future<void> cancel() async {
    cancellations++;
    running = null;
    gate?.completeError(const ModelOperationCancelled());
    gate = null;
  }

  @override
  Future<void> transfer({
    required ModelArtifact artifact,
    required File destination,
    required ModelCancellation cancel,
    required void Function(int) onProgress,
  }) async {
    if (running != null) throw StateError('Another transfer is running');
    running = destination.path;
    try {
      if (gate != null) await cancel.wait(gate!.future);
      await destination.writeAsBytes(contents[artifact.path] ?? [1, 2, 3, 4]);
      onProgress(artifact.bytes);
      running = null;
    } on Object {
      await this.cancel();
      rethrow;
    }
  }
}

Future<List<String>> listing(Directory root) async => [
  for (final entry in await root.list(recursive: true).toList())
    entry.path.substring(root.path.length + 1),
]..sort();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Policy policy;
  late PathTransport transport;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sekret-model-library-');
    policy = Policy();
    transport = PathTransport();
  });
  tearDown(() => root.delete(recursive: true));

  ModelStore store(CatalogueModel model, {BackgroundModelDownload? bg}) =>
      ModelStore(
        directory: root,
        policy: policy,
        transport: transport,
        backgroundDownload: bg,
        model: model,
      );

  test('a many-file model installs into its own folder as published', () async {
    final voice = store(voiceFixture);
    await voice.initialize();
    await voice.install();
    expect(voice.state.phase, ModelInstallPhase.installed);
    expect(voice.state.receivedBytes, voiceFixture.totalBytes);
    expect(await listing(root), [
      'fixture-voice-input',
      'fixture-voice-input/Encoder.mlmodelc',
      'fixture-voice-input/Encoder.mlmodelc/model.mil',
      'fixture-voice-input/Encoder.mlmodelc/weights',
      'fixture-voice-input/Encoder.mlmodelc/weights/weight.bin',
      'fixture-voice-input/vocab.json',
    ]);
    final lease = voice.acquire();
    expect(lease.directory, '${root.path}/fixture-voice-input');
    expect(lease.path, endsWith('Encoder.mlmodelc/weights/weight.bin'));
    lease.release();
    await voice.remove();
    expect(await listing(root), isEmpty);
    await voice.close();
  });

  test(
    'a failed file keeps verified ones, restart reports partial, then resumes',
    () async {
      var voice = store(voiceFixture);
      await voice.initialize();
      transport.failing.add('vocab.json');
      await expectLater(voice.install(), throwsA(isA<SocketException>()));
      expect(voice.state.phase, ModelInstallPhase.failed);
      expect(voice.acquire, throwsStateError);
      // No staging survives; the two verified files do.
      expect(
        (await listing(root)).where((path) => path.endsWith('.partial')),
        isEmpty,
      );
      expect(
        await File(
          '${root.path}/fixture-voice-input/Encoder.mlmodelc/model.mil',
        ).exists(),
        isTrue,
      );
      await voice.close();

      voice = store(voiceFixture);
      await voice.initialize();
      expect(voice.state.phase, ModelInstallPhase.failed);
      expect(voice.state.message, contains('incomplete'));
      expect(voice.state.receivedBytes, 7);
      transport.failing.clear();
      transport.calls.clear();
      await voice.install();
      expect(transport.calls, ['vocab.json']);
      expect(voice.state.phase, ModelInstallPhase.installed);
      await voice.close();
    },
  );

  test('a corrupted published file is replaced on resume', () async {
    final voice = store(voiceFixture);
    await voice.initialize();
    await voice.install();
    await voice.close();
    await File(
      '${root.path}/fixture-voice-input/vocab.json',
    ).writeAsBytes([9, 9, 9]);
    final restarted = store(voiceFixture);
    await expectLater(restarted.initialize(), throwsException);
    transport.calls.clear();
    await expectLater(restarted.install(), throwsStateError);
    await File('${root.path}/fixture-voice-input/vocab.json').delete();
    await restarted.install();
    expect(transport.calls, ['vocab.json']);
    expect(restarted.state.phase, ModelInstallPhase.installed);
    await restarted.close();
  });

  test('a linked folder inside a model is never followed', () async {
    final outside = await Directory.systemTemp.createTemp('sekret-outside-');
    try {
      await File('${outside.path}/model.mil').writeAsString('keep');
      await Directory('${root.path}/fixture-voice-input').create();
      await Link(
        '${root.path}/fixture-voice-input/Encoder.mlmodelc',
      ).create(outside.path);
      final voice = store(voiceFixture);
      await expectLater(voice.initialize(), throwsStateError);
      await expectLater(voice.remove(), throwsStateError);
      expect(await File('${outside.path}/model.mil').readAsString(), 'keep');
      expect(transport.calls, isEmpty);
      await voice.close();
    } finally {
      await outside.delete(recursive: true);
    }
  });

  test('rejects artifacts that could escape or collide', () {
    for (final model in [
      CatalogueModel(
        id: 'bad',
        name: 'Bad',
        kind: ModelKind.readAloud,
        runtime: ModelRuntime.fluidAudio,
        capabilities: const {},
        summary: '',
        artifacts: [file('voice.bin'), file('voice.bin')],
      ),
      CatalogueModel(
        id: '../bad',
        name: 'Bad',
        kind: ModelKind.readAloud,
        runtime: ModelRuntime.fluidAudio,
        capabilities: const {},
        summary: '',
        artifacts: [file('voice.bin')],
      ),
      ModelCatalogue.apple,
    ]) {
      expect(() => store(model), throwsArgumentError, reason: model.id);
    }
  });

  test('library runs one download at a time and erases every model', () async {
    final legacy = store(fixture);
    final voice = store(voiceFixture);
    final reader = store(readAloudFixture);
    final library = ModelLibrary(
      directory: root,
      stores: [legacy, voice, reader],
    );
    await library.initialize();
    final held = StreamController<List<int>>();
    transport.silent['vocab.json'] = held;
    final first = library.install(voiceFixture.id);
    while (!transport.calls.contains('vocab.json')) {
      await Future<void>.delayed(Duration.zero);
    }
    await expectLater(library.install(fixture.id), throwsStateError);
    held.add(contents['vocab.json']!);
    await held.close();
    await first;
    await library.install(fixture.id);
    await library.install(readAloudFixture.id);
    expect([
      for (final s in library.stores) s.state.phase,
    ], everyElement(ModelInstallPhase.installed));
    // The legacy layout is unchanged: one file at the top level.
    expect(
      await File('${root.path}/${fixture.weights!.sha256}.gguf').exists(),
      isTrue,
    );
    await library.removeAll();
    expect(await listing(root), isEmpty);
    await library.close();
  });

  test('removing one model never cancels another model’s transfer', () async {
    final background = SharedBackground();
    final voice = store(voiceFixture, bg: background);
    final reader = store(readAloudFixture, bg: background);
    final library = ModelLibrary(directory: root, stores: [voice, reader]);
    await library.initialize();
    await library.install(readAloudFixture.id);
    background.gate = Completer<void>();
    final transfer = library.install(voiceFixture.id);
    while (background.running == null) {
      await Future<void>.delayed(Duration.zero);
    }
    await reader.remove();
    expect(background.cancellations, 0);
    expect(background.running, isNotNull);
    final failure = expectLater(transfer, throwsException);
    await voice.cancel();
    await failure;
    expect(background.cancellations, greaterThan(0));
    await library.close();
  });

  group('optional voice input and read aloud choices', () {
    late LocalDataVault vault;
    late ChatWorkspace workspace;
    late ChatEngine engine;
    late AppleFoundationModels apple;
    late ModelLibrary library;
    final catalogue = [
      ModelCatalogue.apple,
      fixture,
      voiceFixture,
      readAloudFixture,
    ];
    setUp(() async {
      library = ModelLibrary(
        directory: root,
        stores: [store(fixture), store(voiceFixture), store(readAloudFixture)],
      );
      await library.initialize();
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
    });
    tearDown(() async {
      await engine.dispose();
      await library.close();
      await workspace.dispose();
      await vault.close();
    });

    ModelSelection open() => ModelSelection(
      library: library,
      engine: engine,
      apple: apple,
      catalogue: catalogue,
    );

    test('default off, need a verified install, persist and restore', () async {
      final selection = open();
      await selection.restore();
      expect(selection.selectedFor(ModelKind.voiceInput), isNull);
      expect(selection.selectedFor(ModelKind.readAloud), isNull);
      await expectLater(
        selection.choose(ModelKind.voiceInput, voiceFixture.id),
        throwsStateError,
      );
      await library.install(voiceFixture.id);
      await expectLater(
        selection.choose(ModelKind.readAloud, voiceFixture.id),
        throwsStateError,
      );
      await expectLater(
        selection.choose(ModelKind.chat, fixture.id),
        throwsArgumentError,
      );
      await selection.choose(ModelKind.voiceInput, voiceFixture.id);
      await selection.close();

      final restored = open();
      await restored.restore();
      expect(restored.selectedFor(ModelKind.voiceInput), voiceFixture.id);
      expect(restored.selected, ModelCatalogue.apple.id);
      // Chat cannot be pointed at a speech model.
      await expectLater(restored.select(voiceFixture.id), throwsStateError);
      await restored.choose(ModelKind.voiceInput, null);
      await restored.close();

      final off = open();
      await off.restore();
      expect(off.selectedFor(ModelKind.voiceInput), isNull);
      await off.close();
    });

    test('a read-aloud voice persists and resets with the model', () async {
      final catalogueWithApple = [...catalogue, ModelCatalogue.appleVoices];
      ModelSelection openWithApple() => ModelSelection(
        library: library,
        engine: engine,
        apple: apple,
        catalogue: catalogueWithApple,
      );
      final selection = openWithApple();
      await selection.restore();
      await expectLater(
        selection.chooseReadAloudVoice('fake.voice.ada'),
        throwsStateError,
      );
      // Apple voices are built in: no download needed.
      await selection.choose(
        ModelKind.readAloud,
        ModelCatalogue.appleVoices.id,
      );
      await expectLater(
        selection.chooseReadAloudVoice('../escape'),
        throwsArgumentError,
      );
      await selection.chooseReadAloudVoice('fake.voice.ada');
      expect(selection.readAloudVoice, 'fake.voice.ada');
      await selection.close();

      final restored = openWithApple();
      await restored.restore();
      expect(
        restored.selectedFor(ModelKind.readAloud),
        ModelCatalogue.appleVoices.id,
      );
      expect(restored.readAloudVoice, 'fake.voice.ada');
      await library.install(readAloudFixture.id);
      await restored.choose(ModelKind.readAloud, readAloudFixture.id);
      expect(restored.readAloudVoice, isNull);
      await restored.close();

      final reopened = openWithApple();
      await reopened.restore();
      expect(reopened.readAloudVoice, isNull);
      await reopened.close();
    });

    test('an unknown saved choice restores as off', () async {
      await File('${root.path}/selected-read-aloud').writeAsString(fixture.id);
      final selection = open();
      await selection.restore();
      expect(selection.selectedFor(ModelKind.readAloud), isNull);
      expect(selection.selected, ModelCatalogue.apple.id);
      await selection.close();
    });
  });
}

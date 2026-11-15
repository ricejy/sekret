import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/models/model_artifact_verifier.dart';
import 'package:sekret/core/models/model_catalogue.dart';

void main() {
  ModelArtifact fixture({int bytes = 3, String? digest}) => ModelArtifact(
    repository: 'fixture/model',
    revision: 'a06e946bb6b655725eafa393f4a9745d460374c9',
    path: 'fixture.gguf',
    bytes: bytes,
    sha256: digest ?? sha256.convert(utf8.encode('abc')).toString(),
  );

  test(
    'initial catalogue is Apple first and only the selected Qwen artifact',
    () {
      expect(ModelCatalogue.entries, [
        ModelCatalogue.apple,
        ModelCatalogue.qwen,
        ModelCatalogue.appleVoices,
      ]);
      expect(ModelCatalogue.appleVoices.kind, ModelKind.readAloud);
      expect(ModelCatalogue.appleVoices.downloadable, isFalse);
      expect(ModelCatalogue.apple.artifacts, isEmpty);
      expect(ModelCatalogue.apple.downloadable, isFalse);
      expect(ModelCatalogue.qwen.capabilities, {ModelCapability.generalText});
      expect(ModelCatalogue.qwen.kind, ModelKind.chat);
      expect(ModelCatalogue.qwen.legacyStorage, isTrue);
      expect(ModelCatalogue.qwen.artifacts, hasLength(1));
      final artifact = ModelCatalogue.qwen.weights!;
      expect(artifact.valid, isTrue);
      expect(ModelCatalogue.qwen.totalBytes, artifact.bytes);
      expect(artifact.bytes, 2075618400);
      expect(
        artifact.sha256,
        '9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9',
      );
      expect(
        artifact.downloadUri.toString(),
        'https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/'
        'a06e946bb6b655725eafa393f4a9745d460374c9/'
        'Qwen3-4B-Instruct-2507-Q3_K_M.gguf',
      );
      expect(() => ModelCatalogue.entries.clear(), throwsUnsupportedError);
    },
  );

  test('artifact paths cannot leave the model folder', () {
    ModelArtifact at(String path) => ModelArtifact(
      repository: 'fixture/model',
      revision: 'a06e946bb6b655725eafa393f4a9745d460374c9',
      path: path,
      bytes: 3,
      sha256: sha256.convert(utf8.encode('abc')).toString(),
    );
    expect(at('Encoder.mlmodelc/weights/weight.bin').valid, isTrue);
    for (final bad in [
      '../escape.bin',
      'a/../../b',
      '/absolute',
      '.hidden',
      'a//b',
      'a/',
      '',
      'space name',
    ]) {
      expect(at(bad).valid, isFalse, reason: bad);
    }
    expect(fixture().valid, isTrue);
  });

  test('every reviewed artifact is pinned to a commit with a valid hash', () {
    for (final model in ModelCatalogue.entries) {
      expect(model.artifacts.every((file) => file.valid), isTrue);
      expect(model.downloadable, model.artifacts.isNotEmpty);
      expect(ModelCatalogue.byId(model.id), same(model));
      if (model.kind == ModelKind.chat && model.downloadable) {
        expect(model.profile, isNotNull);
      }
    }
  });

  test('verifies exact artifact over separate chunks', () async {
    await verifyModelArtifact(
      Stream.fromIterable([
        [97],
        [],
        [98, 99],
      ]),
      fixture(),
    );
  });

  test('rejects incomplete and oversized artifacts', () async {
    for (final bytes in [
      [97, 98],
      [97, 98, 99, 100],
    ]) {
      await expectLater(
        verifyModelArtifact(Stream.value(bytes), fixture()),
        throwsA(isA<ModelArtifactVerificationException>()),
      );
    }
  });

  test('rejects same-length corrupted bytes', () async {
    await expectLater(
      verifyModelArtifact(Stream.value([97, 98, 100]), fixture()),
      throwsA(isA<ModelArtifactVerificationException>()),
    );
  });

  test('does not treat interrupted input as verified', () async {
    Stream<List<int>> interrupted() async* {
      yield [97];
      throw StateError('transfer interrupted');
    }

    await expectLater(
      verifyModelArtifact(interrupted(), fixture()),
      throwsStateError,
    );
  });

  test('invalid manifest rejected without consuming input', () async {
    var read = false;
    Stream<List<int>> input() async* {
      read = true;
      yield [97];
    }

    await expectLater(
      verifyModelArtifact(input(), fixture(digest: 'not-a-hash')),
      throwsA(isA<ModelArtifactVerificationException>()),
    );
    expect(read, isFalse);
  });
}

import 'dart:convert';
import 'dart:io';

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

  test('catalogue is Apple first, then the original Qwen artifact', () {
    expect(ModelCatalogue.entries.take(2), [
      ModelCatalogue.apple,
      ModelCatalogue.qwen,
    ]);
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
  });

  test('every id that ever shipped stays listed', () {
    for (final id in [
      'apple-foundation-models',
      'qwen3-4b-instruct-2507-q3-k-m',
      'qwen3.5-4b-q3km',
      'qwen3.5-2b-q4km',
      'minicpm5-2b-q4km',
      'minicpm5-1b-q4km',
      'granite-4.1-3b-q4km',
    ]) {
      expect(ModelCatalogue.byId(id), isNotNull, reason: id);
    }
    final ids = ModelCatalogue.entries.map((model) => model.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('new chat models match the reviewed pins exactly', () {
    final manifest =
        jsonDecode(
              File(
                'docs/evaluation/model-expansion-artifacts-2026-11-15.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final chat = [
      for (final entry in manifest['models']! as List<Object?>)
        if ((entry! as Map)['kind'] == 'chat') entry as Map<String, Object?>,
    ];
    expect(chat.map((entry) => entry['id']), [
      ModelCatalogue.qwen35FourB.id,
      ModelCatalogue.qwen35TwoB.id,
      ModelCatalogue.miniCpm5TwoB.id,
      ModelCatalogue.miniCpm5OneB.id,
      ModelCatalogue.granite41ThreeB.id,
    ]);
    for (final entry in chat) {
      final model = ModelCatalogue.byId(entry['id']! as String)!;
      expect(model.kind, ModelKind.chat);
      expect(model.runtime, ModelRuntime.llamaCpp);
      expect(model.capabilities, {ModelCapability.generalText});
      expect(model.isNew, isTrue);
      expect(model.legacyStorage, isFalse);
      expect(model.addOnFor, isNull);
      expect(model.notice!.license, 'Apache-2.0');
      expect(entry['license'], 'apache-2.0');
      expect(entry['gated'], isFalse);
      expect(model.totalBytes, entry['totalBytes']);
      final files = entry['files']! as List<Object?>;
      expect(model.artifacts, hasLength(files.length));
      for (final file in files.cast<Map<String, Object?>>()) {
        final artifact = model.artifacts.singleWhere(
          (artifact) => artifact.path == file['path'],
        );
        expect(artifact.repository, entry['repository']);
        expect(artifact.revision, entry['revision']);
        expect(artifact.bytes, file['bytes']);
        expect(artifact.sha256, file['sha256']);
        expect(
          artifact.role,
          file['role'] == 'weights'
              ? ArtifactRole.weights
              : ArtifactRole.license,
        );
        expect(artifact.valid, isTrue);
      }
      final profile = model.profile!;
      expect(profile.runtime, 'llama.cpp-b11429');
      expect(profile.instructions, 'local-general-v1');
      expect(profile.context, 2048);
      expect(profile.outputCap, 256);
      expect(model.weights!.path, endsWith('.gguf'));
    }
  });

  test('native profiles and paths match the catalogue', () {
    final profiles = File(
      'native/SekretInference/Sources/SekretInference/ModelProfile.swift',
    ).readAsStringSync();
    final plugin = File('ios/Runner/LocalModelPlugin.swift').readAsStringSync();
    final chat = ModelCatalogue.entries.where(
      (model) => model.kind == ModelKind.chat && model.downloadable,
    );
    expect(chat, hasLength(6));
    expect(chat.map((model) => model.profile!.id).toSet(), hasLength(6));
    for (final model in chat) {
      final profile = model.profile!;
      final weights = model.weights!;
      final block = profiles.substring(profiles.indexOf('id: "${profile.id}"'));
      final end = block.indexOf('checksEmbeddedTemplate');
      final native = block.substring(0, end);
      expect(native, contains('sha256: "${weights.sha256}"'));
      final bytes = weights.bytes.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+$)'),
        (_) => '_',
      );
      expect(native, contains('bytes: $bytes,'), reason: profile.id);
      expect(native, contains('context: ${profile.context}'));
      expect(native, contains('output: ${profile.outputCap}'));
      if (!model.legacyStorage) {
        expect(plugin, contains('"${model.id}/${weights.path}"'));
      }
    }
  });

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

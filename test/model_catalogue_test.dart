import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/models/model_artifact_verifier.dart';
import 'package:sekret/core/models/model_catalogue.dart';

void main() {
  ModelArtifact fixture({int bytes = 3, String? digest}) => ModelArtifact(
    repository: 'fixture/model',
    revision: 'fixed',
    filename: 'fixture.gguf',
    bytes: bytes,
    sha256: digest ?? sha256.convert(utf8.encode('abc')).toString(),
  );

  test(
    'initial catalogue is Apple first and only the selected Qwen artifact',
    () {
      expect(ModelCatalogue.entries, [
        ModelCatalogue.apple,
        ModelCatalogue.qwen,
      ]);
      expect(ModelCatalogue.apple.artifact, isNull);
      expect(ModelCatalogue.qwen.integrationReady, isFalse);
      expect(ModelCatalogue.qwen.capabilities, {ModelCapability.generalText});
      final artifact = ModelCatalogue.qwen.artifact!;
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

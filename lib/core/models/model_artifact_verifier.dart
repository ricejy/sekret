import 'package:crypto/crypto.dart' as crypto;

import 'model_catalogue.dart';

class ModelArtifactVerificationException implements Exception {
  const ModelArtifactVerificationException(this.reason);
  final String reason;

  @override
  String toString() => 'Model artifact verification failed: $reason';
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? digest;
  @override
  void add(crypto.Digest data) => digest = data;
  @override
  void close() {}
}

/// Bounded-memory integrity check; does not download, publish or select a model.
/// The installer must own the staged file exclusively until atomic publication.
Future<void> verifyModelArtifact(
  Stream<List<int>> chunks,
  ModelArtifact artifact,
) async {
  if (artifact.bytes <= 0 ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(artifact.sha256)) {
    throw const ModelArtifactVerificationException('Invalid artifact manifest');
  }
  var bytes = 0;
  final output = _DigestSink();
  final hash = crypto.sha256.startChunkedConversion(output);
  try {
    await for (final chunk in chunks) {
      if (chunk.length > artifact.bytes - bytes) {
        throw const ModelArtifactVerificationException('Artifact exceeds size');
      }
      bytes += chunk.length;
      hash.add(chunk);
    }
  } finally {
    hash.close();
  }
  if (bytes != artifact.bytes) {
    throw const ModelArtifactVerificationException('Artifact is incomplete');
  }
  if (output.digest.toString() != artifact.sha256) {
    throw const ModelArtifactVerificationException('Artifact digest mismatch');
  }
}

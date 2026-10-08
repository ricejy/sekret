import 'dart:io';

import 'model_catalogue.dart';
import 'model_download.dart';

/// Transfers public, reviewed weights to the store's unverified staging file.
/// Ownership of network work survives Dart suspension and process recreation.
abstract interface class BackgroundModelDownload {
  Future<bool> hasPending();
  Future<void> transfer({
    required ModelArtifact artifact,
    required File destination,
    required ModelCancellation cancel,
    required void Function(int) onProgress,
  });

  /// Resolves only after native work can no longer publish a staging file.
  Future<void> cancel();
}

/// Byte count and SHA-256 of a local model file, computed off the UI thread.
abstract interface class ModelFileHasher {
  Future<({int bytes, String sha256})> hash(File file);
}

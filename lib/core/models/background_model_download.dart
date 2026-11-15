import 'dart:io';

import 'model_catalogue.dart';
import 'model_download.dart';

/// Transfers one public, reviewed file to a store's unverified staging file.
/// Ownership of network work survives Dart suspension and process recreation.
/// The system session runs one transfer at a time for every model.
abstract interface class BackgroundModelDownload {
  /// Whether a transfer into [destination] is running or has completed into
  /// it and awaits verification.
  Future<bool> hasPending(File destination);
  Future<void> transfer({
    required ModelArtifact artifact,
    required File destination,
    required ModelCancellation cancel,
    required void Function(int) onProgress,
  });

  /// Stops the transfer in flight, whichever file it is. Resolves only after
  /// native work can no longer publish a staging file.
  Future<void> cancel();
}

/// Byte count and SHA-256 of a local model file, computed off the UI thread.
abstract interface class ModelFileHasher {
  Future<({int bytes, String sha256})> hash(File file);
}

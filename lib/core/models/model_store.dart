import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model_artifact_verifier.dart';
import 'background_model_download.dart';
import 'model_catalogue.dart';
import 'model_download.dart';

enum ModelInstallPhase {
  absent,
  downloading,
  verifying,
  installed,
  removing,
  failed,
}

class ModelInstallState {
  const ModelInstallState(this.phase, {this.receivedBytes = 0, this.message});
  final ModelInstallPhase phase;

  /// Bytes of the whole model on disk or in flight, across all its files.
  final int receivedBytes;
  final String? message;
  bool get busy => const {
    ModelInstallPhase.downloading,
    ModelInstallPhase.verifying,
    ModelInstallPhase.removing,
  }.contains(phase);
}

/// iOS adapter protects the owned directory, excludes it from backups and
/// reports real free space. It must fail closed if any check is unavailable.
abstract interface class ModelStoragePolicy {
  Future<int> prepare(Directory directory);
}

/// Owns one reviewed model's files under `reviewed-models/`. Each pinned file
/// is staged as `<sha256>.partial`, verified for exact size and SHA-256, then
/// atomically renamed to its published path. The model is usable only when
/// every file verifies. Staging is never selectable, no manifest or path
/// received from the network is interpreted, and explicit cancellation
/// discards the file in flight. Files already verified are kept, so a
/// many-file model resumes where it stopped. iOS-owned transfers survive lock
/// and suspension and are reattached on startup before verification.
///
/// A [CatalogueModel.legacyStorage] model keeps the original single-file
/// layout (`download.partial`, `<sha256>.gguf`) in the shared directory.
final class ModelStore extends ChangeNotifier {
  ModelStore({
    required this.directory,
    required this.policy,
    this.transport = const HttpsModelTransport(),
    this.backgroundDownload,
    this.hasher,
    this.model = ModelCatalogue.qwen,
  }) {
    final files = model.artifacts;
    final paths = files.map((file) => file.path).toSet();
    if (!model.downloadable ||
        files.isEmpty ||
        paths.length != files.length ||
        !files.every((file) => file.valid) ||
        !RegExp(r'^[a-z0-9][a-z0-9.-]*$').hasMatch(model.id) ||
        (model.legacyStorage && files.length != 1)) {
      throw ArgumentError('A valid pinned model artifact is required');
    }
  }

  /// The shared `reviewed-models` directory.
  final Directory directory;
  final ModelStoragePolicy policy;
  final ModelTransport transport;
  final BackgroundModelDownload? backgroundDownload;

  /// Native SHA-256 when available; the portable Dart verifier otherwise.
  final ModelFileHasher? hasher;
  final CatalogueModel model;
  static const freeSpaceReserve = 512 * 1024 * 1024;
  ModelInstallState _state = const ModelInstallState(ModelInstallPhase.absent);
  ModelInstallState get state => _state;
  ModelCancellation? _operation;
  Future<void>? _pending;
  bool _initialized = false;
  bool get initialized => _initialized;
  bool _closed = false;
  int _leases = 0;

  /// The staging file of a system-owned transfer adopted at startup.
  String? _recovering;

  bool get _legacy => model.legacyStorage;

  /// This model's own folder; the shared directory for the legacy layout.
  Directory get modelDirectory =>
      _legacy ? directory : Directory('${directory.path}/${model.id}');

  File _staging(ModelArtifact file) => _legacy
      ? File('${directory.path}/download.partial')
      : File('${modelDirectory.path}/${file.sha256}.partial');

  File _installed(ModelArtifact file) => _legacy
      ? File('${directory.path}/${file.sha256}.gguf')
      : File('${modelDirectory.path}/${file.path}');

  Iterable<File> get _stagings =>
      {for (final file in model.artifacts) _staging(file).path}.map(File.new);

  void _publish(ModelInstallPhase phase, {int bytes = 0, String? message}) {
    _state = ModelInstallState(phase, receivedBytes: bytes, message: message);
    if (!_closed) notifyListeners();
  }

  /// Every path component is a real directory or file, never a link, even
  /// when a link's target is missing.
  Future<void> _assertOwned() async {
    Future<FileSystemEntityType> type(String path) =>
        FileSystemEntity.type(path, followLinks: false);
    if (await type(directory.path) != FileSystemEntityType.directory) {
      throw StateError('Model storage is not a regular directory');
    }
    final folder = await type(modelDirectory.path);
    if (folder == FileSystemEntityType.notFound) return;
    if (folder != FileSystemEntityType.directory) {
      throw StateError('Unexpected model storage entry');
    }
    for (final file in model.artifacts) {
      for (final entry in [_staging(file), _installed(file)]) {
        final relative = entry.path.substring(modelDirectory.path.length + 1);
        final parts = relative.split('/');
        var path = modelDirectory.path;
        for (var i = 0; i < parts.length; i++) {
          path = '$path/${parts[i]}';
          final found = await type(path);
          if (found == FileSystemEntityType.notFound) break;
          final expected = i == parts.length - 1
              ? FileSystemEntityType.file
              : FileSystemEntityType.directory;
          if (found != expected) {
            throw StateError('Unexpected model storage entry');
          }
        }
      }
    }
  }

  Future<void> _delete(File file) async {
    await _assertOwned();
    if (await file.exists()) await file.delete();
  }

  /// Removes empty folders this store created, deepest first.
  Future<void> _prune() async {
    if (_legacy || !await modelDirectory.exists()) return;
    await _assertOwned();
    final folders =
        await modelDirectory
              .list(recursive: true, followLinks: false)
              .where((entry) => entry is Directory)
              .map((entry) => entry.path)
              .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final path in [...folders, modelDirectory.path]) {
      final folder = Directory(path);
      if (await folder.list(followLinks: false).isEmpty) await folder.delete();
    }
  }

  Future<bool> _complete() async {
    for (final file in model.artifacts) {
      if (!await _installed(file).exists()) return false;
    }
    return true;
  }

  Future<String?> _ownPendingTransfer() async {
    final background = backgroundDownload;
    if (background == null) return null;
    for (final staging in _stagings) {
      if (await background.hasPending(staging)) return staging.path;
    }
    return null;
  }

  /// The native session runs one transfer for all models. Cancel it only when
  /// it belongs to this model.
  Future<void> _cancelOwnTransfer() async {
    if (await _ownPendingTransfer() != null) {
      await backgroundDownload!.cancel();
    }
  }

  Future<void> initialize() =>
      _run((cancel) async {
        final type = await FileSystemEntity.type(
          directory.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) await directory.create();
        await _assertOwned();
        await policy.prepare(directory);
        _recovering = await _ownPendingTransfer();
        // Only this store's known staging names are reclaimed after
        // interruption; an adopted transfer keeps its own.
        for (final staging in _stagings) {
          if (staging.path != _recovering) await _delete(staging);
        }
        _initialized = true;
        if (await _complete()) {
          if (_recovering != null) {
            await backgroundDownload?.cancel();
            for (final staging in _stagings) {
              await _delete(staging);
            }
            _recovering = null;
          }
          _publish(ModelInstallPhase.verifying);
          for (final file in model.artifacts) {
            await _verify(_installed(file), file, cancel);
          }
          _publish(ModelInstallPhase.installed);
        } else if (await _onDisk() > 0 && _recovering == null) {
          _publish(
            ModelInstallPhase.failed,
            bytes: await _onDisk(),
            message: 'Download incomplete. Download to resume, or remove it.',
          );
        } else {
          _publish(ModelInstallPhase.absent);
        }
        await _prune();
      }).then((_) {
        if (_recovering != null &&
            _state.phase != ModelInstallPhase.installed) {
          // Do not hold app startup behind a system-owned transfer.
          unawaited(install().catchError((Object _) {}));
        }
      });

  /// Bytes of published files; partial staging is not counted.
  Future<int> _onDisk() async {
    var bytes = 0;
    for (final file in model.artifacts) {
      if (await _installed(file).exists()) bytes += file.bytes;
    }
    return bytes;
  }

  Future<void> install() => _run((cancel) async {
    if (!_initialized) throw StateError('Model storage is not ready');
    if (_leases != 0 || await _complete()) {
      throw StateError('Remove the existing model before installing');
    }
    await _assertOwned();
    final freeBytes = await policy.prepare(directory);
    var needed = model.totalBytes - await _onDisk();
    final recovering = _recovering;
    if (recovering != null) {
      needed -= model.artifacts
          .where((file) => _staging(file).path == recovering)
          .first
          .bytes;
    }
    if (freeBytes < needed + freeSpaceReserve) {
      throw StateError(
        'Not enough free space for this model and safety reserve',
      );
    }
    cancel.check();
    var done = 0;
    _publish(ModelInstallPhase.downloading);
    try {
      if (!await modelDirectory.exists()) await modelDirectory.create();
      for (final file in model.artifacts) {
        final installed = _installed(file);
        if (await installed.exists()) {
          // Published earlier, possibly in a previous session.
          try {
            await _verify(installed, file, cancel);
            done += file.bytes;
            _publish(ModelInstallPhase.downloading, bytes: done);
            continue;
          } on ModelArtifactVerificationException {
            await _delete(installed);
          }
        }
        await _fetch(file, cancel, done);
        cancel.check();
        _publish(ModelInstallPhase.verifying, bytes: done + file.bytes);
        // Verify the bytes actually persisted, not just the network stream.
        await _verify(_staging(file), file, cancel);
        await _assertOwned();
        cancel.check();
        await _createParents(installed);
        // Atomic publication on the same volume. No metadata flag can promote
        // a partial or corrupt file, including after process termination.
        await _staging(file).rename(installed.path);
        done += file.bytes;
        _publish(ModelInstallPhase.downloading, bytes: done);
      }
      _publish(ModelInstallPhase.installed, bytes: done);
    } finally {
      _recovering = null;
      for (final staging in _stagings) {
        await _delete(staging);
      }
      await _prune();
    }
  });

  Future<void> _createParents(File file) async {
    var folder = modelDirectory.path;
    final relative = file.path.substring(folder.length + 1).split('/');
    for (final part in relative.take(relative.length - 1)) {
      folder = '$folder/$part';
      if (!await Directory(folder).exists()) await Directory(folder).create();
    }
    await _assertOwned();
  }

  Future<void> _fetch(
    ModelArtifact file,
    ModelCancellation cancel,
    int done,
  ) async {
    final staged = _staging(file);
    final background = backgroundDownload;
    if (background != null) {
      // An adopted transfer may already have completed into its staging file.
      if (staged.path != _recovering) await _delete(staged);
      await background.transfer(
        artifact: file,
        destination: staged,
        cancel: cancel,
        onProgress: (bytes) =>
            _publish(ModelInstallPhase.downloading, bytes: done + bytes),
      );
      return;
    }
    ModelDownload? download;
    RandomAccessFile? sink;
    var received = 0;
    try {
      await _delete(staged);
      sink = await staged.open(mode: FileMode.writeOnly);
      // Apply protection before any model bytes arrive.
      await policy.prepare(directory);
      download = await transport.open(file, cancel);
      await for (final chunk in _read(download.bytes, cancel)) {
        if (chunk.length > file.bytes - received) {
          throw const ModelArtifactVerificationException(
            'Artifact exceeds size',
          );
        }
        await sink.writeFrom(chunk);
        received += chunk.length;
        _publish(ModelInstallPhase.downloading, bytes: done + received);
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } finally {
      await download?.close();
      await sink?.close();
    }
  }

  /// Exact size and SHA-256 of the persisted file, every launch and install.
  Future<void> _verify(
    File file,
    ModelArtifact artifact,
    ModelCancellation cancel,
  ) async {
    final hasher = this.hasher;
    if (hasher == null) {
      await verifyModelArtifact(_read(file.openRead(), cancel), artifact);
    } else {
      final result = await cancel.wait(hasher.hash(file));
      if (result.bytes != artifact.bytes) {
        throw const ModelArtifactVerificationException(
          'Artifact is incomplete',
        );
      }
      if (result.sha256 != artifact.sha256) {
        throw const ModelArtifactVerificationException(
          'Artifact digest mismatch',
        );
      }
    }
    cancel.check();
  }

  /// Native inference holds a lease until all work has stopped and it unloads.
  /// A lease can never be obtained while installation/verification is running.
  ModelLease acquire() {
    if (_closed ||
        _operation != null ||
        _state.phase != ModelInstallPhase.installed) {
      throw StateError('A verified installed model is required');
    }
    _leases++;
    final weights = model.weights ?? model.artifacts.first;
    return ModelLease._(
      _installed(weights).path,
      modelDirectory.path,
      () => _leases--,
    );
  }

  Future<void> remove() => _run((cancel) async {
    if (!_initialized || _leases != 0) {
      throw StateError('Switch away from this model before removing it');
    }
    _publish(ModelInstallPhase.removing);
    await _cancelOwnTransfer();
    for (final staging in _stagings) {
      await _delete(staging);
    }
    for (final file in model.artifacts) {
      await _delete(_installed(file));
    }
    await _prune();
    _publish(ModelInstallPhase.absent);
  });

  Future<void> cancel() async {
    if (_operation == null) await _cancelOwnTransfer();
    _operation?.cancel();
    try {
      await _pending;
    } on Object {
      // Original caller receives the failure; cancellation waits for cleanup.
    }
  }

  Future<void> _run(Future<void> Function(ModelCancellation) work) {
    if (_closed || _operation != null) {
      return Future.error(StateError('Another model operation is active'));
    }
    final cancel = ModelCancellation();
    _operation = cancel;
    final previous = _state;
    return _pending = () async {
      try {
        await work(cancel);
      } on Object catch (error) {
        // Do not demote a still-installed model when removal was refused.
        if (previous.phase == ModelInstallPhase.installed &&
            await _complete()) {
          _publish(
            ModelInstallPhase.installed,
            message: 'Model is still installed',
          );
        } else {
          _publish(
            ModelInstallPhase.failed,
            message: error is ModelOperationCancelled
                ? 'Cancelled. Partial download removed. You can restart.'
                : 'Model operation failed. Check storage and connection, then retry.',
          );
        }
        rethrow;
      } finally {
        _operation = null;
      }
    }();
  }

  Stream<List<int>> _read(
    Stream<List<int>> source,
    ModelCancellation cancel,
  ) async* {
    final reader = StreamIterator(source);
    try {
      while (await cancel.wait(reader.moveNext())) {
        cancel.check();
        yield reader.current;
      }
    } finally {
      await reader.cancel();
    }
  }

  Future<void> close() async {
    _closed = true;
    await cancel();
    super.dispose();
  }
}

final class ModelLease {
  ModelLease._(this.path, this.directory, this._release);

  /// The primary weights file.
  final String path;

  /// The model's folder, for runtimes that load a directory of files.
  final String directory;
  void Function()? _release;
  void release() {
    _release?.call();
    _release = null;
  }
}

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

/// The store exclusively owns two fixed files in a dedicated app directory.
/// Staging is never selectable. No manifest/path received from the network is
/// interpreted. Explicit cancellation discards partial bytes. iOS-owned transfers
/// survive lock/suspension and are reattached on startup before verification.
final class ModelStore extends ChangeNotifier {
  ModelStore({
    required this.directory,
    required this.policy,
    this.transport = const HttpsModelTransport(),
    this.backgroundDownload,
    this.model = ModelCatalogue.qwen,
  }) {
    final artifact = model.artifact;
    if (artifact == null ||
        artifact.bytes <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(artifact.sha256)) {
      throw ArgumentError('A valid pinned model artifact is required');
    }
  }

  final Directory directory;
  final ModelStoragePolicy policy;
  final ModelTransport transport;
  final BackgroundModelDownload? backgroundDownload;
  bool _recovering = false;
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
  ModelArtifact get _artifact => model.artifact!;
  File get _staged => File('${directory.path}/download.partial');
  File get _installed => File('${directory.path}/${_artifact.sha256}.gguf');

  void _publish(ModelInstallPhase phase, {int bytes = 0, String? message}) {
    _state = ModelInstallState(phase, receivedBytes: bytes, message: message);
    if (!_closed) notifyListeners();
  }

  Future<void> _assertOwned() async {
    // A link is not an owned directory/file, even when its target is missing.
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Model storage is not a regular directory');
    }
    for (final file in [_staged, _installed]) {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw StateError('Unexpected model storage entry');
      }
    }
  }

  Future<void> _delete(File file) async {
    await _assertOwned();
    if (await file.exists()) await file.delete();
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
        // Only this store's known staging name is reclaimed after interruption.
        _recovering = await backgroundDownload?.hasPending() ?? false;
        if (!_recovering) await _delete(_staged);
        _initialized = true;
        if (await _installed.exists()) {
          if (_recovering) {
            await backgroundDownload?.cancel();
            await _delete(_staged);
            _recovering = false;
          }
          _publish(ModelInstallPhase.verifying);
          await verifyModelArtifact(
            _read(_installed.openRead(), cancel),
            _artifact,
          );
          cancel.check();
          _publish(ModelInstallPhase.installed);
        } else {
          _publish(ModelInstallPhase.absent);
        }
      }).then((_) {
        if (_recovering && _state.phase != ModelInstallPhase.installed) {
          // Do not hold app startup behind a system-owned transfer.
          unawaited(install().catchError((Object _) {}));
        }
      });

  Future<void> install() => _run((cancel) async {
    if (!_initialized) throw StateError('Model storage is not ready');
    if (_leases != 0 || await _installed.exists()) {
      throw StateError('Remove the existing model before installing');
    }
    await _assertOwned();
    final freeBytes = await policy.prepare(directory);
    if (freeBytes < (_recovering ? 0 : _artifact.bytes) + freeSpaceReserve) {
      throw StateError(
        'Not enough free space for this model and safety reserve',
      );
    }
    cancel.check();
    _publish(ModelInstallPhase.downloading);
    ModelDownload? download;
    RandomAccessFile? sink;
    var received = 0;
    try {
      if (backgroundDownload != null) {
        await backgroundDownload!.transfer(
          artifact: _artifact,
          destination: _staged,
          cancel: cancel,
          onProgress: (bytes) {
            received = bytes;
            _publish(ModelInstallPhase.downloading, bytes: bytes);
          },
        );
      } else {
        await _delete(_staged);
        sink = await _staged.open(mode: FileMode.writeOnly);
        // Apply protection before any model bytes arrive.
        await policy.prepare(directory);
        download = await transport.open(_artifact, cancel);
        await for (final chunk in _read(download.bytes, cancel)) {
          if (chunk.length > _artifact.bytes - received) {
            throw const ModelArtifactVerificationException(
              'Artifact exceeds size',
            );
          }
          await sink.writeFrom(chunk);
          received += chunk.length;
          _publish(ModelInstallPhase.downloading, bytes: received);
        }
        await sink.flush();
        await sink.close();
        sink = null;
      }
      cancel.check();
      _publish(ModelInstallPhase.verifying, bytes: received);
      // Verify the bytes actually persisted, not just the network stream.
      await verifyModelArtifact(_read(_staged.openRead(), cancel), _artifact);
      await _assertOwned();
      cancel.check();
      // Atomic publication on the same volume. No metadata flag can promote
      // a partial or corrupt artifact, including after process termination.
      await _staged.rename(_installed.path);
      _publish(ModelInstallPhase.installed, bytes: received);
    } finally {
      _recovering = false;
      await download?.close();
      await sink?.close();
      await _delete(_staged);
    }
  });

  /// Native inference holds a lease until all work has stopped and it unloads.
  /// A lease can never be obtained while installation/verification is running.
  ModelLease acquire() {
    if (_closed ||
        _operation != null ||
        _state.phase != ModelInstallPhase.installed) {
      throw StateError('A verified installed model is required');
    }
    _leases++;
    return ModelLease._(_installed.path, () => _leases--);
  }

  Future<void> remove() => _run((cancel) async {
    if (!_initialized || _leases != 0) {
      throw StateError('Switch away from this model before removing it');
    }
    _publish(ModelInstallPhase.removing);
    await backgroundDownload?.cancel();
    await _delete(_staged);
    await _delete(_installed);
    _publish(ModelInstallPhase.absent);
  });

  Future<void> cancel() async {
    if (_operation == null) await backgroundDownload?.cancel();
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
            await _installed.exists()) {
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
  ModelLease._(this.path, this._release);
  final String path;
  void Function()? _release;
  void release() {
    _release?.call();
    _release = null;
  }
}

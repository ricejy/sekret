import 'dart:io';

import 'package:flutter/foundation.dart';

import 'background_model_download.dart';
import 'model_catalogue.dart';
import 'model_download.dart';
import 'model_store.dart';

/// Every downloadable model's store, sharing one `reviewed-models` directory
/// and the single native transfer session. One download runs at a time; a
/// second is refused rather than queued, so nothing starts without a tap.
final class ModelLibrary extends ChangeNotifier {
  ModelLibrary({required this.directory, required Iterable<ModelStore> stores})
    : _stores = {for (final store in stores) store.model.id: store} {
    if (_stores.length != stores.length ||
        _stores.values.any((store) => store.directory.path != directory.path)) {
      throw ArgumentError('Stores must be distinct and share one directory');
    }
    for (final store in _stores.values) {
      store.addListener(notifyListeners);
    }
  }

  /// One store for each downloadable catalogue entry.
  factory ModelLibrary.reviewed({
    required Directory directory,
    required ModelStoragePolicy policy,
    ModelTransport transport = const HttpsModelTransport(),
    BackgroundModelDownload? backgroundDownload,
    ModelFileHasher? hasher,
    List<CatalogueModel> catalogue = ModelCatalogue.entries,
  }) => ModelLibrary(
    directory: directory,
    stores: [
      for (final model in catalogue.where((model) => model.downloadable))
        ModelStore(
          directory: directory,
          policy: policy,
          transport: transport,
          backgroundDownload: backgroundDownload,
          hasher: hasher,
          model: model,
        ),
    ],
  );

  final Directory directory;
  final Map<String, ModelStore> _stores;

  Iterable<ModelStore> get stores => _stores.values;
  ModelStore? store(String id) => _stores[id];

  /// The storage policy shared by every store.
  ModelStoragePolicy? get policy => _stores.values.firstOrNull?.policy;

  /// Verifies every installed model, one at a time. Each store reports its own
  /// failure; the first is rethrown after all have been checked.
  Future<void> initialize() async {
    Object? failure;
    for (final store in _stores.values) {
      try {
        await store.initialize();
      } on Object catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }

  Future<void> install(String id) async {
    final store = _stores[id];
    if (store == null) throw StateError('Unreviewed model');
    if (_stores.values.any((other) => other != store && other.state.busy)) {
      throw StateError('Wait for the other download to finish');
    }
    if (!store.initialized) await store.initialize();
    await store.install();
  }

  /// Erase All: stop any transfer, then remove every model's files. Callers
  /// first switch chat away from downloaded models so no lease is held.
  Future<void> removeAll() async {
    Object? failure;
    for (final store in _stores.values) {
      try {
        await store.cancel();
        if (!store.initialized) {
          try {
            await store.initialize();
          } on Object {
            // Verification failed; the files are removed below regardless.
          }
          await store.cancel();
        }
        await store.remove();
      } on Object catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }

  Future<void> cancel() async {
    for (final store in _stores.values) {
      await store.cancel();
    }
  }

  Future<void> close() async {
    for (final store in _stores.values) {
      store.removeListener(notifyListeners);
      await store.close();
    }
    super.dispose();
  }
}

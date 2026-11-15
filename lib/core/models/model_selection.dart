import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../chat/chat_engine.dart';
import '../platform/apple_foundation_models.dart';
import '../platform/llm_backend.dart';
import '../platform/local_model_backend.dart';
import '../platform/token_counter.dart';
import '../storage/local_data_vault.dart';
import 'model_catalogue.dart';
import 'model_library.dart';
import 'model_store.dart';

/// One explicit, persisted choice; no automatic fallback on missing/corrupt
/// downloads, memory pressure, disabled Apple Intelligence or restarts.
/// Chat has one model; voice input and read aloud each have an optional
/// one, off until the person picks it.
final class ModelSelection extends ChangeNotifier {
  ModelSelection({
    required this.library,
    required this.engine,
    required this.apple,
    this.catalogue = ModelCatalogue.entries,
  });
  final ModelLibrary library;

  /// Reviewed entries that can be chosen; tests pass a fixture catalogue.
  final List<CatalogueModel> catalogue;
  CatalogueModel? _byId(String id) =>
      catalogue.where((model) => model.id == id).firstOrNull;
  final ChatEngine engine;
  final AppleFoundationModels apple;
  String _selected = ModelCatalogue.apple.id;
  String get selected => _selected;
  final _optional = <ModelKind, String?>{
    ModelKind.voiceInput: null,
    ModelKind.readAloud: null,
  };
  bool get hasLocalLease => _lease != null;
  Future<void>? _restoring;
  bool _busy = false;
  bool get busy => _busy;
  ModelLease? _lease;
  Future<void>? _pending;
  Directory get _directory => library.directory;
  File get _choice => File('${_directory.path}/selected-model');
  File get _staging => File('${_directory.path}/selection.partial');
  File _optionalChoice(ModelKind kind) => File(
    '${_directory.path}/${kind == ModelKind.voiceInput ? 'selected-voice-input' : 'selected-read-aloud'}',
  );

  /// The chosen model of [kind]; null when voice input or read aloud is off.
  String? selectedFor(ModelKind kind) =>
      kind == ModelKind.chat ? _selected : _optional[kind];

  Future<void> _validateFiles() async {
    if (await FileSystemEntity.type(_directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Invalid selection directory');
    }
    for (final file in [
      _choice,
      _staging,
      for (final kind in _optional.keys) _optionalChoice(kind),
    ]) {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.notFound) {
        throw StateError('Invalid selection file');
      }
    }
  }

  /// With [storeReady], a saved downloaded model is restored once the store
  /// has verified it; until then chat reports the model as not ready instead
  /// of answering with another model. Apple restores immediately.
  Future<void> restore({Future<void>? storeReady}) async {
    for (final kind in _optional.keys) {
      try {
        _optional[kind] = await _read(_optionalChoice(kind), kind);
      } on Object {
        // An unreadable optional choice restores as off.
        _optional[kind] = null;
      }
    }
    try {
      await _validateFiles();
      final id = await _read(_choice, ModelKind.chat);
      if (id == null) return;
      if (storeReady != null && id != ModelCatalogue.apple.id) {
        await _awaitVerification(id, storeReady);
        return;
      }
      await _select(id, persist: false);
    } on Object {
      await _restoreUnavailable();
    }
  }

  Future<String?> _read(File file, ModelKind kind) async {
    await _validateFiles();
    if (!await file.exists()) return null;
    if (await file.length() > 100) throw StateError('Invalid selection');
    final id = await file.readAsString();
    if (_byId(id)?.kind != kind) {
      throw StateError('Unknown selection');
    }
    return id;
  }

  /// Turns voice input or read aloud on with an installed model, or off.
  Future<void> choose(ModelKind kind, String? id) async {
    if (kind == ModelKind.chat) throw ArgumentError('Use select for chat');
    if (_busy) throw StateError('Another model change is active');
    final model = id == null ? null : _byId(id);
    if (id != null && model?.kind != kind) {
      throw StateError('Unreviewed model');
    }
    if (model != null &&
        model.downloadable &&
        library.store(model.id)?.state.phase != ModelInstallPhase.installed) {
      throw StateError('Download and verify this model first');
    }
    _busy = true;
    notifyListeners();
    try {
      await _write(_optionalChoice(kind), id);
      _optional[kind] = id;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _awaitVerification(String id, Future<void> storeReady) async {
    _selected = id;
    await engine.switchModel(
      backend: const _VerifyingModel(),
      contextProbe: const _VerifyingModel(),
      model: const ModelSnapshot(identifier: 'verifying', revision: 'none'),
    );
    notifyListeners();
    _restoring = () async {
      try {
        try {
          await storeReady;
        } on Object {
          // An unverified model restores as unavailable below.
        }
        await _select(id, persist: false);
      } on Object {
        try {
          await _restoreUnavailable();
        } on Object {
          // The app is closing; the engine is already disposed.
        }
      }
    }();
  }

  Future<void> _restoreUnavailable() async {
    _selected = 'unavailable';
    const unavailable = _UnavailableModel();
    await engine.switchModel(
      backend: unavailable,
      contextProbe: unavailable,
      model: const ModelSnapshot(identifier: 'unavailable', revision: 'none'),
    );
    notifyListeners();
  }

  Future<void> select(String id) => _select(id, persist: true);

  Future<void> _select(String id, {required bool persist}) {
    if (_busy || engine.isGenerating) {
      return Future.error(StateError('Finish the current response first'));
    }
    final model = _byId(id);
    if (model == null ||
        model.kind != ModelKind.chat ||
        model.addOnFor != null ||
        model.runtime == ModelRuntime.fluidAudio) {
      return Future.error(StateError('Unreviewed model'));
    }
    _busy = true;
    notifyListeners();
    return _pending = () async {
      ModelLease? nextLease;
      try {
        final isApple = model.runtime == ModelRuntime.apple;
        final store = library.store(id);
        final profile = model.profile;
        GeneralLlmBackend backend = apple;
        ModelContextProbe probe = apple;
        if (!isApple) {
          if (store == null || profile == null) {
            throw StateError('Model not available in this version');
          }
          if (store.state.phase == ModelInstallPhase.installed) {
            nextLease = store.acquire();
            final local = LocalModelBackend(path: nextLease.path);
            backend = local;
            probe = local;
          } else if (!persist) {
            const unavailable = _UnavailableModel();
            backend = unavailable;
            probe = unavailable;
          } else {
            throw StateError('Download and verify this model first');
          }
        }
        await engine.switchModel(
          backend: backend,
          contextProbe: probe,
          grounded: isApple ? apple : null,
          photo: isApple ? apple : null,
          model: ModelSnapshot(
            identifier: id,
            revision: isApple
                ? Platform.operatingSystemVersion
                : model.weights!.revision,
            metadata: isApple
                ? const {}
                : {
                    'artifactSHA256': model.weights!.sha256,
                    if (model.artifacts.length > 1)
                      'artifactSHA256s': [
                        for (final file in model.artifacts) file.sha256,
                      ],
                    'quantization': profile!.quantization,
                    'runtime': profile.runtime,
                    'context': profile.context,
                    'outputCap': profile.outputCap,
                    'template': profile.template,
                    'localInstructions': profile.instructions,
                  },
          ),
          outputTokens: isApple ? 512 : profile!.outputCap,
          beforeChange: persist ? () => _persist(id) : null,
        );
        _lease?.release();
        _lease = nextLease;
        nextLease = null;
        _selected = id;
      } finally {
        nextLease?.release();
        _busy = false;
        notifyListeners();
      }
    }();
  }

  Future<void> _persist(String id) => _write(_choice, id);

  /// Atomic replace of one choice file; null deletes it.
  Future<void> _write(File target, String? id) async {
    await _validateFiles();
    try {
      if (id == null) {
        if (await target.exists()) await target.delete();
        return;
      }
      await _staging.writeAsString(id, flush: true);
      await library.policy?.prepare(_directory);
      await _validateFiles();
      await _staging.rename(target.path);
    } finally {
      await _validateFiles();
      if (await _staging.exists()) await _staging.delete();
    }
  }

  Future<void> close() async {
    await _restoring;
    try {
      await _pending;
    } on Object {
      /* caller has the original error */
    }
    _lease?.release();
    _lease = null;
    super.dispose();
  }
}

/// Holds a saved downloaded model's place while startup verification runs.
final class _VerifyingModel implements GeneralLlmBackend, ModelContextProbe {
  const _VerifyingModel();
  @override
  Future<LlmAvailability> availability() async => const ModelLoading();
  @override
  Stream<String> generateGeneral({required String prompt}) =>
      Stream.error(StateError('The model is still being checked'));
  @override
  Future<int> contextWindowSize() =>
      Future.error(StateError('Model is being checked'));
  @override
  Future<int> countInstructionTokens(String text) =>
      Future.error(StateError('Model is being checked'));
  @override
  Future<int> countPromptTokens(String text) =>
      Future.error(StateError('Model is being checked'));
}

final class _UnavailableModel implements GeneralLlmBackend, ModelContextProbe {
  const _UnavailableModel();
  @override
  Future<LlmAvailability> availability() async => const ModelNotReady();
  @override
  Stream<String> generateGeneral({required String prompt}) =>
      Stream.error(StateError('Choose an available model'));
  @override
  Future<int> contextWindowSize() =>
      Future.error(StateError('Model unavailable'));
  @override
  Future<int> countInstructionTokens(String text) =>
      Future.error(StateError('Model unavailable'));
  @override
  Future<int> countPromptTokens(String text) =>
      Future.error(StateError('Model unavailable'));
}

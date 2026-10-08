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
import 'model_store.dart';

/// One explicit, persisted choice; no automatic fallback on missing/corrupt
/// downloads, memory pressure, disabled Apple Intelligence or restarts.
final class ModelSelection extends ChangeNotifier {
  ModelSelection({
    required this.store,
    required this.engine,
    required this.apple,
  });
  final ModelStore store;
  final ChatEngine engine;
  final AppleFoundationModels apple;
  String _selected = ModelCatalogue.apple.id;
  String get selected => _selected;
  bool get hasLocalLease => _lease != null;
  bool _busy = false;
  bool get busy => _busy;
  ModelLease? _lease;
  Future<void>? _pending;
  File get _choice => File('${store.directory.path}/selected-model');
  File get _staging => File('${store.directory.path}/selection.partial');

  Future<void> _validateFiles() async {
    if (await FileSystemEntity.type(store.directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Invalid selection directory');
    }
    for (final file in [_choice, _staging]) {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.notFound) {
        throw StateError('Invalid selection file');
      }
    }
  }

  Future<void> restore() async {
    try {
      await _validateFiles();
      if (!await _choice.exists()) return;
      if (await _choice.length() > 100) throw StateError('Invalid selection');
      final id = await _choice.readAsString();
      if (!ModelCatalogue.entries.any((m) => m.id == id)) {
        throw StateError('Unknown selection');
      }
      await _select(id, persist: false);
    } on Object {
      _selected = 'unavailable';
      const unavailable = _UnavailableModel();
      await engine.switchModel(
        backend: unavailable,
        contextProbe: unavailable,
        model: const ModelSnapshot(identifier: 'unavailable', revision: 'none'),
      );
      notifyListeners();
    }
  }

  Future<void> select(String id) => _select(id, persist: true);

  Future<void> _select(String id, {required bool persist}) {
    if (_busy || engine.isGenerating) {
      return Future.error(StateError('Finish the current response first'));
    }
    if (!ModelCatalogue.entries.any((m) => m.id == id)) {
      return Future.error(StateError('Unreviewed model'));
    }
    _busy = true;
    notifyListeners();
    return _pending = () async {
      ModelLease? nextLease;
      try {
        final isApple = id == ModelCatalogue.apple.id;
        GeneralLlmBackend backend = apple;
        ModelContextProbe probe = apple;
        if (!isApple) {
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
                : ModelCatalogue.qwen.artifact!.revision,
            metadata: isApple
                ? const {}
                : {
                    'artifactSHA256': ModelCatalogue.qwen.artifact!.sha256,
                    'quantization': 'Q3_K_M',
                    'runtime': 'llama.cpp-b11429',
                    'context': 2048,
                    'outputCap': 256,
                    'template': 'chatml-general-json-v1',
                    'localInstructions': 'local-general-v1',
                  },
          ),
          outputTokens: isApple ? 512 : 256,
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

  Future<void> _persist(String id) async {
    await _validateFiles();
    try {
      await _staging.writeAsString(id, flush: true);
      await store.policy.prepare(store.directory);
      await _validateFiles();
      await _staging.rename(_choice.path);
    } finally {
      await _validateFiles();
      if (await _staging.exists()) await _staging.delete();
    }
  }

  Future<void> close() async {
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

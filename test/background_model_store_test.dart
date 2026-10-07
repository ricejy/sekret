import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/models/background_model_download.dart';
import 'package:sekret/core/models/model_catalogue.dart';
import 'package:sekret/core/models/model_download.dart';
import 'package:sekret/core/models/model_store.dart';
import 'model_store_test.dart' show fixture, payload, Policy;

class _Background implements BackgroundModelDownload {
  bool pending = false;
  int starts = 0;
  int cancellations = 0;
  Completer<void>? gate;
  List<int> bytes = payload;
  @override
  Future<bool> hasPending() async => pending;
  @override
  Future<void> cancel() async {
    cancellations++;
    pending = false;
  }

  @override
  Future<void> transfer({
    required ModelArtifact artifact,
    required File destination,
    required ModelCancellation cancel,
    required void Function(int) onProgress,
  }) async {
    starts++;
    pending = true;
    try {
      if (gate != null) await cancel.wait(gate!.future);
      if (!await destination.exists()) await destination.writeAsBytes(bytes);
      onProgress(bytes.length);
      pending = false;
    } on Object {
      await this.cancel();
      rethrow;
    }
  }
}

void main() {
  late Directory root;
  late _Background background;
  late ModelStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sekret-background-store-');
    background = _Background();
    store = ModelStore(
      directory: root,
      policy: Policy(),
      backgroundDownload: background,
      model: fixture,
    );
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  test(
    'startup preserves completed staging and verifies without redownload',
    () async {
      background.pending = true;
      await File('${root.path}/download.partial').writeAsBytes(payload);
      await store.initialize();
      for (
        var i = 0;
        i < 100 && store.state.phase != ModelInstallPhase.installed;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(store.state.phase, ModelInstallPhase.installed);
      // Wait for publication cleanup to finish before acquiring the lease.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final lease = store.acquire();
      expect(await File(lease.path).readAsBytes(), payload);
      lease.release();
      expect(background.starts, 1);
    },
  );

  test(
    'startup reattaches without blocking the app and Cancel fences native work',
    () async {
      background.pending = true;
      background.gate = Completer<void>();
      await store.initialize().timeout(const Duration(seconds: 1));
      for (var i = 0; i < 100 && background.starts == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(store.state.phase, ModelInstallPhase.downloading);
      await store.cancel();
      expect(background.cancellations, 1);
      expect(store.state.phase, ModelInstallPhase.failed);
      expect(await root.list().toList(), isEmpty);
    },
  );

  test(
    'native completion cannot publish wrong hash or oversized bytes',
    () async {
      for (final corrupt in [
        [4, 3, 2, 1],
        [1, 2, 3, 4, 5],
      ]) {
        background.bytes = corrupt;
        if (!store.initialized) await store.initialize();
        await expectLater(store.install(), throwsException);
        expect(store.acquire, throwsStateError);
        expect(await root.list().toList(), isEmpty);
      }
    },
  );
}

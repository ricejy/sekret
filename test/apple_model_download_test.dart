import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/models/model_download.dart';
import 'package:sekret/core/platform/apple_model_download.dart';
import 'model_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/background-model');
  const transfer = AppleModelDownload(
    channel: channel,
    pollInterval: Duration.zero,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'reattaches to existing work and forwards progress before verification',
    () async {
      var polls = 0;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'hasPending') return true;
        if (call.method == 'start') {
          expect((call.arguments as Map)['sha256'], fixture.artifact!.sha256);
        }
        if (call.method == 'status') {
          polls++;
          return {
            'phase': polls == 1 ? 'downloading' : 'complete',
            'bytes': polls == 1 ? 2 : 4,
          };
        }
        return null;
      });
      expect(await transfer.hasPending(), true);
      final progress = <int>[];
      await transfer.transfer(
        artifact: fixture.artifact!,
        destination: File('/fixture/download.partial'),
        cancel: ModelCancellation(),
        onProgress: progress.add,
      );
      expect(progress, [2, 4]);
      expect(calls, ['hasPending', 'start', 'status', 'status']);
    },
  );

  test('cancellation waits for Start admission then native cleanup', () async {
    final started = Completer<void>();
    final admission = Completer<void>();
    final cleanup = Completer<void>();
    final cancel = ModelCancellation();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'start') {
        started.complete();
        await admission.future;
      }
      if (call.method == 'cancel') await cleanup.future;
      return null;
    });
    var finished = false;
    final pending = transfer.transfer(
      artifact: fixture.artifact!,
      destination: File('/fixture/download.partial'),
      cancel: cancel,
      onProgress: (_) {},
    );
    final assertion = expectLater(
      pending.whenComplete(() => finished = true),
      throwsA(isA<ModelOperationCancelled>()),
    );
    await started.future;
    cancel.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start']);
    admission.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start', 'cancel']);
    expect(finished, false);
    cleanup.complete();
    await assertion;
  });

  test(
    'invalid progress and failed native transfer cancel before returning',
    () async {
      for (final state in [
        {'phase': 'downloading', 'bytes': 5},
        {'phase': 'failed', 'bytes': 2},
      ]) {
        var cancelled = false;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'status') return state;
          if (call.method == 'cancel') cancelled = true;
          return null;
        });
        await expectLater(
          transfer.transfer(
            artifact: fixture.artifact!,
            destination: File('/fixture/download.partial'),
            cancel: ModelCancellation(),
            onProgress: (_) {},
          ),
          throwsException,
        );
        expect(cancelled, true);
      }
    },
  );
}

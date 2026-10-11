// Isolated resource diagnostic: matched idle/workload windows for the memory
// protocol in docs/evaluation/model-ratings/scale-v1.md, then photo device
// acceptance (docs/product/photo-understanding-scope.md). Fictional inputs
// only; never opens the personal database or changes the saved model choice.
// Launch with --sekret-model-rating-eval so native diagnostics are available
// and the screen stays awake. Whole-device memory comes from Instruments
// traces recorded on the Mac and aligned with the UTC timestamps here.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import '../core/models/model_catalogue.dart';
import '../core/platform/apple_foundation_models.dart';
import '../core/platform/local_model_backend.dart';
import '../core/platform/llm_backend.dart';

const _fixture = String.fromEnvironment('RESOURCE_FIXTURE');
const _phases = String.fromEnvironment(
  'RESOURCE_PHASES',
  defaultValue: 'apple,qwen,photo',
);
const _idle = Duration(seconds: 120);
const _rest = Duration(seconds: 10);

/// Fictional brand artwork prepared on the Mac and copied into Documents.
const _photos = [
  (
    file: 'photo-fixtures/landscape.jpg',
    question: 'What animal is shown?',
    expect: 'turtle',
  ),
  (
    file: 'photo-fixtures/rotated.heic',
    question:
        'Is the turtle in this image upright, lying on its side, or upside down?',
    expect: 'upright',
  ),
  (
    file: 'photo-fixtures/small.png',
    question: 'What colour is the turtle?',
    expect: 'teal/green/blue',
  ),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const CupertinoApp(
      theme: CupertinoThemeData(brightness: Brightness.dark),
      home: _Run(),
    ),
  );
}

class _Run extends StatefulWidget {
  const _Run();
  @override
  State<_Run> createState() => _RunState();
}

class _RunState extends State<_Run> with WidgetsBindingObserver {
  String status = 'Preparing resource measurement…';
  final events = <Map<String, Object?>>[];
  final lifecycle = <Map<String, Object?>>[];
  Completer<void>? _paused;
  Completer<void>? _resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    lifecycle.add({'at': _now(), 'state': state.name});
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!(_paused?.isCompleted ?? true)) _paused!.complete();
    }
    if (state == AppLifecycleState.resumed) {
      if (!(_resumed?.isCompleted ?? true)) _resumed!.complete();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  void _show(String text) {
    if (mounted) setState(() => status = text);
  }

  Future<Map<String, Object?>> _resources() async => Map<String, Object?>.from(
    (await localModelChannel.invokeMapMethod<String, Object?>(
      'diagnosticState',
    ))!,
  );

  Future<void> _run() async {
    final docs = await getApplicationDocumentsDirectory();
    final file = File('${docs.path}/resource-measurement.json');
    final fixtureBytes = base64Decode(_fixture);
    final fixture = jsonDecode(utf8.decode(fixtureBytes)) as Map;
    final report = <String, Object?>{
      'schema': 'sekret-resource-measurement-v1',
      'fixture': fixture['version'],
      'fixtureSHA256': sha256.convert(fixtureBytes).toString(),
      'instructionsSHA256': sha256
          .convert(utf8.encode(generalInstructions))
          .toString(),
      'qwenSHA256': ModelCatalogue.qwen.artifact!.sha256,
      'qwenRuntime': 'llama.cpp-b11429',
      'applePromptVersion': 'general-v4',
      'os': Platform.operatingSystemVersion,
      'startedAt': _now(),
      'idleSeconds': _idle.inSeconds,
      'requestedPhases': _phases,
      'restSeconds': _rest.inSeconds,
      'phases': <Object?>[],
      'events': events,
      'lifecycle': lifecycle,
      'complete': false,
    };
    final phases = report['phases']! as List;
    Future<void> save() => file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    // Samples memory/thermals every two seconds for the whole run.
    final samples = <Object?>[];
    report['samples'] = samples;
    final sampler = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final r = await _resources();
        samples.add({
          'at': _now(),
          'thermal': r['thermalState'],
          'footprint': r['physFootprintBytes'],
          'available': r['availableMemoryBytes'],
          'onBattery': r['onBattery'],
        });
      } on Object {
        /* Sampling is best effort. */
      }
    });
    Future<void> phase(String name, Future<void> Function() body) async {
      final entry = <String, Object?>{'name': name, 'start': _now()};
      phases.add(entry);
      report['currentPhase'] = name;
      await save();
      try {
        await body();
      } finally {
        entry['end'] = _now();
        await save();
      }
    }

    Future<void> idle(String name) => phase(name, () async {
      _show('Idle baseline · $name\nKeep Sekret open.');
      await Future<void>.delayed(_idle);
    });

    try {
      final support = await getApplicationSupportDirectory();
      final path =
          '${support.path}/reviewed-models/${ModelCatalogue.qwen.artifact!.sha256}.gguf';
      if (!await File(path).exists()) {
        throw StateError('Reviewed download missing');
      }
      final apple = AppleFoundationModels();
      final qwen = LocalModelBackend(path: path);
      final cases = (fixture['cases'] as List).cast<Map>();
      report['initialResources'] = await _resources();
      // Start unplugged and nominal: charging heat stopped the first attempt.
      final ready = Stopwatch()..start();
      while (_phases != 'interrupt') {
        final r = await _resources();
        report['startResources'] = r;
        if (r['onBattery'] == true && r['thermalState'] == 0) break;
        if (ready.elapsed > const Duration(minutes: 30)) {
          throw StateError('Start readiness timeout');
        }
        _show(
          r['onBattery'] != true
              ? 'Unplug the phone and leave Sekret open.\nMeasurement starts once it is cool.'
              : 'Waiting for the phone to cool…\nKeep Sekret open.',
        );
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      report['startWaitSeconds'] = ready.elapsed.inSeconds;
      final run = _phases.split(',').toSet();

      Future<void> workload(String id) async {
        final backend = id == 'apple' ? apple : qwen as GeneralLlmBackend;
        for (var i = 0; i < cases.length; i++) {
          final item = cases[i];
          // Production admission: wait (excluded) while serious/critical.
          var before = await _resources();
          final waited = Stopwatch()..start();
          while (before['ready'] != true ||
              (before['thermalState'] as int? ?? 3) >= 2) {
            if (waited.elapsed > const Duration(minutes: 20)) {
              throw StateError('Cooling pause timeout');
            }
            _show('Cooling pause…\nKeep Sekret open.');
            await Future<void>.delayed(const Duration(seconds: 5));
            before = await _resources();
          }
          if (waited.elapsed > const Duration(seconds: 1)) {
            events.add({
              'type': 'coolingPause',
              'model': id,
              'beforeCase': item['id'],
              'seconds': waited.elapsedMilliseconds / 1000,
            });
          }
          if (await backend.availability() is! Available) {
            throw StateError('$id unavailable');
          }
          _show('$id · ${i + 1}/${cases.length}');
          final prompt = buildGeneralChatPrompt({
            'context_summary': null,
            'recent_turns': [
              for (final turn
                  in (item['turns'] as List? ?? const []).cast<Map>())
                {
                  'user': turn['user'],
                  'assistant': turn['assistant'],
                  'outcome': 'completed',
                },
            ],
            'current_user_message': item['prompt'],
          });
          final row = <String, Object?>{
            'type': 'general',
            'model': id,
            'id': item['id'],
            'start': _now(),
            'thermalBefore': before['thermalState'],
            'completed': false,
          };
          events.add(row);
          final watch = Stopwatch()..start();
          try {
            await for (final _
                in backend
                    .generateGeneral(prompt: prompt)
                    .timeout(const Duration(seconds: 90))) {}
            row['completed'] = true;
          } on Object catch (error) {
            row['error'] = error is LlmException
                ? error.code.name
                : error.runtimeType.toString();
          } finally {
            if (id == 'qwen') await qwen.finishTurn();
            row['elapsedMs'] = watch.elapsedMilliseconds;
            row['end'] = _now();
            row['thermalAfter'] = (await _resources())['thermalState'];
            await save();
          }
          await Future<void>.delayed(_rest);
        }
      }

      if (run.contains('apple')) {
        await idle('idle-before-apple');
        await phase('apple-general', () => workload('apple'));
      }
      if (run.contains('qwen')) {
        await idle('idle-before-qwen');
        await phase('qwen-general', () => workload('qwen'));
      }
      if (!run.contains('photo') && !run.contains('interrupt')) {
        report['complete'] = true;
        _show('Measurement complete.');
        return;
      }
      final full = _phases != 'interrupt';
      if (full) await idle('idle-before-photo');

      // Photo device acceptance (Apple only; Qwen is text only).
      report['photoSupported'] = await apple.supportsPhotoQuestions();
      final photos = {
        for (final p in _photos)
          p.file: await File('${docs.path}/${p.file}').readAsBytes(),
      };
      Future<Map<String, Object?>> ask(
        ({String file, String question, String expect}) p, {
        String type = 'photo',
        bool Function(int snapshots)? cancelAfter,
        Future<void>? stopWhen,
      }) async {
        final row = <String, Object?>{
          'type': type,
          'file': p.file,
          'bytes': photos[p.file]!.length,
          'question': p.question,
          'expect': p.expect,
          'start': _now(),
          'thermalBefore': (await _resources())['thermalState'],
          'output': '',
          'completed': false,
        };
        events.add(row);
        final watch = Stopwatch()..start();
        final done = Completer<void>();
        var snapshots = 0;
        late final StreamSubscription<String> sub;
        sub = apple
            .answerAboutPhoto(photo: photos[p.file]!, question: p.question)
            .listen(
              (text) {
                snapshots++;
                row['output'] = text;
                row['firstSnapshotMs'] ??= watch.elapsedMilliseconds;
                if (cancelAfter?.call(snapshots) ?? false) {
                  row['cancelledAfterSnapshots'] = snapshots;
                  unawaited(sub.cancel());
                  if (!done.isCompleted) done.complete();
                }
              },
              onError: (Object error) {
                row['error'] = error is LlmException
                    ? error.code.name
                    : error.runtimeType.toString();
                if (!done.isCompleted) done.complete();
              },
              onDone: () {
                row['completed'] = true;
                if (!done.isCompleted) done.complete();
              },
            );
        if (cancelAfter?.call(0) ?? false) {
          row['cancelledAfterSnapshots'] = 0;
          await sub.cancel();
          if (!done.isCompleted) done.complete();
        }
        unawaited(
          stopWhen?.then((_) {
            row['interruptedAt'] = _now();
          }),
        );
        await done.future.timeout(
          const Duration(seconds: 120),
          onTimeout: () {
            row['error'] = 'timeout';
            unawaited(sub.cancel());
          },
        );
        row['elapsedMs'] = watch.elapsedMilliseconds;
        row['end'] = _now();
        row['thermalAfter'] = (await _resources())['thermalState'];
        await save();
        return row;
      }

      if (full) {
        await phase('photo-repeated', () async {
          for (var round = 0; round < 3; round++) {
            for (final p in _photos) {
              _show('Photo · round ${round + 1}/3');
              await ask(p);
              await Future<void>.delayed(_rest);
            }
          }
        });
      }
      if (full) {
        await phase('photo-cancellation', () async {
          _show('Photo · cancellation');
          // Cancel while the large photo is still being prepared.
          await ask(
            _photos[0],
            type: 'cancel-preparation',
            cancelAfter: (n) => n == 0,
          );
          await Future<void>.delayed(const Duration(seconds: 3));
          await ask(
            _photos[0],
            type: 'cancel-generation',
            cancelAfter: (n) => n >= 1,
          );
          await Future<void>.delayed(const Duration(seconds: 3));
          await ask(_photos[2], type: 'after-cancel');
        });
      }
      await phase('photo-interruption', () async {
        _paused = Completer<void>();
        _resumed = Completer<void>();
        _show('Photo · waiting for a background interruption');
        report['awaitingInterruption'] = true;
        await save();
        // Keep a photo answer in flight until the interruption lands in one.
        final waiting = Stopwatch()..start();
        while (!_paused!.isCompleted) {
          if (waiting.elapsed > const Duration(minutes: 5)) {
            throw StateError('No interruption');
          }
          await ask(
            _photos[0],
            type: 'background-interruption',
            stopWhen: _paused!.future,
          );
        }
        report['awaitingInterruption'] = false;
        await _resumed!.future.timeout(const Duration(minutes: 5));
        await Future<void>.delayed(const Duration(seconds: 2));
        await ask(_photos[1], type: 'after-resume');
      });
      report['complete'] = true;
      _show('Measurement complete.');
    } on Object catch (error) {
      report['stopped'] = error.toString();
      _show('Measurement stopped: $error');
    } finally {
      sampler.cancel();
      report['finishedAt'] = _now();
      report['currentPhase'] = 'done';
      await save();
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: CupertinoColors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(status, textAlign: TextAlign.center),
      ),
    ),
  );
}

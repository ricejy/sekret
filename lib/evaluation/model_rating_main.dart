// Explicit diagnostic entrypoint. Never imported by the production application.
// Uses only supplied fictional fixtures; does not open the user's database or
// modify the persisted model choice. Existing reviewed weights are read-only.
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
import '../core/platform/token_counter.dart';

const _fixture = String.fromEnvironment('MODEL_RATING_FIXTURE');

/// Development v1 and the held-out v2 set; each writes its own report.
const _reports = {
  'sekret-broader-text-development-v1': 'model-ratings-v1.json',
  'sekret-broader-text-heldout-v2': 'model-ratings-heldout-v2.json',
};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const CupertinoApp(
      theme: CupertinoThemeData(brightness: Brightness.dark),
      home: _RatingRun(),
    ),
  );
}

class _RatingRun extends StatefulWidget {
  const _RatingRun();
  @override
  State<_RatingRun> createState() => _RatingRunState();
}

class _RatingRunState extends State<_RatingRun> with WidgetsBindingObserver {
  String status = 'Preparing fictional model comparison…';
  bool interrupted = false;
  final rows = <Map<String, Object?>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      interrupted = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _run() async {
    final docs = await getApplicationDocumentsDirectory();
    final fixture = jsonDecode(utf8.decode(base64Decode(_fixture))) as Map;
    final reportName =
        _reports[fixture['version']] ?? 'model-ratings-rejected.json';
    final file = File('${docs.path}/$reportName');
    final report = <String, Object?>{
      'schema': 'sekret-model-ratings-v1',
      'fixture': fixture['version'],
      'fixtureSHA256': sha256.convert(base64Decode(_fixture)).toString(),
      'instructionsSHA256': sha256
          .convert(utf8.encode(generalInstructions))
          .toString(),
      'qwenSHA256': ModelCatalogue.qwen.artifact!.sha256,
      'qwenRevision': ModelCatalogue.qwen.artifact!.revision,
      'qwenRuntime': 'llama.cpp-b11429',
      'applePromptVersion': 'general-v4',
      'timing': 'native-preparation-and-generation-excludes-database-and-ui',
      'os': Platform.operatingSystemVersion,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'complete': false,
      'protocol': 'paced-v4-unplugged-nominal-start-dark-screen',
      'restSeconds': 10,
      'display': 'dark-diagnostic-screen-system-brightness-unchanged',
      'results': rows,
    };
    Future<Map<String, Object?>> resources() async => Map<String, Object?>.from(
      (await localModelChannel.invokeMapMethod<String, Object?>(
        'diagnosticState',
      ))!,
    );
    Future<void> save() => file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    try {
      if (!_reports.containsKey(fixture['version'])) {
        throw StateError('Wrong fixture');
      }
      final support = await getApplicationSupportDirectory();
      final path =
          '${support.path}/reviewed-models/${ModelCatalogue.qwen.artifact!.sha256}.gguf';
      if (!await File(path).exists()) {
        throw StateError('Reviewed download missing');
      }
      final apple = AppleFoundationModels();
      final qwen = LocalModelBackend(path: path);
      final cases = (fixture['cases'] as List).cast<Map>();
      // A distinct paced run; the initial burst report is preserved separately.
      // Owner-requested cooler unplugged comparison; keep all production guards.
      for (var attempt = 0; ; attempt++) {
        final state = await resources();
        report['initialReadiness'] = state;
        await save();
        if (state['ready'] == true &&
            state['thermalState'] == 0 &&
            state['onBattery'] == true) {
          break;
        }
        if (interrupted || attempt >= 240) {
          throw StateError('Readiness timeout');
        }
        if (mounted) {
          setState(
            () => status = state['onBattery'] != true
                ? 'Unplug the phone and leave Sekret open.\nThe comparison starts after cooling.'
                : 'Waiting for the phone to cool…\nKeep Sekret open.',
          );
        }
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      for (var i = 0; i < cases.length; i++) {
        final item = cases[i];
        for (final id in i.isEven ? ['apple', 'qwen'] : ['qwen', 'apple']) {
          if (interrupted) throw StateError('Interrupted');
          final before = await resources();
          report['latestReadiness'] = before;
          if (before['onBattery'] != true) {
            throw StateError('Power connection changed');
          }
          final backend = id == 'apple' ? apple : qwen as GeneralLlmBackend;
          final probe = backend as ModelContextProbe;
          if (await backend.availability() is! Available) {
            throw StateError('$id unavailable');
          }
          if (mounted) {
            setState(() => status = '$id · ${i + 1}/${cases.length}');
          }
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
          final watch = Stopwatch()..start();
          final row = <String, Object?>{
            'id': item['id'],
            'model': id,
            'outputCap': id == 'apple' ? 512 : 256,
            'resourcesBefore': before,
            'output': '',
            'completed': false,
          };
          rows.add(row);
          try {
            final instructions = await probe.countInstructionTokens(
              generalInstructions,
            );
            final tokens = await probe.countPromptTokens(prompt);
            row['inputTokens'] = instructions + tokens;
            row['preparationMs'] = watch.elapsedMilliseconds;
            var output = '';
            await for (final snapshot
                in backend
                    .generateGeneral(prompt: prompt)
                    .timeout(const Duration(seconds: 90))) {
              output = snapshot;
              row['output'] = output;
              row['firstSnapshotMs'] ??= watch.elapsedMilliseconds;
            }
            row['completed'] = true;
            row['elapsedMs'] = watch.elapsedMilliseconds;
          } on Object catch (error) {
            row['error'] = error.runtimeType.toString();
            if (error is LlmException) row['errorCode'] = error.code.name;
            row['elapsedMs'] = watch.elapsedMilliseconds;
          } finally {
            if (id == 'qwen') await qwen.finishTurn();
            row['resourcesAfter'] = await resources();
            await save();
          }
          await Future<void>.delayed(const Duration(seconds: 10));
        }
      }
      report['complete'] = !interrupted && rows.length == cases.length * 2;
      if (mounted) {
        setState(
          () => status =
              'Comparison complete.\nReconnect the phone to collect results.',
        );
      }
    } on Object catch (error) {
      report['stopped'] = error.toString();
      if (mounted) {
        setState(
          () => status =
              'Comparison stopped: $error\nReconnect the phone to collect results.',
        );
      }
    } finally {
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

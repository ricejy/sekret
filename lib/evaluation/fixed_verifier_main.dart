// Isolated, auto-running fictional benchmark. Never opens the regular vault.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

import '../core/platform/apple_foundation_models.dart';
import '../core/platform/llm_backend.dart';
import 'fixed_verifier_benchmark.dart';

const _fixture = String.fromEnvironment('FIXED_VERIFIER_SUITE_BASE64');
const _manifest = String.fromEnvironment('EVALUATION_SOURCE_MANIFEST');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CupertinoApp(home: _Benchmark()));
}

class _Benchmark extends StatefulWidget {
  const _Benchmark();
  @override
  State<_Benchmark> createState() => _BenchmarkState();
}

class _BenchmarkState extends State<_Benchmark> with WidgetsBindingObserver {
  bool interrupted = false;
  bool finished = false;
  StreamIterator<String>? active;
  String status = 'Preparing fixed-answer verifier benchmark…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!finished &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      interrupted = true;
      unawaited(active?.cancel());
    }
  }

  @override
  void dispose() {
    interrupted = true;
    unawaited(active?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _run() async {
    Directory? directory;
    final rows = <Map<String, dynamic>>[];
    final report = <String, Object?>{
      'schemaVersion': 1,
      'purpose': fixedVerifierPurpose,
      'fictional': true,
      'complete': false,
      'runtime': Platform.operatingSystemVersion,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'verifierVersion': groundedVerificationVersion,
      'instructions': groundedVerificationInstructions,
      'generationEvaluated': false,
      'retrievalEvaluated': false,
      'resourceMeasurement': 'Memory, energy and thermal impact not measured.',
      'results': rows,
    };
    Future<void> save(String name) async {
      if (directory != null) {
        await File('${directory.path}/$name.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
      }
    }

    try {
      final text = utf8.decode(base64Decode(_fixture));
      final suite = decodeFixedVerifierSuite(text);
      final cases = fixedVerifierCases(suite);
      final plan = fixedVerifierPlan(cases);
      report['suiteID'] = suite['suiteID'];
      report['fixtureSha256'] = sha256.convert(utf8.encode(text)).toString();
      report['sourceManifest'] = jsonDecode(_manifest);
      report['plannedTrials'] = plan.length;
      final documents = await getApplicationDocumentsDirectory();
      final exports = await Directory(
        '${documents.path}/fixed-verifier-evaluation',
      ).create(recursive: true);
      directory = await exports.createTemp('run-');
      final native = AppleFoundationModels();
      if (await native.availability() is! Available) {
        throw StateError('Model unavailable');
      }
      final window = await native.contextWindowSize();
      final instructionTokens = await native.countInstructionTokens(
        groundedVerificationInstructions,
      );
      report['contextSize'] = window;
      report['instructionTokens'] = instructionTokens;
      for (final trial in plan) {
        if (interrupted) throw StateError('Interrupted');
        final prompt = fixedVerifierPrompt(trial.row);
        final tokens = await native.countPromptTokens(prompt);
        if (tokens +
                instructionTokens +
                groundedVerificationOutputTokens +
                128 >
            window) {
          throw StateError('Context overflow: never truncate a fixed input');
        }
        String output = '';
        String? failure;
        final watch = Stopwatch()..start();
        try {
          active = StreamIterator(native.verifyGrounded(prompt: prompt));
          while (true) {
            final remaining = const Duration(seconds: 30) - watch.elapsed;
            if (remaining <= Duration.zero) throw TimeoutException('Deadline');
            if (!await active!.moveNext().timeout(remaining)) break;
            output = active!.current;
          }
          if (interrupted) throw StateError('Interrupted');
          parseGroundedVerification(output);
        } on LlmException catch (e) {
          failure = e.code.name;
        } on TimeoutException {
          failure = 'timeout';
        } finally {
          watch.stop();
          await active?.cancel();
          active = null;
        }
        rows.add({
          'caseID': trial.row['id'],
          'repeat': trial.repeat,
          'prompt': prompt,
          'output': output,
          'failure': failure,
          'latencyMs': watch.elapsedMilliseconds,
          'promptTokens': tokens,
        });
        report['grades'] = gradeFixedVerifier(cases, rows);
        await save('progress');
        if (mounted) {
          setState(
            () => status = '${rows.length}/${plan.length} checks recorded.',
          );
        }
      }
      if (interrupted) throw StateError('Interrupted');
      report['complete'] = true;
    } on Object {
      report['error'] = interrupted
          ? 'interrupted'
          : 'setup-or-evaluation-failure';
    } finally {
      finished = true;
      report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
      await save('result');
      if (mounted) {
        setState(
          () => status = report['complete'] == true
              ? 'Complete. Fixed answers checked; not a release pass.'
              : 'Incomplete. No pass recorded.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TEST DATA — fixed-answer verification'),
            const SizedBox(height: 20),
            const Text(
              'Fictional development only. No answer generation, retrieval, or vault access. Keep this screen open.',
            ),
            const SizedBox(height: 20),
            Text(status),
          ],
        ),
      ),
    ),
  );
}

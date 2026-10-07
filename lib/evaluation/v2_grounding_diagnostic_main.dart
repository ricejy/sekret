// Fictional development diagnostics only. Never imported by production.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

import '../core/platform/apple_foundation_models.dart';
import '../core/platform/llm_backend.dart';

const _suite = String.fromEnvironment('DEVELOPMENT_SUITE_BASE64');
const _capture = String.fromEnvironment('DEVELOPMENT_CAPTURE_BASE64');
const _manifest = String.fromEnvironment(
  'EVALUATION_SOURCE_MANIFEST',
  defaultValue: '{}',
);
const _ids = {'LEG-A09', 'LEG-U03', 'MED-A19', 'MED-A20', 'LEG-A03', 'LEG-U01'};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CupertinoApp(home: _Diagnostic()));
}

class _Diagnostic extends StatefulWidget {
  const _Diagnostic();
  @override
  State<_Diagnostic> createState() => _DiagnosticState();
}

class _DiagnosticState extends State<_Diagnostic> with WidgetsBindingObserver {
  bool interrupted = false;
  bool finished = false;
  String status = 'Preparing fictional grounding comparison…';

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
    }
  }

  @override
  void dispose() {
    interrupted = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _run() async {
    Directory? directory;
    final rows = <Map<String, Object?>>[];
    final report = <String, Object?>{
      'purpose': 'fictional-development-grounding-diagnostic-not-acceptance',
      'fictional': true,
      'complete': false,
      'runtime': Platform.operatingSystemVersion,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'sourceManifest': jsonDecode(_manifest),
      'groundedPromptVersion': groundedPromptVersion,
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
      final suiteText = utf8.decode(base64Decode(_suite));
      final captureText = utf8.decode(base64Decode(_capture));
      final suite = jsonDecode(suiteText) as Map;
      final capture = jsonDecode(captureText) as Map;
      if (suite['fictional'] != true ||
          suite['purpose'] != 'development' ||
          capture['fictional'] != true ||
          capture['purpose'] != 'v2-engine-development-not-acceptance' ||
          capture['suiteID'] != suite['suiteID']) {
        throw StateError('Development inputs only');
      }
      report['fixtureSha256'] = sha256
          .convert(utf8.encode(suiteText))
          .toString();
      report['captureSha256'] = sha256
          .convert(utf8.encode(captureText))
          .toString();
      final documents = await getApplicationDocumentsDirectory();
      final exports = await Directory(
        '${documents.path}/v2-grounding-diagnostic',
      ).create(recursive: true);
      directory = await exports.createTemp('run-');
      final native = AppleFoundationModels();
      if (await native.availability() is! Available) {
        throw StateError('Model unavailable');
      }
      final window = await native.contextWindowSize();
      final instructionTokens = {
        'v1': await native.countInstructionTokens(guardrailV1Instructions),
        'v3': await native.countInstructionTokens(groundedChatInstructions),
      };
      Future<void> call(
        String id,
        String variant,
        String mode,
        String prompt,
        String question,
        List<String> evidence,
        int repeat,
      ) async {
        if (interrupted) throw StateError('Interrupted');
        final tokens = await native.countPromptTokens(prompt);
        if (tokens + instructionTokens[mode]! + 640 > window) {
          throw StateError('Context overflow');
        }
        String output = '';
        String? failure;
        final watch = Stopwatch()..start();
        try {
          final stream = mode == 'v1'
              ? native.generate(
                  question: question,
                  evidence: evidence,
                  prompt: prompt,
                )
              : native.generateGrounded(prompt: prompt);
          await for (final snapshot in stream.timeout(
            const Duration(seconds: 60),
          )) {
            output = snapshot;
          }
        } on LlmException catch (e) {
          failure = e.code.name;
        } on TimeoutException {
          failure = 'timeout';
        }
        rows.add({
          'caseID': id,
          'variant': variant,
          'repeat': repeat,
          'mode': mode,
          'question': question,
          'prompt': prompt,
          'output': output,
          'failure': failure,
          'latencyMs': watch.elapsedMilliseconds,
          'promptTokens': tokens,
        });
        await save('progress');
        if (mounted) {
          setState(
            () => status = '${rows.length} fictional responses recorded.',
          );
        }
      }

      for (final row in (capture['results'] as List).cast<Map>().where(
        (r) => _ids.contains(r['caseID']),
      )) {
        final id = row['caseID'] as String;
        final question = row['question'] as String;
        final passages = (row['evidence'] as List).cast<Map>();
        final evidence = passages.map((p) => p['text'] as String).toList();
        String framed(List<Map> selected, String question) =>
            buildGroundedChatPrompt(
              question: question,
              conversationContext: {
                'context_summary': null,
                'recent_turns': [],
              },
              evidence: [
                for (final p in selected)
                  (
                    sourceId: p['source'] as String,
                    sourceTitle:
                        ((suite['excerpts'] as List).cast<Map>().singleWhere(
                              (e) => e['id'] == p['source'],
                            ))['title']
                            as String,
                    page: null,
                    section: p['heading'] as String,
                    text: p['text'] as String,
                  ),
              ],
            );
        final metadata = framed(passages, question);
        final plain = buildGuardrailV1Prompt(
          question: question,
          evidence: evidence,
        );
        final variants = [
          ('v3-metadata', 'v3', metadata),
          ('v3-plain', 'v3', plain),
          ('v1-metadata', 'v1', metadata),
          ('v1-plain', 'v1', plain),
          ('v3-first-passage', 'v3', framed([passages.first], question)),
        ];
        for (var repeat = 1; repeat <= 2; repeat++) {
          for (final (variant, mode, prompt)
              in repeat == 1 ? variants : variants.reversed) {
            await call(id, variant, mode, prompt, question, evidence, repeat);
          }
        }
        if (id == 'LEG-U03') {
          const neutral =
              'Does the excerpt establish that Elena actually contacted a regulator?';
          for (var repeat = 1; repeat <= 3; repeat++) {
            await call(
              id,
              'v3-neutral-question',
              'v3',
              framed(passages, neutral),
              neutral,
              evidence,
              repeat,
            );
          }
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
              ? 'Comparison complete. Fictional results exported; not a release pass.'
              : 'Comparison incomplete. No pass recorded.',
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
            const Text(
              'TEST DATA — grounding diagnosis. Keep this screen open.',
            ),
            const SizedBox(height: 24),
            Text(status),
          ],
        ),
      ),
    ),
  );
}

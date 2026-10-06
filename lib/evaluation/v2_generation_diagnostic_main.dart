import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

import '../core/chat/chat_engine.dart';
import '../core/chat/chat_workspace.dart';
import '../core/knowledge/knowledge_base.dart';
import '../core/platform/apple_embedder.dart';
import '../core/platform/apple_foundation_models.dart';
import '../core/platform/llm_backend.dart';
import '../core/storage/local_data_vault.dart';

// Diagnostic-only, never imported by production. No acceptance-suite tuning.
const _fixtureBase64 = String.fromEnvironment('DEVELOPMENT_SUITE_BASE64');
const _manifestJson = String.fromEnvironment(
  'EVALUATION_SOURCE_MANIFEST',
  defaultValue: '{}',
);
const _caseIds = {'LEG-A08', 'MED-A04'};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CupertinoApp(home: _Diagnostic()));
}

final class _Capture implements GeneralLlmBackend, GroundedLlmBackend {
  _Capture(this.native);
  @override
  Stream<String> verifyGrounded({required String prompt}) =>
      native.verifyGrounded(prompt: prompt);
  final AppleFoundationModels native;
  String prompt = '';
  String output = '';
  @override
  Future<LlmAvailability> availability() => native.availability();
  @override
  Stream<String> generateGeneral({required String prompt}) =>
      native.generateGeneral(prompt: prompt);
  @override
  Stream<String> generateGrounded({required String prompt}) async* {
    this.prompt = prompt;
    output = '';
    await for (final snapshot in native.generateGrounded(prompt: prompt)) {
      output = snapshot;
      yield snapshot;
    }
  }
}

class _Diagnostic extends StatefulWidget {
  const _Diagnostic();
  @override
  State<_Diagnostic> createState() => _DiagnosticState();
}

class _DiagnosticState extends State<_Diagnostic> with WidgetsBindingObserver {
  String status = 'Preparing development-fixture comparison…';
  bool interrupted = false;
  bool finished = false;
  ChatEngine? engine;
  final rows = <Map<String, Object?>>[];

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
      unawaited(engine?.suspend());
    }
  }

  @override
  void dispose() {
    interrupted = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _run() async {
    LocalDataVault? vault;
    KnowledgeBase? knowledge;
    ChatWorkspace? workspace;
    Directory? directory;
    final report = <String, Object?>{
      'schemaVersion': 1,
      'purpose':
          'development-fixture-generation-differential-diagnostic-not-acceptance',
      'fictional': true,
      'diagnosticStage': 'matched-passages-and-exact-general-pattern',
      'runtime': Platform.operatingSystemVersion,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'sourceManifest': jsonDecode(_manifestJson),
      'complete': false,
      'results': rows,
    };
    Future<void> save(String name) async {
      if (directory == null) return;
      await File('${directory.path}/$name.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
    }

    try {
      // Historical differential: its JSON variants require the original engine.
      // Run the full development evaluator for subsequent prompt versions.
      if (groundedPromptVersion != 'grounded-chat-v1') {
        throw StateError('Historical diagnostic requires grounded-chat-v1');
      }
      final text = utf8.decode(base64Decode(_fixtureBase64));
      final fixture = jsonDecode(text) as Map<String, dynamic>;
      if (fixture['fictional'] != true || fixture['purpose'] != 'development') {
        throw StateError('Development fixtures only');
      }
      report['fixtureHash'] = sha256.convert(utf8.encode(text)).toString();
      report['suiteID'] = fixture['suiteID'];
      final documents = await getApplicationDocumentsDirectory();
      final exports = await Directory(
        '${documents.path}/v2-generation-diagnostic',
      ).create(recursive: true);
      directory = await exports.createTemp('run-');
      final native = AppleFoundationModels();
      if (await native.availability() is! Available) {
        throw StateError('Unavailable');
      }
      vault = await openLocalDataVault(databasePath: ':memory:');
      workspace = await ChatWorkspace.open(vault);
      knowledge = await KnowledgeBase.open(
        vault: vault,
        embedder: AppleEmbedder(),
        tokenCounter: native,
      );
      final capture = _Capture(native);
      engine = ChatEngine(
        workspace: workspace,
        backend: capture,
        groundedBackend: capture,
        contextProbe: native,
        knowledgeBase: knowledge,
        model: ModelSnapshot(
          identifier: 'Apple Foundation Models',
          revision: Platform.operatingSystemVersion,
        ),
      );
      final excerpts = {
        for (final e in fixture['excerpts'] as List)
          e['id'] as String: e as Map<String, dynamic>,
      };
      final sourceIds = <String, String>{};
      for (final item
          in (fixture['cases'] as List).cast<Map<String, dynamic>>().where(
            (c) => _caseIds.contains(c['id']),
          )) {
        if (interrupted) throw StateError('Interrupted');
        final evidence = <String>[];
        final scope = <String>[];
        for (final excerptId in item['excerptIDs'] as List) {
          final excerpt = excerpts[excerptId]!;
          evidence.add(excerpt['text'] as String);
          if (!sourceIds.containsKey(excerptId)) {
            final imported = await knowledge.importText(
              title: excerpt['title'] as String,
              text: excerpt['text'] as String,
            );
            if ((await knowledge.process(imported.item.id)).processingState !=
                KnowledgeProcessingState.indexed) {
              throw StateError('Index failed');
            }
            sourceIds[excerptId as String] = imported.item.id;
          }
          scope.add(sourceIds[excerptId]!);
        }
        final question = item['question'] as String;
        capture.prompt = '';
        capture.output = '';
        final chat = await workspace.newChat();
        await workspace.changeScope(chat.id, ChatMode.knowledgeBase, scope);
        final watch = Stopwatch()..start();
        final timer = Timer(
          const Duration(seconds: 60),
          () => unawaited(engine!.stop()),
        );
        late ChatTurnResult baseline;
        try {
          baseline = await engine!.send(chatId: chat.id, text: question);
        } finally {
          timer.cancel();
        }
        if (capture.prompt.isEmpty) throw StateError('No actual engine prompt');
        final original = capture.prompt;
        rows.add({
          'caseID': item['id'],
          'variant': 'v2-engine',
          'repeat': 0,
          'question': question,
          'expected': item['expectedAnswer'],
          'output': capture.output,
          'appOutput': baseline.turn.assistantText,
          'appOutcome': baseline.turn.outcome.name,
          'latencyMs': watch.elapsedMilliseconds,
        });
        final payload = jsonDecode(original) as Map<String, dynamic>;
        final intact = {
          ...payload,
          'current_evidence': [
            for (var i = 0; i < evidence.length; i++)
              {
                'source_id': scope[i],
                'source_title':
                    excerpts[(item['excerptIDs'] as List)[i]]!['title'],
                'page': null,
                'section': '',
                'passage': evidence[i],
              },
          ],
        };
        final reordered = {
          'current_evidence': payload['current_evidence'],
          'conversation_context': payload['conversation_context'],
          'current_user_message': payload['current_user_message'],
        };
        final plain = buildGuardrailV1Prompt(
          question: question,
          evidence: evidence,
        );
        final variants = <(String, String, String)>[
          ('v2-json-native', 'v2', original),
          ('v1-instructions-v2-json', 'v1', original),
          ('v1-canonical', 'v1', plain),
          (
            'v1-matched-chunks',
            'v1',
            buildGuardrailV1Prompt(
              question: question,
              evidence: (payload['current_evidence'] as List)
                  .map((p) => p['passage'] as String)
                  .toList(),
            ),
          ),
          ('v1-intact-json', 'v1', jsonEncode(intact)),
          ('v2-intact-evidence', 'v2', jsonEncode(intact)),
          ('v2-evidence-first', 'v2', jsonEncode(reordered)),
          (
            'v2-pretty-json',
            'v2',
            const JsonEncoder.withIndent('  ').convert(payload),
          ),
        ];
        for (var repeat = 1; repeat <= 2; repeat++) {
          // Reverse variant order on the second pass to reduce time/order bias.
          for (final (label, mode, prompt)
              in repeat == 1 ? variants : variants.reversed) {
            if (interrupted) throw StateError('Interrupted');
            var output = '';
            String? failure;
            final latency = Stopwatch()..start();
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
            } on LlmException catch (error) {
              failure = error.code.name;
            } on TimeoutException {
              failure = 'timeout';
            }
            rows.add({
              'caseID': item['id'],
              'variant': label,
              'repeat': repeat,
              'question': question,
              'expected': item['expectedAnswer'],
              'output': output,
              'failure': failure,
              'latencyMs': latency.elapsedMilliseconds,
            });
            await save('progress');
            if (mounted) {
              setState(
                () => status = '${rows.length} diagnostic responses recorded.',
              );
            }
          }
        }
        await workspace.deleteAllChats();
      }
      // Same factual chat content under different presentation, unchanged native
      // General instructions. These are diagnostics, not proposed production prompts.
      final general = {
        'context_summary': null,
        'recent_turns': [
          {
            'user':
                'For this fictional test, the project codename is Copper Finch. Reply with that codename.',
            'assistant': 'Copper Finch.',
            'outcome': 'completed',
          },
          {
            'user': 'What project codename did I just give you?',
            'assistant': 'Copper Finch.',
            'outcome': 'completed',
          },
        ],
        'current_user_message':
            'For this fictional test, our meeting day is Wednesday. Acknowledge briefly.',
      };
      final generalVariants = [
        ('general-json', jsonEncode(general)),
        (
          'general-pretty-json',
          const JsonEncoder.withIndent('  ').convert(general),
        ),
        (
          'general-role-text',
          'Earlier chat (context only):\nUser: For this fictional test, the project codename is Copper Finch. Reply with that codename.\nAssistant: Copper Finch.\nUser: What project codename did I just give you?\nAssistant: Copper Finch.\n\nCurrent user message:\nFor this fictional test, our meeting day is Wednesday. Acknowledge briefly.',
        ),
      ];
      for (var repeat = 1; repeat <= 3; repeat++) {
        for (final (label, prompt) in generalVariants) {
          if (interrupted) throw StateError('Interrupted');
          var output = '';
          String? failure;
          try {
            await for (final snapshot
                in native
                    .generateGeneral(prompt: prompt)
                    .timeout(const Duration(seconds: 60))) {
              output = snapshot;
            }
          } on LlmException catch (error) {
            failure = error.code.name;
          } on TimeoutException {
            failure = 'timeout';
          }
          rows.add({
            'caseID': 'general-current-message',
            'variant': label,
            'repeat': repeat,
            'expected':
                'Acknowledge Wednesday, not just repeat the old codename.',
            'output': output,
            'failure': failure,
          });
          await save('progress');
        }
      }
      if (interrupted) throw StateError('Interrupted');
      report['complete'] = true;
    } on Object {
      report['error'] = interrupted ? 'interrupted' : 'diagnostic-failure';
    } finally {
      await engine?.dispose();
      engine = null;
      await knowledge?.dispose();
      await workspace?.dispose();
      await vault?.close();
      report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
      await save('result');
      finished = true;
      if (mounted) {
        setState(
          () => status = report['complete'] == true
              ? 'Comparison exported. Diagnostic only—not a release pass.'
              : 'Diagnostic incomplete; partial evidence retained.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(
      middle: Text('Generation diagnostic'),
    ),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('FICTIONAL DEVELOPMENT DATA — keep this screen open.'),
            const SizedBox(height: 24),
            Text(status),
          ],
        ),
      ),
    ),
  );
}

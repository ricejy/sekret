import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/chat/chat_engine.dart';
import '../core/chat/chat_workspace.dart';
import '../core/knowledge/knowledge_base.dart';
import '../core/knowledge/knowledge_algorithms.dart' show RetrievalMode;
import '../core/platform/apple_embedder.dart';
import '../core/platform/apple_foundation_models.dart';
import '../core/platform/embedder.dart';
import '../core/platform/llm_backend.dart';
import '../core/question/document_question_service.dart'
    show insufficientEvidenceMessage;
import '../core/storage/local_data_vault.dart';
import 'synthetic_retrieval_corpus.dart';

const _candidate = String.fromEnvironment(
  'EVALUATION_CANDIDATE',
  defaultValue: 'unrecorded-working-tree',
);
const _retrievalSha = String.fromEnvironment('EVALUATION_RETRIEVAL_SHA256');
const _algorithmsSha = String.fromEnvironment('EVALUATION_ALGORITHMS_SHA256');

/// Standalone fictional retrieval probe, never imported by the production main.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CupertinoApp(home: _RetrievalGate()));
}

/// This adapter does NOT evaluate generation quality. It lets the real engine
/// finish after sealing its exact admitted evidence, without generating an answer.
final class _NoGeneration implements GeneralLlmBackend, GroundedLlmBackend {
  @override
  Stream<String> verifyGrounded({required String prompt}) =>
      Stream.error(StateError('Retrieval-only probe must not verify answers.'));
  @override
  Future<LlmAvailability> availability() async => const Available();
  @override
  Stream<String> generateGeneral({required String prompt}) =>
      Stream.error(StateError('This probe must not enter General mode.'));
  @override
  Stream<String> generateGrounded({required String prompt}) =>
      Stream.value(insufficientEvidenceMessage);
}

class _RetrievalGate extends StatefulWidget {
  const _RetrievalGate();
  @override
  State<_RetrievalGate> createState() => _RetrievalGateState();
}

class _RetrievalGateState extends State<_RetrievalGate>
    with WidgetsBindingObserver {
  String _status = 'Preparing fictional v2 retrieval evaluation…';
  Map<String, Object>? _report;
  bool _interrupted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_report == null &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      _interrupted = true;
    }
  }

  @override
  void dispose() {
    _interrupted = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _run() async {
    LocalDataVault? vault;
    ChatWorkspace? workspace;
    KnowledgeBase? knowledge;
    ChatEngine? engine;
    try {
      if (!Platform.isIOS) throw StateError('Physical iPhone required');
      final models = AppleFoundationModels();
      final embedder = AppleEmbedder();
      if (await models.availability() is! Available) {
        throw StateError('Model unavailable');
      }
      final metadata = await embedder.embeddingModelStatus();
      if (metadata is! EmbeddingModelAvailable) {
        throw StateError('Embeddings unavailable');
      }
      final contextSize = await models.contextWindowSize();
      vault = await openLocalDataVault(databasePath: ':memory:');
      workspace = await ChatWorkspace.open(vault);
      knowledge = await KnowledgeBase.open(
        vault: vault,
        embedder: embedder,
        tokenCounter: models,
      );
      final probe = _NoGeneration();
      engine = ChatEngine(
        workspace: workspace,
        backend: probe,
        contextProbe: models,
        groundedBackend: probe,
        knowledgeBase: knowledge,
        model: ModelSnapshot(
          identifier: 'retrieval-only-no-generation',
          revision: Platform.operatingSystemVersion,
        ),
      );
      final sourceIds = <String, String>{};
      final watch = Stopwatch()..start();
      for (final fixture in syntheticRetrievalCorpus) {
        final imported = await knowledge.importText(
          title: fixture.title,
          text: fixture.text,
        );
        final indexed = await knowledge.process(imported.item.id);
        if (indexed.processingState != KnowledgeProcessingState.indexed) {
          throw StateError('Index failed');
        }
        sourceIds[fixture.id] = indexed.id;
      }
      if (const bool.fromEnvironment('RETRIEVAL_DIAGNOSTIC')) {
        final report = await _diagnoseMeridian(
          workspace,
          knowledge,
          engine,
          sourceIds,
        );
        if (_interrupted || !mounted) throw StateError('Interrupted');
        await _exportReport({
          'schemaVersion': 1,
          'purpose': 'meridian-term-diagnostic-not-acceptance',
          'runAt': DateTime.now().toUtc().toIso8601String(),
          'candidate': _candidate,
          'retrievalSourceSha256': _retrievalSha,
          'algorithmsSourceSha256': _algorithmsSha,
          'runtime': Platform.operatingSystemVersion,
          'generationEvaluated': false,
          'contextSize': contextSize,
          'elapsedMs': watch.elapsedMilliseconds,
          'runs': report,
        });
        if (mounted) {
          setState(
            () =>
                _status = 'Focused diagnostic exported. No answer generation.',
          );
        }
        return;
      }
      var singleHits = 0;
      var multiHits = 0;
      var reversedHits = 0;
      var denseHits = 0;
      final cases = <Map<String, Object>>[];
      for (final fixture in syntheticRetrievalCorpus) {
        for (final question in fixture.questions) {
          if (_interrupted || !mounted) throw StateError('Interrupted');
          final target = sourceIds[fixture.id]!;
          final dense = await knowledge.retrieve(
            itemId: target,
            question: question.question,
            mode: RetrievalMode.denseOnly,
          );
          final denseHit = dense
              .take(4)
              .any((p) => question.relevantHeadings.contains(p.heading));
          if (denseHit) denseHits++;
          final hits = <bool>[];
          List<String>? forwardEvidence;
          for (final scope in [
            [target],
            sourceIds.values.toList(),
            sourceIds.values.toList().reversed.toList(),
          ]) {
            final chat = await workspace.newChat();
            await workspace.changeScope(chat.id, ChatMode.knowledgeBase, scope);
            final result = await engine.send(
              chatId: chat.id,
              text: question.question,
            );
            if (result.turn.outcome != TurnOutcome.insufficientEvidence) {
              throw StateError('Probe failed');
            }
            final evidence = result.turn.provenance.evidence;
            final signature = evidence
                .map(
                  (e) => jsonEncode([
                    e.sourceId,
                    e.heading,
                    e.page,
                    e.passageText,
                  ]),
                )
                .toList();
            if (hits.length == 1) forwardEvidence = signature;
            if (hits.length == 2 &&
                jsonEncode(forwardEvidence) != jsonEncode(signature)) {
              throw StateError('Source-order invariance failed');
            }
            if (evidence.length > 4 ||
                evidence.any((e) => !scope.contains(e.sourceId))) {
              throw StateError('Evidence admission invariant failed');
            }
            hits.add(
              evidence.any(
                (e) =>
                    e.sourceId == target &&
                    question.relevantHeadings.contains(e.heading),
              ),
            );
            await workspace.deleteAllChats();
          }
          if (hits[0]) singleHits++;
          if (hits[1]) multiHits++;
          if (hits[2]) reversedHits++;
          cases.add({
            'questionId': question.id,
            'category': question.category,
            'singleSourceAdmittedHit': hits[0],
            'multiSourceAdmittedHit': hits[1],
            'reversedMultiSourceAdmittedHit': hits[2],
            'denseCandidateHit': denseHit,
          });
          if (mounted) {
            setState(
              () => _status = '${cases.length}/30 fictional questions measured',
            );
          }
          debugPrint('V2_RETRIEVAL_PROGRESS=${cases.length}/30');
        }
      }
      if (_interrupted || !mounted) throw StateError('Interrupted');
      final summary = <String, Object>{
        'schemaVersion': 2,
        'runAt': DateTime.now().toUtc().toIso8601String(),
        'candidate': _candidate,
        'retrievalSourceSha256': _retrievalSha,
        'algorithmsSourceSha256': _algorithmsSha,
        'runtime': Platform.operatingSystemVersion,
        'vaultSchema': localDataVaultSchemaVersion,
        'corpus': 'synthetic-contract-and-policy-v1',
        'questions': cases.length,
        'embedding': {
          'implementation': metadata.implementation,
          'language': metadata.language,
          'dimensions': metadata.dimensions,
          'revision': metadata.revision,
        },
        'tokenCounter': 'Apple Foundation Models native',
        'contextSize': contextSize,
        'singleSourceAdmittedHits': singleHits,
        'multiSourceAdmittedHits': multiHits,
        'reversedMultiSourceAdmittedHits': reversedHits,
        'sourceOrderInvariant': true,
        'denseOnlyCandidateHits': denseHits,
        'elapsedMs': watch.elapsedMilliseconds,
        'generationEvaluated': false,
        'meetsV1SingleSourceBaseline':
            cases.length == 30 && singleHits == 30 && denseHits >= 29,
        'multiSourcePerfectRecall': cases.length == 30 && multiHits == 30,
      };
      await _exportReport({...summary, 'cases': cases});
      debugPrint('V2_RETRIEVAL_SUMMARY_JSON=${jsonEncode(summary)}');
      final json = jsonEncode(_report);
      final parts = (json.length / 800).ceil();
      for (var part = 0; part < parts; part++) {
        final end = ((part + 1) * 800).clamp(0, json.length);
        debugPrint(
          'V2_RETRIEVAL_JSON_PART=${part + 1}/$parts:${json.substring(part * 800, end)}',
        );
      }
      if (mounted) {
        setState(
          () => _status =
              'Single-source: $singleHits/30\nMulti-source: $multiHits/30\nDense candidates: $denseHits/30\nGeneration not evaluated.',
        );
      }
    } on Object {
      debugPrint(
        'V2_RETRIEVAL_FAILED=${_interrupted ? 'interrupted' : 'capability_or_evaluation_failure'}',
      );
      if (mounted) {
        setState(
          () => _status =
              'Evaluation did not complete. Keep the app in front, check model readiness, and relaunch. No passing result recorded.',
        );
      }
    } finally {
      await engine?.dispose();
      await knowledge?.dispose();
      await workspace?.dispose();
      await vault?.close();
    }
  }

  Future<void> _exportReport(Map<String, Object> report) async {
    // Only this standalone fictional evaluator writes here. Unique run folders
    // preserve initial scores when diagnostics are repeated; never read a vault.
    final documents = await getApplicationDocumentsDirectory();
    final exports = await Directory(
      '${documents.path}/v2-retrieval-evaluation',
    ).create(recursive: true);
    final runDirectory = await exports.createTemp('run-');
    await File('${runDirectory.path}/result.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    _report = report;
  }

  /// Fictional-only boundary trace. No private database IDs, text or vectors.
  Future<List<Map<String, Object>>> _diagnoseMeridian(
    ChatWorkspace workspace,
    KnowledgeBase knowledge,
    ChatEngine engine,
    Map<String, String> sourceIds,
  ) async {
    final fixture = syntheticRetrievalCorpus.last;
    final question = fixture.questions.first;
    final target = sourceIds[fixture.id]!;
    final all = sourceIds.values.toList();
    final fixtureIds = {
      for (final entry in sourceIds.entries) entry.value: entry.key,
    };
    final scopes = <(String, List<String>)>[
      ('single', [target]),
      for (var repeat = 1; repeat <= 3; repeat++) ('all-repeat-$repeat', all),
      ('all-reversed', all.reversed.toList()),
      for (final other in all.where((id) => id != target))
        ('pair-${fixtureIds[other]}', [other, target]),
    ];
    final runs = <Map<String, Object>>[];
    for (final (label, scope) in scopes) {
      if (_interrupted || !mounted) throw StateError('Interrupted');
      final chat = await workspace.newChat();
      await workspace.changeScope(chat.id, ChatMode.knowledgeBase, scope);
      final result = await engine.send(
        chatId: chat.id,
        text: question.question,
      );
      final provenance = result.turn.provenance;
      // Use the exact immutable scope/order seen by the engine, not an assumed
      // correspondence with caller selection order.
      final actualScope = provenance.sourceScope.map((s) => s.id).toList();
      final candidates = await knowledge.retrieveAcross(
        sourceIds: actualScope,
        question: question.question,
      );
      final expectedRank =
          candidates.indexWhere(
            (p) =>
                p.knowledgeItemId == target &&
                question.relevantHeadings.contains(p.heading),
          ) +
          1;
      final hit = provenance.evidence.any(
        (p) =>
            p.sourceId == target &&
            question.relevantHeadings.contains(p.heading),
      );
      runs.add({
        'label': label,
        'questionId': question.id,
        'requestedScope': scope.map((id) => fixtureIds[id]!).toList(),
        'actualScope': actualScope.map((id) => fixtureIds[id]!).toList(),
        'outcome': result.turn.outcome.name,
        'admittedHit': hit,
        'expectedCandidateRank': expectedRank,
        'candidates': [
          for (var i = 0; i < candidates.length; i++)
            {
              'rank': i + 1,
              'source': fixtureIds[candidates[i].knowledgeItemId]!,
              'heading': candidates[i].heading,
              'tokenCount': candidates[i].tokenCount,
            },
        ],
        'admitted': [
          for (final p in provenance.evidence)
            {
              'source': fixtureIds[p.sourceId]!,
              'heading': p.heading,
              'candidateRank':
                  candidates.indexWhere(
                    (c) =>
                        c.knowledgeItemId == p.sourceId &&
                        c.heading == p.heading &&
                        c.page == p.page &&
                        c.text == p.passageText,
                  ) +
                  1,
            },
        ],
      });
      await workspace.deleteAllChats();
    }
    return runs;
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(
      middle: Text('Fictional retrieval gate'),
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'TEST DATA — actual v2 retrieval and native token counting, no answer generation. Keep this screen open.',
          ),
          const SizedBox(height: 24),
          Text(_status),
          if (_report != null)
            CupertinoButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text: const JsonEncoder.withIndent('  ').convert(_report),
                ),
              ),
              child: const Text('Copy aggregate results'),
            ),
        ],
      ),
    ),
  );
}

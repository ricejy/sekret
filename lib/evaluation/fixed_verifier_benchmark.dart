// Fictional development-only verifier measurements. No vault or generator.
import 'dart:convert';

import '../core/platform/llm_backend.dart';

const fixedVerifierPurpose = 'fixed-verifier-development-not-acceptance';

List<Map<String, dynamic>> fixedVerifierCases(Map<String, dynamic> suite) {
  if (suite['schemaVersion'] != 1 ||
      suite['fictional'] != true ||
      suite['purpose'] != fixedVerifierPurpose ||
      suite['repeats'] != 3) {
    throw const FormatException('Frozen fictional development suite required');
  }
  final cases = (suite['cases'] as List).cast<Map<String, dynamic>>();
  final ids = <String>{};
  if (cases.isEmpty) throw const FormatException('Empty suite');
  for (final row in cases) {
    if (!ids.add(row['id'] as String) ||
        (row['question'] as String).trim().isEmpty ||
        (row['draft'] as String).trim().isEmpty ||
        (row['evidence'] as List).isEmpty) {
      throw const FormatException('Invalid fixed case');
    }
    parseGroundedVerification(row['expectedVerdict'] as String);
    fixedVerifierPrompt(row);
  }
  return cases;
}

/// The exact production framing, with fixed fictional metadata and no history.
/// Labels/rationales are deliberately never passed to the model.
String fixedVerifierPrompt(Map<String, dynamic> row) =>
    buildGroundedVerificationPrompt(
      groundedPrompt: buildGroundedChatPrompt(
        question: row['question'] as String,
        conversationContext: {'context_summary': null, 'recent_turns': []},
        evidence: [
          for (final p in (row['evidence'] as List).cast<Map>())
            (
              sourceId: p['sourceId'] as String,
              sourceTitle: p['sourceTitle'] as String,
              page: p['page'] as int?,
              section: p['section'] as String?,
              text: p['text'] as String,
            ),
        ],
      ),
      draft: row['draft'] as String,
    );

/// Three passes with deterministic forward/reverse/rotated order.
/// Repetitions stay visible; a later pass never replaces an earlier failure.
List<({Map<String, dynamic> row, int repeat})> fixedVerifierPlan(
  List<Map<String, dynamic>> cases,
) => [
  for (var repeat = 1; repeat <= 3; repeat++)
    for (final row in switch (repeat) {
      1 => cases,
      2 => cases.reversed,
      _ => [...cases.skip(cases.length ~/ 2), ...cases.take(cases.length ~/ 2)],
    })
      (row: row, repeat: repeat),
];

Map<String, Object?> gradeFixedVerifier(
  List<Map<String, dynamic>> cases,
  List<Map<String, dynamic>> rows,
) {
  final byId = {for (final c in cases) c['id'] as String: c};
  final seen = <String>{};
  var positives = 0;
  var negatives = 0;
  var falseApprovals = 0;
  var falseRejections = 0;
  var runtimeFailures = 0;
  var exactLabels = 0;
  final errors = <Map<String, Object?>>[];
  final latencies = <int>[];
  final decisions = <String, Set<String>>{};
  for (final r in rows) {
    final c = byId[r['caseID']];
    final repeat = r['repeat'];
    if (c == null ||
        repeat is! int ||
        repeat < 1 ||
        repeat > 3 ||
        !seen.add('${r['caseID']}:$repeat') ||
        r['prompt'] != fixedVerifierPrompt(c)) {
      throw const FormatException('Unknown, duplicate, or changed trial');
    }
    final expected = c['expectedVerdict'] as String;
    final positive = expected == 'SUPPORTED';
    positive ? positives++ : negatives++;
    String decision;
    try {
      if (r['failure'] != null) throw const FormatException('Runtime failure');
      final output = (r['output'] as String).trim();
      parseGroundedVerification(output);
      decision = output;
      if (output == expected) exactLabels++;
      if (positive && output != 'SUPPORTED') falseRejections++;
      if (!positive && output == 'SUPPORTED') falseApprovals++;
    } on Object {
      decision = 'ERROR';
      runtimeFailures++;
      // Errors are counted separately, never credited as correct rejections.
    }
    decisions.putIfAbsent(r['caseID'] as String, () => {}).add(decision);
    if (decision != expected) {
      errors.add({
        'caseID': r['caseID'],
        'repeat': repeat,
        'expected': expected,
        'actual': decision,
      });
    }
    if (decision != 'ERROR') latencies.add(r['latencyMs'] as int);
  }
  latencies.sort();
  num? median() => latencies.isEmpty
      ? null
      : latencies.length.isOdd
      ? latencies[latencies.length ~/ 2]
      : (latencies[latencies.length ~/ 2 - 1] +
                latencies[latencies.length ~/ 2]) /
            2;
  final complete = rows.length == cases.length * 3;
  return {
    'complete': complete,
    'trials': rows.length,
    'supportedTrials': positives,
    'unsupportedTrials': negatives,
    'falseApprovals': falseApprovals,
    'falseRejections': falseRejections,
    'runtimeOrInvalidLabelFailures': runtimeFailures,
    'exactLabelCorrect': exactLabels,
    'verifierOnlyMedianMs': median(),
    'firstCallMs': rows.isEmpty ? null : rows.first['latencyMs'],
    'verifierOnlyP95Ms': latencies.isEmpty
        ? null
        : latencies[(latencies.length * .95).ceil() - 1],
    'unstableCaseIDs': [
      for (final e in decisions.entries)
        if (e.value.length > 1) e.key,
    ],
    'labelMismatches': errors,
    // Predeclared development screen, not a release gate or statistical proof.
    'developmentTargetMet':
        complete &&
        positives > 0 &&
        negatives > 0 &&
        falseApprovals == 0 &&
        falseRejections / positives <= .10 &&
        runtimeFailures == 0,
    'target':
        'Zero false approvals/errors; at most 10% false rejections. '
        'Development screen only, not release acceptance.',
  };
}

Map<String, dynamic> decodeFixedVerifierSuite(String text) =>
    jsonDecode(text) as Map<String, dynamic>;

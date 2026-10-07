// Run with dart run tool/diagnostics/check_fixed_verifier.dart <result.json>.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sekret/evaluation/fixed_verifier_benchmark.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/diagnostics/check_fixed_verifier.dart <result.json>',
    );
    exitCode = 2;
    return;
  }
  final bytes = File(
    'eval/guardrails/fixed_verifier_development_v1.json',
  ).readAsBytesSync();
  final suite = decodeFixedVerifierSuite(utf8.decode(bytes));
  final report = jsonDecode(File(args.single).readAsStringSync()) as Map;
  if (report['fixtureSha256'] != sha256.convert(bytes).toString() ||
      report['purpose'] != fixedVerifierPurpose ||
      report['fictional'] != true) {
    throw const FormatException('Wrong fixture or result provenance');
  }
  final grades = gradeFixedVerifier(
    fixedVerifierCases(suite),
    (report['results'] as List).cast<Map<String, dynamic>>(),
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(grades));
  exitCode =
      report['complete'] == true && grades['developmentTargetMet'] == true
      ? 0
      : 1;
}

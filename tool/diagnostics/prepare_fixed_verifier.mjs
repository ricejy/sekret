// Generates disposable build definitions; no weights, dependencies, or vault IO.
import {readFileSync, writeFileSync, mkdtempSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
const files = [
  'eval/guardrails/fixed_verifier_development_v1.json',
  'lib/evaluation/fixed_verifier_benchmark.dart',
  'lib/evaluation/fixed_verifier_main.dart',
  'lib/core/platform/llm_backend.dart',
  'lib/core/platform/apple_foundation_models.dart',
  'ios/Runner/AppleFoundationModelsPlugin.swift',
];
const hashes = Object.fromEntries(files.map(path => [path,
  createHash('sha256').update(readFileSync(path)).digest('hex')]));
const directory = mkdtempSync('/private/tmp/sekret-fixed-verifier-');
const manifest = {baseHead: execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  dirtyWorkingTree: true, files: hashes};
const defs = {
  FIXED_VERIFIER_SUITE_BASE64: readFileSync(files[0]).toString('base64'),
  EVALUATION_SOURCE_MANIFEST: JSON.stringify(manifest),
};
writeFileSync(`${directory}/defines.json`, JSON.stringify(defs, null, 2));
console.log(`${directory}/defines.json`);

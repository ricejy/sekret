# Grounding diagnostics

## Fixed-answer verifier comparison (development only)

`eval/guardrails/fixed_verifier_development_v1.json` freezes 28 fictional cases
(14 supported, 14 unsupported), including four previously captured development
drafts. SHA-256: `737ba8a186362c8a30323370d0778b34e0e9007f8ea916df8f1bfa1d98a89169`.
Expected labels/rationales were fixed before the verifier-only runs. Three passes
use forward, reverse, then rotated order, preserving every result. Do not edit v1
after viewing results. This is not a fresh release acceptance suite.

The predeclared development screen requires zero false approvals/runtime errors
and at most 10% false rejections; exact three-label accuracy is secondary. Errors
and token overflow never receive credit as correct rejections. These few repeated
cases cannot establish population accuracy or a release pass.

Native Apple baseline (no generator, retrieval, or vault access):

```sh
flutter test test/fixed_verifier_benchmark_test.dart
node tool/diagnostics/prepare_fixed_verifier.mjs
# Use the emitted temporary definitions path:
flutter build ios --release --dart-define-from-file=<defines.json> -t lib/evaluation/fixed_verifier_main.dart
# Install/launch only with the owner's test-device permission.
# Copy only Documents/fixed-verifier-evaluation/run-*/result.json.
dart run tool/diagnostics/check_fixed_verifier.dart <result.json>
```

The last command exits 1 for incomplete/failed quality, not just runtime errors.
The model sees production verifier framing and fixed question, passages, draft,
and metadata, but never the expected label/rationale. Cancellation/backgrounding
ends the run without a pass. Each inference has a 30-second total deadline.

Approved isolated DeBERTa experiment (not app dependencies):

```sh
uv venv <temporary-directory>/venv
uv pip install --python <temporary-directory>/venv/bin/python -r tool/diagnostics/nli-requirements.txt
node tool/diagnostics/download_nli_candidate.mjs <temporary-directory>/assets
<temporary-directory>/venv/bin/python tool/diagnostics/check_nli_tokenizer.py <temporary-directory>/assets
<temporary-directory>/venv/bin/python tool/diagnostics/run_nli_candidate.py <temporary-directory>/assets fp32 <fp32-result.json>
<temporary-directory>/venv/bin/python tool/diagnostics/run_nli_candidate.py <temporary-directory>/assets arm64-int8 <int8-result.json>
<temporary-directory>/venv/bin/python tool/diagnostics/compare_nli_results.py <fp32-result.json> <int8-result.json>
```

Only the download/setup commands need network access. Inference loads explicit
local ONNX/tokenizer paths. Assets are pinned to publisher revision
`a150876415327c80daeff35ca6f68f5ed8cf5c24`, hashed, and excluded from the repository.
The last command recomputes quality failures and exits 1. Fresh output paths are
required; reruns must not erase initial results.

NLI takes unchanged passage texts as premise and the unchanged draft as hypothesis;
it does **not** receive the question or metadata. No human/oracle rewrite expands
short answers. Thus the cases are fixed but model interfaces differ, and the NLI
run evaluates a proposed component, not a drop-in production replacement. Report
question-dependent short answers and answer completeness as interface limitations.
Never silently truncate beyond its combined 512-token limit or substitute Apple
token counts. Token IDs were checked against the publisher's SentencePiece path;
Swift/iPhone tokenizer parity has not been tested.

Measured outcomes and remaining device work are in
`docs/evaluation/fixed-verifier-comparison-2026-09-13.md`.

## Historical lexical-screen replay

Fictional development data only. These historical replays are outside the portable
`test/` suite. They originally exposed the lexical screen's semantic failures.
After separate verification was implemented, they use controlled correct verifier
verdicts to check admission; passing them does not establish native verifier quality.

From the repository root:

```sh
flutter test tool/diagnostics/grounding_replay_test.dart
flutter test --dart-define=MINIMIZE=true tool/diagnostics/grounding_replay_test.dart
```

The test replays two captured native responses with the same admitted passages
and source title through the real ChatEngine and persistence path. Retrieval
vectors and token counts are controlled doubles; this does **not** evaluate
native generation. Before semantic verification, both assertions failed on the
`grounded-chat-v3` overlap-screen pipeline:

The second command narrows each document to one relevant sentence; the event
answer is reduced to the same sentence with `may report` changed to `reported`.

| Case | Desired outcome | Actual outcome | Exact-word overlap |
| --- | --- | --- | --- |
| LEG-A09: correct paraphrase | Completed | Insufficient evidence | 5/11 (45.45%) |
| LEG-U03: unsupported event | Insufficient evidence | Completed | 12/15 (80%) |

Historical threshold: 50%. These scores run in the opposite direction from semantic
correctness. No adjustment of this single lower-bound threshold can accept the
correct answer and reject the invented event. Negation/modality and inflected
words are not understood by the screen. Do not lower its threshold or suppress
these assertions to obtain a release pass.

The separate physical-device entry point is
`lib/evaluation/v2_grounding_diagnostic_main.dart`. It accepts only fictional
development inputs, compares existing native instruction modes and prompt
representations with matched captured passages, and writes its own isolated
`Documents/v2-grounding-diagnostic/run-*/` JSON exports. It opens no vault. Raw
outputs require semantic review; completion does not imply a quality pass.

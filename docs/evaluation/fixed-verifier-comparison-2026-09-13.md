# Fixed-answer verifier development comparison — 2026-09-13

## Outcome

**The first alternative is not suitable to integrate.** DeBERTa-v3-xsmall NLI,
both publisher FP32 and ARM64 INT8 exports, made the same three false approvals
and three false rejections on every pass. Do not add it to the shipping app or
claim semantic verification is solved. No production files, dependencies, signing
settings, or vault contents were changed by this experiment.

**The unchanged Apple verifier also failed this fixed-suite screen.** After the
owner unlocked the iPhone, all 84 trials completed: 13/42 false approvals and 11/42
false rejections, with zero runtime/invalid-label failures. Both tested approaches
remain unsuitable as the app's grounding safety check. This is a development
finding, not proof that every small local verifier will fail.

## Frozen experiment

- Fixture: `eval/guardrails/fixed_verifier_development_v1.json`, SHA-256
  `737ba8a186362c8a30323370d0778b34e0e9007f8ea916df8f1bfa1d98a89169`.
- 28 cases: 14 supported and 14 unsupported; 24 matched synthetic cases plus four
  unchanged captured development drafts/questions/passages. Captured source IDs
  are normalized fixture IDs and titles are resolved from the development suite.
- Three complete passes (forward/reverse/rotated); 84 trials per model variant.
  Repeats measure stability, not 84 independent examples.
- Gold labels and rationales frozen before any fixed-suite inference. No generator,
  retrieval, private material, threshold tuning, or acceptance cases in the loop.
- Predeclared development screen: no false approvals/errors; at most 10% false
  rejections. This is deliberately not the #29 release acceptance gate.
- Primary metric: admit supported answers and reject unsupported answers.
  `CONTRADICTED` versus `NOT_ESTABLISHED` accuracy is secondary.

## Mac results — first runs retained

| Measurement | FP32 | ARM64 INT8 |
| --- | ---: | ---: |
| Unsupported drafts incorrectly admitted | 9/42 trials (3/14 cases) | 9/42 trials (3/14 cases) |
| Supported drafts incorrectly rejected | 9/42 trials (3/14 cases) | 9/42 trials (3/14 cases) |
| Exact three-label correctness | 63/84 | 66/84 |
| Runtime failures / token overflows | 0 / 0 | 0 / 0 |
| Cases changing verdict across repeats | 0 | 0 |
| Median tokenization + inference time | 14.68 ms | 9.38 ms |
| First inference | 16.29 ms | 10.20 ms |
| Model session load | 426.37 ms | 388.98 ms |
| Whole-process peak RSS | 944,717,824 bytes | 515,375,104 bytes |

These are local **Mac CPU** measurements, two intra-op threads, one inter-op
thread, separate fresh Python processes. Peak RSS includes Python, runtime,
tokenizer, hashing/loading, and inference—not model-only RAM. None of these
measurements establish iPhone latency, memory alongside Apple's resident model,
Neural Engine execution, energy, or thermal behavior.

The six exact-label differences between exports occur on two cases across three
repeats; **none changes admission**. Quantization did not introduce the observed
false approvals/rejections. This does not prove quantization parity universally.

## Apple iPhone baseline — completed after unlock

The already-installed harness launched at `2026-09-13T06:51:53Z` and finished at
`06:52:27Z` on the iPhone 15 Pro Max, iOS 26.6.2 (23G90), using unchanged
`grounded-verification-v2`. Export:
`Documents/fixed-verifier-evaluation/run-HCpBE6/result.json`, preserved as
`eval/guardrails/fixed-verifier-apple-2026-09-13.json`.

| Measurement | Apple verifier |
| --- | ---: |
| Unsupported drafts incorrectly admitted | 13/42 trials; 5 distinct cases |
| Supported drafts incorrectly rejected | 11/42 trials; 4 distinct cases |
| Correct binary admission/rejection | 60/84 |
| Exact three-label correctness | 39/84 |
| Runtime / invalid-label failures | 0 |
| Cases with changing labels | 4 (3 changed admission) |
| Verifier-only median / p95 | 327 / 594 ms |
| First verifier call | 451 ms |

The app-token preflight is outside these per-call latency measurements; the
measurement includes native stream completion but not answer generation. Memory,
energy, thermals, and cold model loading were not measured. Mac NLI timings are
not a same-device speed comparison.

False approvals: wrong amount (2/3), invented manager (2/3), swapped plan facts
(3/3), captured workplace-letter draft `MED-A20` (3/3), and captured invented
reporting event `LEG-U03` (3/3). False rejections: correct permission/event negative
(2/3), correct no-automatic-deadline-pause answer (3/3), correct schedule-not-proof
answer (3/3), and captured correct mediation answer `LEG-A19` (3/3).

This reproduces the original semantic admission defect with **unchanged evidence
and unchanged drafts**, without retrieval or generator variability. Labels such
as NOT_ESTABLISHED instead of CONTRADICTED still reject a bad answer, so the lower
exact-label score must not be confused with the primary admission score.

The export's fixture and all six recorded source-file hashes match the current
frozen harness/bridge sources. Independent scoring with
`dart run tool/diagnostics/check_fixed_verifier.dart <export>` exited **1** and
reproduced the recorded counts. No rerun replaced these first observations, no
labels or prompts were tuned, and no acceptance pass is claimed.

### Specific failures

Both variants consistently admitted:

1. **Permission → event:** the record says Nila *may report* misconduct and gives no
   record of doing so; the draft says she *reported* it.
2. **Wrong amount:** evidence says SGD 420; the short draft says four hundred and
   seventy Singapore dollars.
3. **Schedule → event:** a planning note schedules a workshop but records no
   attendance; the draft says it *took place*.

Both consistently rejected: the correct statement that a manager is not identified,
the correct short answer “Six digits,” and the captured correct pay-discussion
answer (`LEG-A09`). Both rejected the captured invented Elena-contact answer
(`LEG-U03`), but that isolated improvement does not compensate for other false
approvals. The schedule error received approximately 0.97 entailment softmax in
both variants: apparent confidence is not factual reliability.

### Interface and interpretation limits

The NLI component uses premise = all fixed passage texts, hypothesis = unchanged
draft. It does not consume the original question or metadata, unlike the Apple
verifier. No human expands short answers into self-contained claims. This prevents
an unimplemented oracle preprocessing step from receiving credit, but means these
are fixed cases with different input protocols, not an identical-prompt model swap.
The wrong-amount and short-answer failures need to be interpreted with that gap.
The permission/event and schedule/event failures are self-contained claims, so
missing question interpretation cannot explain all errors.

Claim entailment and answer adequacy are different. A true fragment can omit part
of the requested answer; NLI alone cannot certify completeness. The captured
`MED-A20` draft also changes a possibility to asserted attendance, so its rejection
is not based solely on a missing detail. No thresholds or gold labels were changed
after observing these results.

## Reproduction and validation

Research rationale and primary-source citations:
[local verifier candidates](local-verifier-candidates-2026-09-13.md).
Model revision: `a150876415327c80daeff35ca6f68f5ed8cf5c24`. Publisher label
mapping checked: contradiction, entailment, neutral. Every input stays within 512
tokens without truncation. Fast tokenizer IDs and attention masks matched the
publisher's SentencePiece tokenizer on **28/28** cases. This rules out a tokenizer
mismatch on this set, not all possible integration errors.

Results (fictional only):

- `eval/guardrails/fixed-verifier-nli-fp32-2026-09-13.json`
- `eval/guardrails/fixed-verifier-nli-int8-2026-09-13.json`
- `eval/guardrails/fixed-verifier-nli-tokenizer-parity-2026-09-13.json`
- `eval/guardrails/fixed-verifier-apple-2026-09-13.json`

The agent ran the following red-capable command; it exited **1**, reporting nine
false approvals and nine false rejections per variant. This is the intended
quality failure, not an infrastructure error:

```sh
<evaluation-python> tool/diagnostics/compare_nli_results.py \
  eval/guardrails/fixed-verifier-nli-fp32-2026-09-13.json \
  eval/guardrails/fixed-verifier-nli-int8-2026-09-13.json
```

`flutter analyze`: clean after resolving three benchmark lint findings.
`flutter test`: **211 passed**, including six new scoring/fixture integrity tests.
Release benchmark build: passed, 23.2-second Xcode build. No native production
bridge change this turn; the earlier 22 native tests remain historical evidence,
not a new run. No regular vault or owner screen regression was performed.

Scripts, setup instructions, fixed-label hash assertion, input validation,
no-overwrite result handling, and the isolated dependency snapshot live under
`tool/diagnostics/`. Model/runtime assets remain outside the repository in
`/private/tmp/sekret-nli-comparison.HHp91j` (approximately 586 MiB at measurement).
The owner approved this download; no app-time download mechanism was added.

## Next boundary

The planned fixed-input comparison is complete. Do not engineer an iPhone NLI
integration for this candidate or ship the Apple verifier after these failed
quality screens. A different candidate or a source-excerpt answer design requires
a separate choice; this experiment does not establish that all small local
verifiers are inadequate. #29 remains open, with no release pass or PR. The owner
can leave the test screen; no further device interaction is needed for this run.

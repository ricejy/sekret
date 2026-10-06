# Sekret v2 release gate — work in progress

Issue #29. This is an evidence ledger, not a release approval. Only fictional
fixtures and aggregate measurements may be retained. Never record private
prompts, answers, source titles, excerpts, or database contents.

## Candidate

- Merged implementation: `fe03a77e7b8ff607db12e30622d7b30105bf2236` (PR #40).
- App version: `0.1.0+1`; vault schema: 6.
- Pinned Flutter: 3.44.9; Dart requirement: ^3.12.2.
- Mac Xcode: 26.6 (17F113), checked 2026-09-12.
- Target: paired iPhone 15 Pro Max. Record actual OS/build and model/embedding
  capability metadata again at the physical evaluation, not from older reports.
- `lib/main.dart` still defaults to v1. `SEKRET_V2=true` is opt-in and refuses
  incompatible existing databases. Do not reset the regular vault. Final regular
  v2 deployment/transition requires its own immediately confirmed data decision.

## Evidence available at kickoff

| Area | Evidence | Scope / remaining work |
| --- | --- | --- |
| Windows portable checks | Both PR #40 runs passed: [PR run](https://github.com/ricejy/sekret/actions/runs/34668631631), [branch run](https://github.com/ricejy/sekret/actions/runs/34668620791). | Static analysis and portable suite on the final implementation branch. Record merged-main CI separately when complete. |
| Accessibility / visual UI | Owner reported all 14 #28 manual steps passed on 2026-09-12. | Includes large text, VoiceOver, light/dark, Reduce Motion, keyboard/rotation, deletion UI, Photos, preview, and lock regressions. No duplicate agent-driven click-through planned. |
| Settings / native bridges | #27 previously recorded 22 native tests and owner authentication/privacy checks passing. | Historical evidence only; rerun native checks against this candidate. |
| Static network scan | No direct application HTTP client, URLSession/NWConnection, analytics, or telemetry match in the initial source scan. | Not proof of zero traffic. Review dependencies/explicit URL launching, then perform a fresh app-targeted capture. |
| v1 baseline | [Recorded v1 gate](v1-release-gate-2026-09-06.md). | Comparison baseline, not v2 acceptance evidence. |

The [merged-main CI run](https://github.com/ricejy/sekret/actions/runs/34669505166)
completed successfully for `fe03a77`, verified on 2026-09-13.

## Fresh verification — 2026-09-13

- Owner freed additional space: 7.1 GiB available at restart. The previously
  approved generated-output cleanup was completed; no source/app data was deleted.
- Existing non-UI regression suite: **81 passed**. Includes vault schemas,
  workspace retention/summaries, General and grounded engines, Knowledge Base,
  retrieval fixtures, and protection state logic. No screen-level tests were run.
- The initial portable invocation collided with generated-package setup while
  the native configuration ran concurrently. A serial retry passed. Keep Flutter
  setup invocations serialized; no production fix was needed.
- Native Runner XCTest: **22 passed**, no skips, on the physical iPhone using
  a Release host with the isolated accessibility acceptance entry point. The
  first launch was blocked by untrusted developer signing; no tests ran in that
  attempt. The owner trusted the profile and the subsequent run passed.
- `dart run tool/v2_integrity_audit.dart`: **10 stages passed** against a newly
  created disposable fictional database. Every stage verified SQLite integrity,
  foreign keys, FTS structure/content/membership, and explicit expected counts.
  Stages cover fresh/populated schema, import cancellation, source deletion with
  retained citations, turn-tail deletion, finalized chat deletion, retention,
  Delete All Chats, entire Knowledge Base deletion, and Erase All. The fixture
  directory was removed after the audit. [Aggregate results](v2-integrity-2026-09-13.json)
  contain no source text, prompts, answers, or database identifiers.
- New evaluator and audit tool static analysis: clean. The isolated retrieval
  evaluator also compiled successfully as an unsigned iOS Release app (32.6 MB).
  This is compilation evidence only, not signed deployment or a retrieval pass.
- Physical retrieval launch was initially blocked. The initial wireless connection
  failed; after the owner connected USB, Flutter stopped at its Developer Mode
  check. CoreDevice reports wired transport and can query lock state, but its
  device-details request fails and reports Developer Mode as unknown. This does
  not establish that Developer Mode is disabled; the owner confirmed it is on.
  A generic-device Xcode Release build and strict code-signature verification
  then passed. Direct installation still failed with CoreDevice error 4000,
  "Failed to allocate RSD device" (`0xE8000003`). At that point the blocker was
  the device-development connection, not evaluator compilation. No app uninstall
  or data reset was attempted, and no retrieval result was produced.
  The newly detected runtime is iOS 26.6.2
  (23G90), which must be retained with the eventual model evaluation results.
  Available Mac space after compilation: 6.0 GiB.
- The owner subsequently cleared Derived Data/device support and repaired the
  iPhone pairing. CoreDevice now successfully reports Developer Mode enabled,
  wired transport, and a connected tunnel on iOS 26.6.2 (23G90). Free space at
  this restart was 18 GiB. The fresh signed evaluator build completed (35.3 s),
  then installed and launched successfully (6.1 s). The connection blocker is
  resolved. No evaluator result appeared in Flutter's console.
- Owner-reported final evaluator screen: **single-source 30/30, multi-source
  29/30, dense candidates 29/30; generation not evaluated**. The single-source
  and dense scores match the recorded v1 baselines. The all-six-source stress
  score is recorded separately, not presented as perfect recall or as a model
  answer-quality result. The owner's complete JSON export confirms the miss as
  `meridian-term`: single-source admitted hit true, multi-source admitted hit
  false, dense candidate hit true. Its fictional question asks how long a
  workshop membership lasts; expected evidence is `MEMBERSHIP TERM` in the
  Meridian agreement (twelve months from activation). The export contains hit
  booleans, not ranked/admitted passage details, so it does not establish why
  multi-source admission missed the expected evidence. No production change or
  rerun has been made on the basis of this result.
- The [complete first-run export](v2-retrieval-2026-09-13.json) was supplied by the
  owner and retained with whitespace normalized only. Validation confirmed valid
  JSON, all 30 unique question IDs in corpus order, and per-case hit totals matching
  the summary. Run timestamp: 2026-09-13T04:05:11.939061Z; runtime: iOS 26.6.2
  (23G90); Apple Natural Language embeddings: English, 512 dimensions, revision 1;
  native Foundation Models context size: 4096. Total measured evaluation time:
  9,509 ms, including fixture indexing and retrieval checks, **not answer latency**.
  Dense-only missed `juniper-hotel`, which both hybrid admission scopes recovered.
  Multi-source admission missed only `meridian-term`; its cause remains unproven.
  The first-run result is now preserved; further diagnostic runs must be separate.

## Retrieval miss diagnosis — 2026-09-13

The standalone evaluator now writes only fictional reports into unique
`Documents/v2-retrieval-evaluation/run-*/result.json` folders. This allows direct
device retrieval without owner click-through or copying the regular vault.
Console output was unavailable through both Flutter and direct CoreDevice launch.
No production entry point imports this evaluator, and no production retrieval
behavior was changed. Static analysis passed after the evaluator changes.

- A [separate full repeat](v2-retrieval-2026-09-13-repeat-1.json) reproduced
  30/30 single-source, 29/30 multi-source, and 29/30 dense candidates in 8,195 ms.
  Again, only `meridian-term` missed multi-source admission.
- A [focused 10-scenario diagnostic](v2-retrieval-2026-09-13-diagnostic.json)
  then measured just `meridian-term` through fresh chats with actual Apple
  embeddings/native token admission, with no answer generation. It completed in
  1,942 ms including fixture setup. All three all-six-source repetitions placed
  `MEMBERSHIP TERM` at candidate rank 5; the engine admitted ranks 1–4. Reversing
  the same source set moved the expected passage to rank 3 and recovered the hit.
  Single-source and each of five two-source combinations also admitted it.
- The candidate lists were retrieved again using the exact immutable scope/order
  captured by the engine. Their first four passages match the admitted snapshots.
  This distinguishes ranking/cutoff exclusion from token-budget exclusion in these
  runs. The fixed `insufficientEvidence` outcomes are produced by the evaluator's
  stub and are **not** model guardrail findings.
- `KnowledgeBase.retrieveAcross` interleaves per-source lexical lists in caller
  scope order before reciprocal-rank fusion. Positions in that merged list affect
  score, so reversing an otherwise identical source set changes relevance ranks.
  The engine then admits at most four passages. This is a reproducible
  source-order-dependent ranking defect, not evidence that the owner must select
  sources in a particular order. Do not work around it by changing acceptance
  questions or increasing the four-passage cap for this one fixture.

Reproduce with the standalone evaluator built using
`--dart-define=RETRIEVAL_DIAGNOSTIC=true`; install without uninstall/reset, launch,
then copy only its new fictional result directory with CoreDevice. The focused
mode is explicitly labeled diagnostic, never an acceptance run. The source-set
order-invariance fix and complete physical rerun are recorded below, separately
from these pre-fix diagnostic scores.

## Source-order fix verification — 2026-09-13

The owner approved fixing the diagnosed defect. `retrieveAcross` now fuses each
passage's within-source lexical rank with the global dense rank, without inserting
source-order positions into the lexical score. Dense ties are broken by passage
ID before candidate truncation; fused-score ties use the same stable identifier.
The immutable source scope/order, four-passage cap, native prompt budget, and v1
retrieval function are unchanged.

- Two regression tests through the actual SQLite Knowledge Base and ChatEngine
  failed before the fix and passed afterward. They compare candidates and admitted
  evidence across forward, reversed, and rotated scopes containing 24 equal-vector
  sources (more than the 20-candidate cap), with and without lexical matches.
- A third regression checks equal within-source rank weights and stable lexical
  ties. The complete selected non-UI core suite now passes **84 tests**; static
  analysis is clean. No agent-driven screen click-through was run.
- Physical rerun candidate is labeled `fe03a77+source-local-ranks-v1` (uncommitted
  working-tree correction, not a Git commit). The evaluator records SHA-256 hashes
  for both modified retrieval source files. Its schema-2 full run checks all 30
  questions in single-source, all-six forward, and all-six reversed scopes, and
  fails if forward/reversed admitted passage snapshots differ.
- The [post-fix physical export](v2-retrieval-2026-09-13-fixed.json) validates
  **30/30 single-source, 30/30 multi-source forward, 30/30 multi-source reversed,
  and 29/30 dense-only**. All thirty forward/reversed admitted passage sequences
  matched exactly. `meridian-term` is recovered in both orders; the unchanged
  dense-only `juniper-hotel` miss is recovered by hybrid retrieval in every scope.
  Total evaluation time was 11,013 ms (now includes an extra reversed-order run
  for every question, so it is not directly comparable to the earlier timings
  and is not answer latency). Runtime remained iOS 26.6.2 (23G90), English Apple
  embeddings revision 1, 512 dimensions, native context size 4096.
- Export validation confirmed 30 unique cases, consistent boolean totals, and
  retrieval-source hashes matching the current files. The original and repeat
  pre-fix exports remain unchanged. This is retrieval evidence only: no actual
  answer generation was performed. Windows CI for the correction remains pending;
  the old candidate's passing CI does not validate this working-tree change.

## Execution sequence

### Actual-model initial result — gate failed

The signed actual-model evaluator completed all 50 fictional comparison cases
and ten separate smoke turns on iOS 26.6.2 (23G90). The supplied fixture hash
matches the unchanged committed suite. No runtime failures or hard guardrail
refusals occurred; the failures below are answer quality, not deployment errors.
The original multiline build-define input failed compilation before deployment;
base64 encoding the same bytes resolved that packaging issue without fixture or
prompt changes. Static analysis passed.

The immutable [initial raw fictional report](../../eval/guardrails/v2-ios-26.6.2-initial-2026-09-13.json)
and [separate semantic grades/rerun selection](../../eval/guardrails/v2-ios-26.6.2-grades-2026-09-13.json)
record:

- **9/40 answerable correct**, 29 false abstentions, and two incorrect answers.
- **9/10 unsupported cases correctly abstained**; one asserted a crisis-service
  call not established by its fictional evidence.
- Zero hard refusals, verbal refusals, and runtime failures. Median initial
  end-to-end latency: 628.5 ms. Low latency does not compensate for failed quality.
- The two incorrect answerable outputs reversed an explicit assistance-animal
  deposit exemption and asserted family violence despite an explicit non-event
  disclaimer. These errors reached the user-visible result. Another native
  non-event assertion was intercepted by the app and became a false abstention.
  The presence-overlap screen is not proof of semantic support.
- General codename recall, summary use, complete transcript reopening, fresh-chat
  isolation, no General fallback in grounded mode, and original-scope regeneration
  passed the recorded structural checks. However, three General acknowledgments
  repeated an earlier codename instead of addressing the latest message. The
  initial multi-source answer abstained; its regeneration answered correctly.
  Do not describe all chat behavior as passing from structural booleans alone.

The evaluator removed its unique fixture database after completion. Only fictional
results were exported. The numerical initial score is fixed and falls far below
the recorded v1 gate (36/40 answerable, 10/10 unsupported, zero invented answers).
The required unchanged repeatability run completed all 32 non-passing cases plus
ten randomly sampled passes. The [raw repeat](../../eval/guardrails/v2-ios-26.6.2-repeat-2026-09-13.json)
and [repeat grades](../../eval/guardrails/v2-ios-26.6.2-repeat-grades-2026-09-13.json)
show **31/32 initial failures persisted**, including all three incorrect or
unsupported user-visible answers. `ACC1-LEG-A12` recovered from false abstention;
all ten sampled initial passes remained correct. This selected subset is not a
new full-suite score, and it does not replace the initial 9/40 and 9/10 results.
Fixture and source manifests match between runs; both fixture databases were
removed after completion. No generation prompt or native model behavior has
been changed in response to these results.

Owner click-through and offline/traffic checks are deferred while this quality
failure is unresolved. Next diagnose the v2 generation/prompt path versus the
current OS/model runtime using controlled tests, not prompt tuning against this
frozen acceptance suite. The retrieved excerpts visibly contain supporting facts
in inspected failed cases, but the root cause of the broader failure is not yet
established. Do not attribute it solely to retrieval, the OS upgrade, or model
size without a controlled comparison.

### Controlled generation diagnosis

The owner requested diagnosis of v2 prompt handling versus the current iOS model.
`v2_generation_diagnostic_main.dart` is a standalone development-only harness.
It selects five answerable and two unsupported cases from the committed
**development** suite, not the failed frozen acceptance suite. For each case it
captures the actual v2 engine prompt/native answer, then makes paired native calls:

- Original v2 JSON with unchanged v2 instructions.
- The identical JSON with existing v1 instructions (instruction-only contrast).
- Existing v1 instructions with canonical v1 excerpt/question format.
- Existing v2 instructions with intact rather than retrieved/chunked excerpts.
- Existing v2 instructions with the same JSON values but evidence first/question last.
- Existing v2 instructions with only JSON whitespace changed to pretty printing.

Each native variant runs twice, with variant order reversed on the second pass.
A separate General-mode development example compares compact JSON, pretty JSON,
and explicit role-labeled text while retaining the same facts and native General
instructions. These are diagnostic representations, not proposed production
changes. Native answers are observed before the app's overlap filter. The earlier
end-to-end evaluator already preserves filtered and native output separately.
No acceptance score is replaced by these development results, and no production
generation prompt/native implementation has been changed.

The first comparison completed 100 responses on the same iOS 26.6.2 device.
Raw fictional results: `eval/guardrails/v2-development-diagnostic-2026-09-13.json`.
The canonical v1 representation answered all five answerable examples correctly
on both repeats (10/10). Original v2 JSON/native instructions answered 6/10;
changing only instructions also answered 6/10. Intact excerpts and pretty JSON
each answered 6/10; evidence-first JSON answered 5/10. All unsupported-case
native calls abstained semantically (apostrophe formatting varied). The initial
General fixture did not reproduce the stale reply, so it was not treated as
evidence that the General bug was fixed or diagnosed.

A focused second run completed 43 responses, narrowing to `LEG-A08` (medical
diagnosis disclosure) and `MED-A04` (explicitly absent gastrointestinal diagnosis).
It added v1-format calls containing the **exact same retrieved passages in the
same order**, and intact-excerpt JSON with v1 instructions. Each knowledge variant
ran twice, reversing variant order on the second pass. Raw fictional results:
`eval/guardrails/v2-development-focused-diagnostic-2026-09-13.json`.

| Focused knowledge variant | Correct / 4 | Other outputs |
| --- | --- | --- |
| Current v2 JSON + v2 instructions | 0/4 | Four false abstentions |
| Same v2 JSON + v1 instructions | 3/4 | One false abstention |
| Canonical v1 + intact excerpts | 4/4 | None |
| Canonical v1 + matched retrieved passages | 4/4 | None |
| Intact-excerpt JSON + v1 instructions | 2/4 | Two false abstentions |
| Intact-excerpt JSON + v2 instructions | 0/4 | Four false abstentions |
| Evidence-first JSON + v2 instructions | 0/4 | Four false abstentions |
| Pretty JSON + v2 instructions | 0/4 | Four false abstentions |

Both actual-engine baseline calls also falsely abstained. The matched-passage
contrast rules out missing retrieved facts as the sole cause of these two
failures. It supports a prompt framing/instruction interaction on the current
model, not a claim that JSON universally fails. Canonical v1 framing also removes
JSON metadata/context fields, so this comparison does not isolate punctuation
alone. Small samples and variation between runs prevent broader reliability
claims. The results do not establish an iOS-version regression or explain every
incorrect/unsupported acceptance answer.

For General mode, the focused development fixture more closely reproduced the
original pattern: two earlier codename exchanges, followed by a request to
acknowledge a new meeting day. All representations retained identical messages
and native instructions; each ran three times:

- Compact JSON: stale `Copper Finch.` response on all three attempts; no Wednesday.
- Pretty JSON: `Wednesday.` on all three attempts, correctly addressing the latest
  message.
- Role-labeled text: `Copper Finch. Wednesday.` on all three attempts; the latest
  fact was included, but the obsolete codename still leaked into the answer.

This reproduces General's stale-answer symptom and isolates representation as a
contributing factor for this fixture. It does not validate pretty printing as a
complete solution for longer conversations, summaries, or instruction injection.

The owner approved the targeted production prompt-framing change on 2026-09-13.
Preserve mode separation, untrusted evidence boundaries, immutable source
scope/citations, and native token admission; add tests at the real prompt-building
seam, then run broader development/native checks before a separately recorded
quality-gate rerun. Keep the frozen initial and repeat failures intact. Manual
screen click-through and privacy sign-off cannot substitute for this failed
generation-quality gate. The diagnostic harness remains isolated under
`lib/evaluation/`; no production debug instrumentation was added.

### Prompt-framing remediation — development results

`general-v2` retains the same General instructions and messages but pretty-prints
JSON. `grounded-chat-v2` puts escaped chat context, source-labelled excerpts, and
the current question in separate sections, with the question last. Its native
instructions use the v1 transformation framing while preserving v2's explicit
context-versus-evidence distinction, source separation, no fallback/outside
knowledge, fixed abstention, and app-owned citations. The frozen `guardrail-v1`
path is unchanged. Escaping protects delimiters; it is not a claim that semantic
prompt injection has been eliminated.

Two new real-engine prompt-contract checks failed before the change, then passed.
They lock down the validated General serialization and escaped grounded framing,
including counting the exact prompt sent to generation. Fake-model tests cannot
prove native answer quality; that is evaluated separately on the device.
All 196 Flutter tests passed, static analysis reported no issues, and the additional
Dart/Swift instruction and version parity assertions passed. Owner-managed iOS
signing changes were preserved. The signed development evaluator built in 22.8 s
and launched without uninstalling or opening the regular vault.

The full 40-answerable/10-unsupported **development** suite completed through
the actual production engine and native backend, followed by continuity, summary,
restart, isolation, and two-source/regeneration probes. Candidate v2 produced
34/40 correct answerable results under semantic review, four false abstentions,
and two answers missing material conditions (an IP exception and a severance cap).
Nine of ten unsupported cases abstained; `LEG-U03` incorrectly inferred that a
permitted disclosure had occurred. General continued repeating the old codename
on its three acknowledgment turns. The small earlier formatting comparison did
not generalize. Native `LEG-A09` was correct but the app's overlap screen rejected
it; no overlap-screen change was made in this prompt-focused pass.

Candidate `general-v3` adds explicit latest-message instructions: earlier requests
are completed context, not instructions to carry out again. `grounded-chat-v3`
retains the v2 serialization and adds modality and material-condition guidance.
The native/Dart instruction strings and both versions match. All 196 Flutter
tests and static analysis passed again, including escaped prior-context delimiter
coverage. The signed v3 build completed in 22.1 s.

The v3 initial development run scored **37/40 answerable** and **9/10 unsupported**.
`MED-A19` and `MED-A20` falsely abstained; `LEG-A12` omitted the additional
no-confidential-information condition; `LEG-U03` still asserted an unsupported
event. There were no runtime failures or benign refusals. Median case latency
was 813.5 ms. Native answers and user-visible outputs are retained separately.
General answered the latest acknowledgment requests rather than repeating the
codename; the first acknowledgment mentioned the meeting day without restating
Tuesday. Codename recall before/after summary and reopening remained correct,
the fresh chat did not know the codename, and both multi-source responses were
correct with original-scope regeneration. Structural smoke checks all passed;
these do not by themselves establish answer quality.

Raw initial runs are `eval/guardrails/v2-prompt-v2-development-2026-09-13.json`
and `eval/guardrails/v2-prompt-v3-development-2026-09-13.json`; semantic judgments
and rubric are in `eval/guardrails/v2-prompt-development-grades-2026-09-13.json`.
An unchanged full repeat of the v3 development candidate completed: **33/40
answerable**, **9/10 unsupported**, with six false abstentions and the same
material-condition omission and unsupported event assertion. Four initially
passing answers additionally abstained (`LEG-A09`, `LEG-A13`, `MED-A04`,
`MED-A06`). General acknowledgment behavior, recall/summary/reopen, isolation,
and both multi-source answers remained correct under the same rubric. All
structural smoke checks passed. Raw repeat and grades are in
`eval/guardrails/v2-prompt-v3-development-repeat-2026-09-13.json` and
`eval/guardrails/v2-prompt-v3-development-repeat-grades-2026-09-13.json`.
The unchanged binary was relaunched, so the embedded runNumber remains 1; distinct
timestamps and export directories identify initial versus repeat. Both fixture
databases were removed by the evaluator, with only fictional exports retained.
**Still not release-ready:** improved prompt handling does not resolve the
unsupported assertion or all answer-quality failures. Do not weaken the evidence
filter to obtain a passing score. A semantic-grounding investigation remains.

Acceptance attempt 1's historical results remain immutable; because tuning has
resumed, it must not be recycled as the release gate for these new prompts. Freeze
the candidate and create a fresh acceptance suite only after development checks.

### Remaining grounding diagnosis — 2026-09-13

The owner approved investigating the remaining failures. This diagnosis changed
no production prompt, filter, retrieval, or native implementation.

`flutter test tool/diagnostics/grounding_replay_test.dart` reproduces two opposite
semantic failures through the real ChatEngine and evidence-persistence path:
`LEG-A09` rejects a correct captured native answer and `LEG-U03` accepts the
captured invented event. Both fail identically on a second run. The same command
with `--dart-define=MINIMIZE=true` reproduces both with one-sentence evidence.
These known-red diagnostics are intentionally outside the portable suite; they
are not passing regression coverage. Model responses, embeddings, and token counts
are controlled doubles in this replay, so it does not measure native generation.

The exact overlap scores are 5/11 (45.45%) for the correct paraphrase and 12/15
(80%) for the unsupported assertion, against a 50% cutoff. `prevent` versus
`prevents`, `discussing` versus `discussion`, and negation words contribute to
the false rejection; the invented answer retains most source nouns while changing
permission to an asserted event. No adjustment of this single lower-bound
threshold can accept the lower-scoring correct answer and reject the higher-scoring
invention. This is a limitation of the lexical screen, not missing evidence.

A separate standalone native diagnostic completed 63 responses on the same
iOS 26.6.2 (23G90) device. Six development cases each ran five variants twice
(second-pass variant order reversed), plus three neutral-question controls:

- Current v3 instructions with source-labelled framing.
- Same v3 instructions with canonical plain excerpt/question framing.
- Existing v1 instructions with each of those two representations.
- Current v3 framing with only the first captured passage (removing overlap).

Passage text/order, question, native model settings, and token admission were
held constant within each framing/instruction contrast. Source identifiers were
normalized to fictional fixture IDs instead of the earlier random vault IDs;
therefore the source-labelled baseline is a reconstructed prompt, not a byte-for-
byte replay of the original app prompt. Plain framing removes metadata and empty
chat-context framing together. Every prompt was native-token-counted with the
640-token reserve. No expected answer was sent to generation, and no vault was
opened. All 63 calls completed without native runtime errors.

| Case | Results across the ten paired calls |
| --- | --- |
| Salary control (`LEG-A03`) | 10 correct |
| Correct pay-discussion paraphrase (`LEG-A09`) | 9 correct; first-passage-only variant contradicted the source once |
| Partner notes access (`MED-A19`) | 8 correct; 2 false abstentions; plain framing answered correctly on both repeats |
| Workplace letter (`MED-A20`) | 7 false abstentions; 3 incomplete answers omitting the permitted functional disclosure |
| Unsupported bonus control (`LEG-U01`) | 10 correct abstentions |
| Unsupported reporting event (`LEG-U03`) | 8 unsupported assertions; 2 correct abstentions |

For `LEG-U03`, changing only the question to ask whether the excerpt establishes
that contact actually occurred yielded three correct abstentions. This supports
susceptibility to a question's unsupported event premise. It does not establish
that automatic question rewriting or a second model judgment will reliably solve
it. Existing v1 instructions and simpler framing still failed some cases; there
is no demonstrated universal prompt-only remedy, and no OS-regression claim is
supported by this experiment.

Raw fictional results and semantic grades:
`eval/guardrails/v2-grounding-diagnostic-2026-09-13.json` and
`eval/guardrails/v2-grounding-diagnostic-grades-2026-09-13.json`.
The isolated harness built successfully in 19.1 s; static analysis passed.
The normal portable suite still passed all 196 tests after the diagnostic additions;
the separately invoked known-red semantic replays remain unresolved.
The diagnostic helper documentation is `tool/diagnostics/README.md`.

**Recommendation for owner decision:** evaluate an evidence-first answer and
verification pipeline on development cases before implementing a replacement
for the lexical screen. Exact supporting quotes can be checked against admitted
passages, but quotation presence alone does not prove that a generated claim is
entailed; false premises, negation, conditions, latency, and unsupported-output
streaming need explicit tests. This is a generation/validation design change,
not a threshold tweak. Until it is demonstrated and approved, keep production
behavior unchanged and #29 blocked; no click-through or fresh acceptance suite
is warranted yet.

### Separate semantic verification implementation — work in progress

The owner approved a separate on-device inference call before displaying grounded
answers. The implementation replaces the lexical overlap screen with a fresh
Foundation Models session in a distinct `grounded-verification` mode. General
mode and frozen v1 generation are unchanged. The captured turn records the
verification prompt version alongside the generation version.

Knowledge Base draft snapshots remain in memory only; none are saved to the
transcript or displayed. After generation completes, the exact admitted evidence,
original question/context, and escaped draft are sent for verification. Only a
completed exact `SUPPORTED` label admits the draft. `CONTRADICTED` or
`NOT_ESTABLISHED` yields the existing fixed insufficient-evidence response and
existing source cards. Malformed/empty labels or native errors fail closed without
exposing the draft. Numeric model-authored citation markers are still rejected;
the percentage-overlap and exact numeric-presence heuristics are removed.

Verification has its own native token preflight, including the draft, a 32-token
native output limit plus 128 framing tokens, and a 30-second total stream deadline.
Generation is fully released before verification starts. Stop/backgrounding
cancels either stage and never preserves unverified grounded text. This changes
grounded streaming intentionally; General streaming remains unchanged. No new
vault schema, network provider, account, or regular-vault transition was added.

The two historical semantic failures were reproduced before implementation.
They now pass through the real engine with controlled verifier verdicts. These
are admission tests, not evidence that the real verifier is correct. The full
portable suite passed 205 tests after additional final-verdict coverage; analysis
was clean. Tests cover invalid labels, native errors, verification context overflow,
hidden drafts, Stop, suspension, immutable provenance, and bridge/instruction parity.

**First native development candidate (`grounded-verification-v1`): failed quality.**
The signed build completed in 22.1 s and ran all 50 development cases plus ten
smoke turns. The verifier returned valid labels but accepted only 11 correct
answerable drafts, yielding 11/40 answerable correct and 10/10 unsupported
abstentions. It rejected the invented event and the answer missing a material
condition, but also rejected 25 correct drafts. Three answerable cases abstained
at generation and therefore never called verification. This is overly conservative,
not a release pass. Raw results: `eval/guardrails/v2-verifier-v1-development-2026-09-13.json`.

A separately versioned development candidate (`grounded-verification-v2`) simplifies
the verification instructions and adds an explicit final classification question.
It retains the same support requirements but clarifies concise/equivalent wording.
Generation instructions and retrieval are unchanged. The signed v2 candidate built
in 22.3 s. All 205 portable tests and static analysis pass. The original captured
failure replays now pass with explicitly controlled verifier verdicts; they do not
claim native verification accuracy.

The v2 candidate completed all 50 development cases plus ten smoke turns with no
runtime failures or malformed labels. It scored **35/40 answerable correct** and
**9/10 unsupported abstentions**. Four answerable cases abstained: `LEG-A12`
(verifier correctly rejected an incomplete draft), `LEG-A19` and `MED-A19`
(verifier falsely rejected correct drafts), and `MED-A16` (generation abstained;
no verification call). `MED-A20` was accepted despite changing a statement that
remote attendance may help into language describing actual attendance and omitting
the disclosure restriction. The verifier also returned `SUPPORTED` for `LEG-U03`'s
invented reporting event. Thus a second call to the same model can repeat the
generator's semantic error; successful call routing is not proof of grounding.

Median end-to-end case latency was 1,419 ms (v1 verifier: 1,485 ms; earlier
generation-only v3 development run: 813.5 ms). These are whole-pipeline medians,
not isolated verifier latency or a controlled speed comparison. The 50-case v2
run made 40 verification calls. General never called the verifier, and its smoke
responses, summary/reopen recall, and isolation remained correct. Both multi-source
answers passed semantic review and verification, retaining original regeneration
scope. Fixture databases were removed; only fictional exports remain.

Raw and graded evidence: `eval/guardrails/v2-verifier-v2-development-2026-09-13.json`
and `eval/guardrails/v2-verifier-development-grades-2026-09-13.json`. Both candidate
initial scores are retained separately. No fresh acceptance suite has been created.

**Implementation is present but experimental/unmerged, not a validated release
fix.** The stricter candidate blocked too many valid answers; the simpler candidate
still accepted an unsupported event. Do not ship this as a reliable semantic
verifier or claim that #29 passed. A different verification approach/model or a
more constrained evidence-display behavior needs a separate decision and testing.

Native Runner XCTest also passed **22 tests with no skips** on the physical
iPhone after enabling testability on the Release host. The first attempt did not
run tests because `@testable import Runner` requires `ENABLE_TESTABILITY=YES`;
the invocation-only retry passed, including the added verification-mode routing.
Result bundle: `/private/tmp/sekret-29-verifier-native.cdvpDG/retry.xcresult`.
This verifies native bridge mechanics, not semantic answer reliability.

### Actual-model evaluation method

`lib/evaluation/v2_generation_acceptance_main.dart` is an isolated entry point,
not imported by production. It receives the unchanged committed fictional
acceptance JSON through build defines, imports its 20 excerpts as knowledge
items, and runs all 50 questions through the real v2 ChatEngine, Apple embeddings,
native token admission, and Foundation Models generation. Each case has a fresh
chat scoped only to its fixture-provided excerpt IDs. Expected answers are retained
for grading but never sent as prompts or evidence. This is a controlled v1-case
comparator using the v2 `grounded-chat-v1` prompt, not a claim that the frozen
`guardrail-v1` prompt was used or a new unseen acceptance set was created.

The observer records native final snapshots/errors separately from user-visible
terminal outputs so app-filtered abstention is not confused with native refusal.
All content is fictional. Each run has its own export directory, checkpoints
after each case, a 60-second per-turn stop timer, and interruption invalidation.
The unique temporary fixture database is closed and removed after the run; only
fictional JSON results remain. Never copy the regular vault or treat an incomplete
run as passing. Source hashes, runtime, prompt versions/hashes and fixture hash
identify the actual implementation under evaluation.

Initial results require semantic grading against the supplied fictional excerpts
and expected answers: correct, conservative abstention, incorrect/invented answer,
verbal refusal, hard guardrail refusal, or runtime failure. Exact unsupported
abstention is checked separately. The numerical initial score is immutable; rerun
every non-passing case plus ten randomly selected passes after initial grading,
and retain those as repeatability evidence. Do not tune on this frozen suite.

Separate actual-model smoke turns check General follow-ups, summary continuity,
retained full transcript across a database reopen, fresh-chat isolation,
multi-source answering, and regeneration after changing the current scope.
Structural booleans are not a substitute for reviewing the fictional outputs.
This does not replace owner screen-level, offline, or traffic verification.

1. **Storage and connection prerequisites.** Mac had only 1.3 GiB available at
   kickoff. Hold native builds and traces until adequate headroom is available;
   target roughly 5–10 GiB before the whole gate. Ask before removing any caches.
   Connect/unlock the iPhone by USB for device checks. Storage was sufficient to
   resume on 2026-09-13; continue checking headroom before capture.
2. **Native regression.** Run the existing Runner XCTest suite using a Release
   host and an isolated acceptance entry point. Record actual test/pass/skip
   counts. Cover OCR, embeddings, tokenizer, mode routing, generation/streaming,
   cancellation/interruption, stable errors, authentication policy, file
   protection, and confined import cleanup. Real Face ID/snapshot behavior is
   owner-observed, not proved by mocked authentication tests.
3. **Aggregate integrity.** Exercise a fresh disposable v2 schema, supported
   upgrades/refusal of unknown/v1 schema, source deletion/cancellation, chat
   deletion/tail deletion/reaping, and Erase All. Check SQLite integrity,
   foreign keys, orphaned rows, FTS/index consistency, and expected retained
   provenance using fictional data only. Do not copy/open the regular vault.
4. **Actual v2 retrieval.** Reuse the six-document/30-question fictional corpus
   through `KnowledgeBase` with Apple embeddings and the production tokenizer.
   Record single-source baseline and multi-source behavior separately. v1
   baseline is hybrid 30/30 and dense-only 29/30. The generic historical 0.80
   threshold alone is insufficient for #29's "meet or exceed" criterion.
5. **Actual v2 generation and guardrails.** Verify General and grounded turns,
   follow-ups, original-scope regeneration, summaries, retained full history,
   exact insufficient-evidence wording, no fallback, and no cross-chat memory.
   Reevaluate the committed synthetic guardrail acceptance cases through the
   v2 engine; retain only fictional results/aggregate grades and latencies.
   Historical v1 acceptance: 36/40 answerable correct, 10/10 unsupported abstained,
   zero benign refusals/invented answers. Record required reruns rather than
   replacing the initial score with retry results.
6. **Signed Release offline workflow.** Owner disconnects from the Mac, enables
   Airplane Mode and explicitly disables Wi-Fi, then exercises General and
   multi-source chats plus text/PDF/scanned-PDF/photo ingestion, indexing,
   previews/citations, reopen, and deletion in an isolated vault. Sources must
   already be stored on the phone; cloud-provider downloads are not an offline
   app capability. Report outcomes and approximate latency, not private content.
7. **Traffic verification.** Separately reconnect for an Instruments Network
   Connections recording targeted at the actual Sekret/Runner process. Keep
   HTTP Traffic disabled; do not collect payloads. Record a bounded complete
   workflow and confirm the capture covers the actual interaction interval.
   Do not substitute a failed-to-start/offline trace for a zero-traffic result,
   or attribute unrelated Unknown/device traffic to the app.
8. **Release decision.** Record exact revision/build/runtime, results, latency,
   remaining exceptions, and the empirical privacy finding. Any source change
   after a run invalidates only the affected evidence, which must be rerun.
   Keep #29 open until every gate is genuinely supported.

## Evaluation gap identified

The existing `RETRIEVAL_QUALITY_EVALUATION` and
`FOUNDATION_MODELS_EVALUATION` launch flags invoke the v1 `DocumentLibrary` path.
The standalone guardrail harness likewise uses the frozen v1 prompt. Those can
remain useful v1 regressions, but must not be reported as evidence that the v2
`KnowledgeBase.retrieveAcross` / `ChatEngine` paths passed. A v2 evaluation path
or explicitly recorded v2 manual run is required before claiming that gate.

`lib/evaluation/v2_retrieval_acceptance_main.dart` now supplies the v2 retrieval
probe. It uses Apple embeddings/native tokens, the real Knowledge Base, and the
real ChatEngine prompt-admission path in an in-memory vault. Each question has
a fresh chat, first scoped to its source and then to all six fictional sources.
Relevance requires the correct source ID and heading among the engine's admitted
passages, not merely a matching heading in another source. Dense-only top-four
candidate recall is reported separately (the engine has no dense-only mode).
The generation adapter deliberately returns the fixed abstention after evidence
capture: **no answer generation or guardrail behavior is evaluated by this probe**.
Per-question hit booleans and metadata are fictional/aggregate only. A backgrounded
run is invalidated rather than reported as a pass.

## Safety notes

- Existing local signing changes remain uncommitted and must be excluded from PRs.
- Keep the TEST DATA acceptance app until review is finished; don't silently
  install the default v1 app and represent it as the tested v2 build.
- Never uninstall/reset the app to make a check pass. Integration commands, if
  needed for non-UI scenarios, must retain `--no-uninstall`.
- Avoid unbounded packet captures. The previous run exhausted disk space; the
  preferred app-targeted Instruments trace is separate from offline validation.
- Only the two explicitly approved generated build-output directories were
  cleaned. No production-vault transition has been authorized.

## Decision

**Not release-ready: actual-model quality gate failed.** Windows, fresh non-UI/native tests, and local aggregate integrity
checks passed. The validated first-run export confirms single-source retrieval
meets the v1 baseline. The multi-source ordering defect is fixed and the physical
corpus passes in both selection orders. Fresh Windows CI for the correction,
actual model/guardrail remediation and reevaluation, offline,
traffic verification, and any regular-vault transition remain separate gates.

## Fixed-answer verifier follow-up — 2026-09-13

The owner approved an isolated alternative-model download and comparison.
The 28-case balanced fictional suite is frozen and hashed before verifier-only
inference, with three retained repetitions. DeBERTa-v3-xsmall FP32 and ARM64 INT8
each made 9/42 false approvals and 9/42 false rejections (three distinct cases of
each, repeated consistently), with no runtime or overflow failures. The published
tokenizer paths matched 28/28 inputs. This candidate is not recommended for app
integration; the experiment did not change production code or dependencies.

The new Apple fixed-suite baseline initially could not launch because iOS reported
the phone locked. After owner unlock it completed all 84 checks: 13/42 false
approvals and 11/42 false rejections, zero runtime/invalid-label failures, median
327 ms verifier-only latency. The captured invented reporting event was admitted
on all three repetitions. Independent frozen-fixture scoring exited 1. The export
and source hashes are preserved and verified; earlier changing-draft results are
not substituted. Both approaches fail this development screen. Static analysis
was clean, 211 portable tests passed, and the signed isolated harness built
successfully before this unchanged device run. No release pass or PR.

Full methods, input-protocol caveats, saved results, resource measurements, and
reproduction commands: [fixed verifier comparison](fixed-verifier-comparison-2026-09-13.md).

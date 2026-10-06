# Qwen3-4B-Instruct-2507 isolated evaluation

Not a shipping adapter, model installer, reviewed catalogue entry or iPhone qualification. The user approved this single 2.50 GB download after the research/size disclosure. No other weights or runtime are required.

## Development result — 2026-10-06

All 30 answers completed, with **26/30 full task passes**, below the predeclared 27/30 threshold. Everyday 4/5; facts 5/5; missing information 5/5; arithmetic 2/5; source-instruction boundaries 5/5; language/format 5/5. Two arithmetic answers were wrong, one correct calculation violated number-only formatting, and one message introduced an unsupported rationale (conservative manual judgment). See [per-case grades and limitations](BROADER-GRADES-2026-10-06.json). No iPhone or catalogue approval follows. The follow-up diagnostic is complete; the GGUF is retired for storage cleanup while metadata, reports, runtime and harness remain.

The original nine answers, the separate 21-case continuation, and the failed pre-generation restricted-environment launch are all preserved. All 30 successful logs confirm Apple M2 / 37-of-37 GPU layers, and publisher/native token parity passed all 30 inputs. Do not report controlled speed comparisons from this interrupted, initially disk-constrained run. The storage guard's four tests and the nine shared collector/report tests passed after resuming.

## Provenance

Unsloth community conversion `Qwen3-4B-Instruct-2507-Q4_K_M.gguf`, revision `a06e946bb6b655725eafa393f4a9745d460374c9`, 2,497,281,120 bytes, SHA-256 `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597`. The converter identifies the Qwen source model but does not attest its exact source-weights revision. Inspected publisher metadata/template revision is `cdbee75f17c01a7cc42f958dc650907174af0554`; do not claim this was necessarily the revision converted. Apache-2.0 source licence screening is not a full redistribution audit. See [research and immutable links](../../docs/evaluation/next-text-candidate-2026-10-06.md).

The local package reuses `../local_generation/artifacts/build-apple/llama.xcframework` through an ignored symlink. Runtime remains llama.cpp b11429, commit `d81235049384534c167caea52b85a694f6103d14`. No previous model adapter, baseline result or shipping app was modified. The new adapter derives from the bounded Qwen0.6B harness but has separate pins and template; native cancellation helpers preserve the same limitations (no proof of immediate Metal abort or actual UI Stop/background behavior).

## Fixed profile

`profile.json` is frozen before generation: single-system/single-user ChatML; **no BOS and no empty-thinking suffix**; tokenizer `add_special=false`, `parse_special=true`; native first token must be 151644 and no 151643 pad/end-of-text appears in input. Native EOS must be 151645 and both 151645/151643 must be end-of-generation tokens. This deliberately narrow profile does not implement tools, images or chat history.

Sampling is top-k20 → top-p0.8 → temperature0.7 → fixed-seed42 distribution, no repetition/frequency/presence penalty, min-p disabled. Context2048, output128, four CPU threads maximum, Metal99 layers. Exact complete prompt plus output reservation must fit, without truncation. The publisher's more generous general output recommendation is not this resource-bounded screen.

## Commands

From repository root, after approval and checking free space:

```sh
bash experiments/qwen4_text/fetch-approved.sh
swift test --package-path experiments/qwen4_text -c release
python3 experiments/qwen4_text/run_evaluation.py
```

For the interrupted `broader-o6ogzahr` run, do **not** start a new screen or overwrite its answers. Resume with:

```sh
python3 experiments/qwen4_text/resume_evaluation.py experiments/qwen4_text/results/broader-o6ogzahr
```

The continuation requires 8 GB free initially, checks a 3 GiB reserve throughout each native process, and verifies the original binary/model/profile/reference hashes plus all 30 publisher/native token sequences. It preserves the original manifest and nine completed outputs (including the separately audited ninth result), writes `continuation.json` separately, and refuses to silently retry failed attempts or replace unrecorded outputs. The native process needs Metal GPU access: the restricted launch failed at context creation before producing an answer; its empty output, full log, and audit are retained under `sandbox-launch-failure/`. The GPU-enabled retry uses unchanged inputs and sampling. This interrupted run is not a controlled latency benchmark.

The fetch script verifies exact byte count and SHA before renaming the sole partial file. It requires at least 4.5 GiB free before fetching, leaving an operational reserve; it does not download a projector/runtime or run inference. The symlink to the existing runtime must already be present for Swift build. All weights, references, binaries and raw runs are ignored. Preserve result reports and exact metadata when retiring model weights.

The offline runner first hash-checks weights, copies the frozen 30-case suite/profile to a unique run directory, and records source metadata/executable hashes. A separate `--tokens-suite` mode loads the model and exports all 30 native prompt/token sequences **without generating answers**. Existing isolated Hugging Face `tokenizers==0.22.2` at `../liquid_text/artifacts/diagnostic-reference/python` independently checks every sequence against the publisher's tokenizer JSON. This uses an already-installed small test library, not the removed Liquid model. Admission failure stops before the quality run and preserves its log.

Only after admission does the runner generate all 30 cases once, serially, with a fresh process per case and a 120-second process timeout. It validates every result against the frozen profile, admitted prompt/token hashes, and shared report contract. Malformed results, errors and incomplete outcomes remain visible; they do not count as completed generation. A successful generation is never automatically a quality pass. Manual grading uses the unchanged required/forbidden criteria and predeclared gate in `broader-text-v1.json`.

Timings distinguish native load from generation/context/prefill and overall process duration. Model hash, OS, sampling, exact token counts/hashes, thermal state, sampled physical footprint and process-lifetime peak RSS are recorded. File/shader caches and host load are uncontrolled, so do not infer an iPhone speed/memory limit or rank models solely by these short Mac timings. A passing development screen would still require fresh validation and device qualification, separately for General and Knowledge Base capabilities.

## Focused diagnostics

`diagnostic-plan.json` fixes four failed cases and one positive control before running comparisons. `run_diagnostic.py repro` repeats the original packs-and-singles input twice using the hash-pinned, unchanged Swift executable; exit 1 means the answer still differs from 26. This is a deliberate red-capable quality check, not an infrastructure failure. Original prompts are kept whole to avoid introducing a wording confound.

`build-diagnostic.sh` builds a separate small C++ caller against the same native framework without rebuilding the Swift executable. `run_diagnostic.py controls` compares its original top-k20/top-p0.8/temperature0.7/seed42 sampling with greedy selection. No new model/runtime is downloaded. Both controls validate exact prompt/token hashes against the original reports, use the same Metal backend/context/output budget, and retain every result. The caller additionally records the raw first-token top eight logits and exact token roundtrip for inspection; this does not certify the shared runtime. Each process has the same storage guard and timeout as the continuation.

These failure-focused comparisons are diagnostic only. Do not substitute their answers into the original 30-case run, infer a new accuracy score, or treat a passing subset as iPhone qualification. A sampling change is a new profile requiring separate full evaluation and fresh validation.

The completed [diagnostic results](DIAGNOSTIC-RESULTS-2026-10-06.json) contain 14 generations: two unchanged original-executable arithmetic repeats, ten baseline/greedy comparisons, and two supplemental backend/API checks declared in `diagnostic-backend-plan.json`. The separate caller reproduces all five original subset answers exactly. Greedy fixes the unsupported meeting rationale, but both arithmetic misses and the number-only formatting miss remain. The card-count error also persists on CPU and through the extended decoding API. No simple caller/sampling/backend fix was found; this does not distinguish model limitations from quantization/conversion or a shared native runtime problem. The original 26/30 score and shipping app remain unchanged.

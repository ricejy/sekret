# Local model comparison — development screen

This suite is deliberately small and includes failures already observed during Qwen3-0.6B and SmolVLM-500M development. It is **not a held-out benchmark**, a trustworthy overall accuracy percentage, or approval to ship. All inputs are fictional or repository-owned; no personal documents or Photos are used.

`development-v1.json` freezes ten text requests and three image requests with human-readable required/forbidden criteria. It tests direct completion, multilingual instructions, source boundaries, missing information, elementary arithmetic, and format compliance. It does not test retrieval, conversation continuity, the production verifier, broad visual understanding, or adversarial robustness. Do not use it to select a model and then call the same cases independent validation.

## Comparable runs

- Use exactly the same user request, source text/image, 2048 context and 128 generated-token cap. Record the suite SHA-256 and image SHA-256 with results. No silent truncation or omitted failures.
- Text models use the suite's identical system instruction. Vision baseline has no system turn: record this distinction and compare within modality only.
- Use each publisher's verified native template/tokenizer/image preprocessing. Record template, sampling, quantization, runtime, device, OS, context, input/output tokens, and reasoning mode; these can prevent a controlled head-to-head claim.
- A reasoning model that exhausts its cap before a final answer has **not completed the task**. Any longer-budget experiment is a separately labelled configuration, not a replacement for the fixed-budget result.
- Run serially, with no unrelated inference. Keep fresh-process load+hash latency distinct from generation latency and TTFT. This baseline runner reloads each case: it cannot measure retained-model chat latency.
- Mac results are a cheap screening step. Only promising candidates proceed to physical-device memory, cancellation, suspension, sustained load and offline qualification. Installed artifacts must pass pinned byte count and SHA-256 checks before parsing.

## Manual grading

For each returned answer, retain the unedited output and terminal outcome, then record:

1. **Task completion:** pass only if all required criteria hold. List each missed criterion; a helpful but incomplete answer is still incomplete.
2. **Unsupported claims:** separately flag every contradicted or invented factual claim. A format error alone is not fabrication. For image cases inspect the original pixels, not a generated caption.
3. **Abstention:** on missing-information cases, distinguish correct abstention from an invented answer; on answerable cases, flag unnecessary abstention.

Runtime errors, timeouts, incomplete UTF-8 and output-limit endings remain visible, never silently excluded from totals. A completed runtime outcome does not automatically pass quality. No word-overlap judge or model-generated score is used. Do not display a single user-facing “quality” score from this development screen.

## Existing baseline runner

`python3 run_baseline.py qwen` runs the ten text cases using the already-built, pinned local Qwen executable. `python3 run_baseline.py smol` runs three visual cases using the already-built SmolVLM executable. Neither command downloads, builds, installs, or touches the shipping app. A unique ignored result directory holds prompts, outputs, logs and a manifest. Each subprocess has a 120-second timeout and runs serially. Stronger models need their own verified adapter before joining this runner; arbitrary model paths are deliberately not accepted.

The suite's context/output settings match both existing harnesses; the runner rejects changed settings instead of pretending they applied to a fixed-configuration binary. For Qwen the baseline system instruction is fixed in `EvaluationCLI/main.swift`; the runner checks that it still matches before launch. Pinning build provenance remains necessary for a future formal benchmark.

Collector-only tests (no models or inference): `python3 -m unittest discover -s experiments/model_comparison -p 'test_*.py' -v`. These exercise result collection, timeout/nonzero preservation and changed-configuration rejection.

New text adapters must pass `validate_text_report.validate_report` against a separately frozen candidate profile containing `modelSHA256`, `runtimeTag`, `templateVersion`, `sampling`, `context` and `output_cap`. The validator rejects declared provenance/configuration mismatches, missing native token hashes, and context/output overflow; it preserves incomplete outcomes without claiming completion or quality. This checks report consistency, not whether an adapter truthfully implements its declared template. Verify actual prompt/token parity against publisher data separately, before interpreting quality differences. Five additional model-free tests cover this contract.

## Next-candidate protocol after the Liquid diagnostic

1. Confirm one exact artifact and download size with the user. Prefer a non-thinking instruction candidate with documented source-model/converter provenance; explicitly distinguish a community GGUF from a publisher-produced file. Keep at least 1.5 GiB free after model/build staging. A file size is not a RAM admission threshold.
2. Preserve previous harness defaults, binaries/results and failed scores. Use a separate candidate adapter and a frozen profile; do not inherit Liquid's BOS or penalties, or Qwen3-0.6B's empty-thinking prefix without verifying the new model's native requirements.
3. Before the quality run, check exact weight bytes/hash, source template, token IDs/special tokens, native runtime support and model-specific sampling. Run the report contract and a load smoke check. Record any compatibility failure rather than automatically changing runtime or quantization.
4. Run the existing `broader-text-v1.json` once with the same 2048 context, 128 output cap, system/user texts and predeclared screening rule. No favorable retries or retroactive edits to criteria. Grade all 30, distinguishing substantive errors, source-scope violations, abstention and format-only mistakes. This is the same development set, not fresh held-out evidence.
5. If it passes that gate, freeze a new validation set before testing further; only then consider physical-device resource/lifecycle testing. Do not ship or enable Knowledge Base support based solely on a development score. Stop on failure and report the next decision instead of silently downloading more models.
6. Retain only weights still needed for active evaluation. Remove retired weights at the user's request after saving results, hashes and recovery references; preserve the shared runtime. Do not remove phone apps/data as a side effect of Mac storage cleanup.

The next catalogue decision requires a fresh, broader test set plus licensing review and physical-device evidence. Neither this suite nor isolated model downloads change ADR 0001's no-network shipping policy; an explicit download-policy decision is still needed before app integration.

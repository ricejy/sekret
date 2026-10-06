# Isolated LFM2.5 text evaluation

Mac-only development harness; no shipping app integration or iPhone deployment. It reuses the approved llama.cpp b11429 XCFramework from `../local_generation/artifacts/build-apple/llama.xcframework` through the ignored `artifacts/llama.xcframework` symlink. Source is deliberately isolated from the preserved Qwen adapter; copied native lifecycle/cancellation helpers retain the same limitations. No package downloads are required.

Latest decision: the [broader 30-case screen](BROADER-RESULTS-2026-10-06.md) achieved only 15 complete passes, with eleven substantive failures. The [completed diagnostic](DIAGNOSTIC-RESULTS-2026-10-06.md) found token parity for all 30 prompts and persistent failures across five controls, not a simple harness fix. **Do not advance this configuration to the phone or catalogue.** Earlier results remain intact. The now-unused model GGUF was removed at the user's request after diagnosis; inference commands below require re-fetching its exact pin. Model-free tests and retained-evidence tokenizer parity still work.

Approved/downloaded artifact: `LiquidAI/LFM2.5-1.2B-Instruct-GGUF` revision `8ed288026e23958ad9dfa92d53ed773a8eee7125`, `LFM2.5-1.2B-Instruct-Q4_K_M.gguf`, exactly 730,895,168 bytes, SHA-256 `b1b3de114215d9507409a662a501a631095a479a419584e8a2ded6304b19b4f5`. [Pinned source/license and rationale](../../docs/evaluation/stronger-text-candidate-2026-10-06.md) · [Results](RESULTS-2026-10-06.md).

The artifact is in ignored `artifacts/`; results and build output are ignored too. Do not commit model weights. The profile checks exact size and SHA before native parsing on every process invocation. Download to a partial file, verify against the above immutable pin, then rename; preserve >1.5 GiB free disk and account for other agents' pending downloads. The research note contains the exact download URL for recovery if unused weights are later removed. Download permission does not authorize publishing/distributing the custom-licensed weights.

From this directory:

```sh
swift test -c release
python3 run_development.py
python3 run_development.py --suite ../model_comparison/broader-text-v1.json
python3 -m unittest discover -s . -p 'test_runner.py' -v
```

The runner never downloads/builds. It checks the model, system instruction, 2048 context and 128 output cap; it runs frozen text cases serially with a 120-second per-process deadline (the original ten-case suite by default). Each case is a fresh process/model load. A unique ignored directory contains the frozen suite, raw response JSON, native logs, exact prompts and a manifest including suite/model/executable/prompt/report hashes. Failures remain in the manifest and cause a nonzero final exit, including malformed reports and non-completed native outcomes. Valid JSON and successful generation do not imply answer quality; review raw outputs. Use the shared comparison README's manual required/forbidden/abstention rubric.

Prompt profile: explicit BOS, native ChatML single nonempty system/user turns, no tools/history/images, no Qwen thinking suffix. Native tokenizer runs with `add_special=false`, `parse_special=true`; exactly one native BOS token is checked. Prompt/control-marker rejection and exact template tests avoid accidental special-token injection. GGUF load logs confirm LFM2 architecture, LFM2 pre-tokenizer, BOS 1, EOS 7 and Q4_K-Medium. The pinned GGUF's full historical Jinja text may differ from the current source-model template; only the explicitly tested single-turn subset is implemented.

Sampling: repetition penalty 1.05 over 2048 recent tokens including input, frequency/presence zero; top-k 50; temperature 0.1; seed 42; no top-p filter. That penalty window/order/seed is our explicit evaluation configuration, not a claim that the publisher specified every default. Native repetition sampling accepts input history before sampling. The runtime captures exact prompt-token count/hash and refuses prompt-plus-output overflow, samples physical footprint, and preserves valid UTF-8 streaming.

Five Swift tests passed. The comparison is not held-out, not an overall accuracy estimate and not catalogue approval. The model is text-only; Knowledge Base, actual UI Stop/background, physical iPhone memory, repeated turns, sustained thermal/power and offline qualification remain untested. A SIGINT or between-token cancellation path is not proof of in-flight Metal cancellation. No production networking exception is made here.

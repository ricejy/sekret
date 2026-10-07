# Isolated local-generation evaluation

This is **not a shipping model adapter, installer, reviewed catalogue entry, or device qualification**. It never opens a network connection. It loads one hash-pinned local GGUF and produces native measurements for fictional test prompts. No Runner project, app signing, app networking, ADR, or Flutter dependency is changed.

## Dependencies and provenance

See `artifacts.json` for the exact publisher URLs, revisions, bytes and SHA-256 values. The user authorized these isolated evaluation downloads on 2026-10-06:

- MIT llama.cpp b11429 XCFramework: 61,992,495 bytes compressed; source commit `d81235049384534c167caea52b85a694f6103d14`.
- Apache-2.0 Qwen3-0.6B Q8_0 GGUF: 639,446,688 bytes; publisher revision `23749fefcc72300e3a2ad315e1317431b06b590a`.

Both size and SHA-256 were verified before use. Runtime unpacked footprint was approximately 209 MiB. License texts reside alongside the ignored local artifacts. These license declarations are not a completed redistribution audit. `artifacts/`, `.build/`, `.swiftpm/`, and `results/` are gitignored; never commit weights or native binaries.

Primary metadata: [runtime release](https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/b11429), [model metadata](https://huggingface.co/api/models/Qwen/Qwen3-0.6B-GGUF?blobs=true). Native interfaces follow the [pinned header](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/include/llama.h).

The Swift package uses a **local** binary target at `artifacts/build-apple/llama.xcframework`, not a remote dependency. A fresh checkout therefore fails to build until an explicitly approved retrieval supplies and verifies that dependency. Do not replace the pinned runtime with an unreviewed download to make the build succeed.

## Mac run

Storage cleanup, 2026-10-06: the Mac's Qwen GGUF was removed at the user's request after preserving the [shared comparison baseline](../model_comparison/BASELINE-2026-10-06.md). The shared runtime, reports and phone installation remain. Generation commands below require re-fetching the exact model from `artifacts.json`; model-free unit tests do not.

Requires Apple Silicon macOS, Xcode and Swift tools. From this directory:

```sh
swift test
bash run.sh --context 2048 --output 128 --repeat 2
bash run.sh --context 4096 --output 128 --repeat 2
bash run.sh --context 2048 --cancel-after-tokens 8
bash run.sh --context 2048 --prompt-file prompts/fictional-facts.txt
```

The convenience script verifies the saved runtime archive hash, builds locally and launches the executable. The extracted framework is a trusted local build input: the script is not a production installer and does not defend against subsequent local edits. Runtime `verifyModel` checks the full model size/SHA-256 before native parsing. No model URL is accepted by the executable. `--gpu-layers 99` requests full Metal offload; `0` is a CPU comparison. Native diagnostics disclose the actual backend behavior.

Stdout is JSON; native logs and visible streaming text go to stderr. To retain local results, create `results/` and redirect stdout to a new file. Outputs may contain the prompt's content, so use only fictional prompts here. Do not feed private chats or Knowledge Base content into a benchmark by convenience.

## What is tested

- Exact native tokenization of the **complete rendered prompt**, including system/user markers and generation prefix, and hash of token IDs. No word-count proxy or silent input truncation.
- A deliberately narrow no-tools, single-system/single-user Qwen3 template. Native `chatml` output must equal the pinned expected framing, then the publisher's hard non-thinking prefix is appended. This is not a general Jinja implementation or a multi-turn production template. [Publisher template](https://huggingface.co/Qwen/Qwen3-0.6B/blob/main/tokenizer_config.json).
- Fixed sampling seed 42 with temperature 0.7/top-p 0.8/top-k 20; 2K/4K configured context and at most 512 output tokens. The complete prompt plus output reservation must fit before allocation/generation. Native allocated context is checked again.
- Cumulative Unicode-valid snapshots, explicit terminal outcome, fresh context for each repeat and no cross-run chat state. Repeats reuse loaded weights, not KV state. Model-load timing excludes initial file hashing; first-token timing includes context allocation and prefill, not weight load.
- SIGINT cancellation checks between 128-token prefill batches and generated tokens. CPU decode also receives the native abort callback. The runtime header says that callback is CPU-only: do **not** claim in-flight Metal cancellation. `--cancel-after-tokens` exercises the deterministic between-token path only, not worst-case in-flight interruption. Its observation metric ends before deferred native resource cleanup; it is not a resource-release acknowledgement latency.
- Sampled process physical footprint, process-lifetime peak RSS, thermal state, first-token and total latency. Sampled footprint may miss transient peaks; process-lifetime RSS includes previous runs and model verification. These metrics are not an iOS memory admission policy.

Tests without model loading cover template framing, control-marker/oversize rejection, bounded options and missing-artifact rejection. Real generation smoke tests do not establish answer quality, grounded verification reliability, safe minimum RAM, or phone compatibility.

## Physical-device next step

A separate [iOS harness](ios/README.md) reuses the `EvaluationRuntime` library product. It was subsequently signed using command-line-only overrides, installed with explicit permission, and ran all seven fixed fictional probes on iPhone 15 Pro Max/iOS 27.0. See [phone results](PHONE-RESULTS-2026-10-06.md). It adds off-main work, atomic Stop/background/memory-warning cancellation, pinned local-file import and report export. Do not modify shipping Runner signing. These smoke results are not lifecycle, memory-safety or quality qualification.

On the owner's iPhone 15 Pro Max/A17 Pro, record cold/warm load, complete prompt token parity, 2K/4K context, actual Metal behavior, memory under concurrent retrieval/OCR, first-token latency, throughput, sustained thermals and battery effects. Implement native app-background cancellation and test acknowledgement latency while prefill/decode are in flight. Measure available-process-memory and memory-warning handling with an iOS-specific harness, not Mac RSS guesses. Confirm all assets are local and inference works with networking disabled.

Only after this qualification should an app-native adapter, verified-download lifecycle, explicit General-mode model selection and capability-specific catalogue entry be considered. Knowledge Base mode requires independent held-out grounding/verifier evaluation of this exact artifact and template.

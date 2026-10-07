# Isolated local vision feasibility

Not app integration, not an iPhone qualification, and no personal inputs.

## Status

- Existing llama.cpp b11429 XCFramework reused read-only from `../local_generation/artifacts/build-apple/llama.xcframework`.
- `abi_probe.cpp` compiled/linked and ran on arm64 Mac. Default multimodal parameters/chunks work; model-load, image, tokenizer and chunk-evaluation symbols resolve.
- `nm` also found multimodal symbols in the iOS arm64 slice. No iOS harness build/run performed here.
- `main.mm` compiled and ran three isolated probes on the Apple M2 Mac. Exact weight sizes/hashes passed. **Feasibility passed; the missing-information quality probe failed with an invented salary.** See [measured results](RESULTS-2026-10-06.md).
- Additional approved pair was 545,590,272 bytes. No new runtime was fetched. After preserving the [shared comparison baseline](../model_comparison/BASELINE-2026-10-06.md), both Mac weight files were removed at the user's request to reclaim storage. Reports, manifests and the shared runtime remain; the fetch command below is necessary before another model run.

See [research and exact artifact metadata](../../docs/evaluation/local-image-understanding-2026-10-06.md). The phone is now confirmed iOS 27.0 (24A437), but installed SDK 26.5 cannot build Apple's new native image prompting interface. No SDK upgrade is authorized.

## Harness design

`build.sh` builds an arm64 Mac executable against the existing dynamic framework, without package fetching. `main.mm` verifies pinned size/SHA-256 before native model parsing, decodes a local image with ImageIO (orientation transform, sRGB, white alpha composite, 1024-pixel longest-edge cap), invokes `libmtmd` and runs a single greedy image-question turn. Context is bounded to 2048 with 128 output tokens reserved; over-budget inputs fail rather than truncate.

The prompt implements the exact single-user, image-then-text subset of the publisher's template at `a7da5b986cb59b408707209984f360a5f4ad7e47`. This is not a general multimodal chat implementation. Model-native preprocessing comes from the projector/runtime; parity and visual correctness must be tested. No network is used by the evaluation executable.

Reproduce after ensuring sufficient free disk; the fetch script retrieves only the already-approved pinned pair and small license/card files, verifies size/hash, and never runs inference:

```sh
bash experiments/local_vision/fetch-approved-model.sh
bash experiments/local_vision/build.sh
experiments/local_vision/.build/abi-probe
experiments/local_vision/.build/local-vision-eval \
  experiments/local_vision/artifacts/SmolVLM-500M-Instruct-Q8_0.gguf \
  experiments/local_vision/artifacts/mmproj-SmolVLM-500M-Instruct-Q8_0.gguf \
  test/fixtures/fictional_document_photo.png \
  'What text is visible in this image?' \
  experiments/local_vision/results/document.json
```

`artifacts/`, `.build/`, and `results/` are ignored. Retain exact artifact/runtime metadata and a concise reviewed results report outside those directories. Do not interpret caption-grounded text verification as pixel-level verification. Follow the research note's physical-device and provenance gates before proposing production changes.

Generation is greedy, single-turn, Metal-offloaded; no sampling sweep or tokenizer/preprocessor parity study was performed. `SIGINT`/`SIGTERM` are checked during hashing and text generation and passed to decoder abort handling, but cancellation during vision encoding, iOS suspension and model residency are **not qualified**. The CLI is an evaluation tool, not a production module.
## Liquid comparison update

The approved Liquid Q8 pair has completed the isolated Mac development screen. See [exact results and limitations](LIQUID-RESULTS-2026-10-06.md). Fetch with `bash experiments/local_vision/fetch-liquid-approved.sh`, build with the existing `build.sh`, and run `bash experiments/local_vision/run-liquid-development.sh` only while no other native evaluator is running. Each future run receives a unique result directory and a 120-second per-case timeout; failures are retained. The existing Smol profile is unchanged; its obsolete downloaded weights were removed centrally by root after reports were preserved. No phone or shipping integration is included.

Storage cleanup is complete for Liquid too: its model and projector were removed after evaluation. Re-fetching the pinned pair is required before another vision run; metadata, results and the shared runtime are preserved.

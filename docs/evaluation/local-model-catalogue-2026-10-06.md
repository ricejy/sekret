# Downloadable local model catalogue — 2026-10-06

Research and proposed production scope, followed by separately authorized isolated Mac and physical-iPhone smoke evaluations. The pinned weights/runtime were downloaded and verified under `experiments/local_generation`; no shipping-app native dependency, supported-device qualification, or production networking was added. This is not a release approval or an architecture decision. See the [harness](../../experiments/local_generation/README.md), [Mac results](../../experiments/local_generation/RESULTS-2026-10-06.md), and [iPhone results](../../experiments/local_generation/PHONE-RESULTS-2026-10-06.md). The phone completed all seven fixed probes but showed instruction-following limitations; the model is not approved for the reviewed catalogue.

## Recommendation

### User-confirmed catalogue presentation

The eventual Models destination must be a **selectable list**, with **Apple Intelligence first**, followed by reviewed downloadable local models only. Each model should expose approximately three user-facing comparison metrics. The current proposed labels are **answer quality**, **speed**, and **memory use**; this trio is a recommendation, not a claim that measurements exist or a final user-approved scoring system. Show download size separately so users can distinguish storage from working memory. Mark unmeasured metrics explicitly, identify the test device/configuration for measured speed/memory, and never promote a candidate to reviewed based on the Mac smoke alone. Answer quality needs a documented, model-specific evaluation rather than an invented score. The interim Apple-readiness screen does not yet fulfill selectable local inference.

Show **capability badges separately from the three metrics**: text/image input support and independently approved General/Knowledge Base modes. The user also requires ordinary photo/screenshot understanding, not merely OCR. Selecting the current text-only Qwen candidate must never imply that it can interpret an image; OCR-readable text is not a vision capability. An image-capable runtime/model needs separate acceptance and must not inherit Knowledge Base approval from text generation.

Start with a small **curated catalogue of exact artifacts**, not arbitrary Hugging Face repositories. Evaluate one runtime and one model in General mode before exposing a Download or Use action. Prefer a native **llama.cpp + GGUF** experiment, retaining Apple Foundation Models as an explicitly selected option. A Models destination beside Chat is a reasonable eventual product surface; an unimplemented download button or a compatibility badge inferred from parameter count would be misleading.

Runtime model downloads conflict with [ADR 0001](../adr/0001-keep-v2-entirely-local.md). They require an explicit, narrow exception: user-initiated artifact retrieval only, with no private chat, Knowledge Base, prompt, embedding, or device telemetry sent. The download host still sees ordinary request metadata such as IP address and artifact choice. No hosted inference, accounts, cloud fallback, or automatic model updates are implied.

## Native runtime options

| Option | Primary-source evidence | Recommendation |
| --- | --- | --- |
| llama.cpp | Maintainers provide an iOS-capable XCFramework and describe Apple Silicon/Metal support. [XCFramework instructions](https://github.com/ggml-org/llama.cpp/blob/master/docs/xcframework.md), [runtime repository](https://github.com/ggml-org/llama.cpp). | First experiment: a pinned native binary/source revision and GGUF artifact, wrapped by a Swift adapter. Documentation proves an integration route, not performance or safety on Sekret's target devices. |
| MLX Swift LM | Maintainers provide reusable language-model libraries; official examples run on iOS/macOS and demonstrate model/tokenizer retrieval. The reusable libraries moved out of the examples repository. [Libraries](https://github.com/ml-explore/mlx-swift-lm), [examples](https://github.com/ml-explore/mlx-swift-examples). | Viable Apple-focused alternative if device measurements favor it. Do not integrate both runtimes in the first increment. MLX artifacts and GGUF are not interchangeable. |

Flutter supports Swift communication through platform channels. Sekret already uses MethodChannel/EventChannel for its Apple adapter, so a native adapter follows an established seam without requiring a third-party Flutter LLM plugin. Run native inference off the UI thread and preserve cancellation acknowledgements. [Flutter platform-channel documentation](https://docs.flutter.dev/platform-integration/platform-channels).

## Bounded candidate set

| Candidate | Publisher facts | Proposed role |
| --- | --- | --- |
| Qwen3-0.6B | Publisher describes a 0.6B model, a 32,768-token model context, and an explicit non-thinking chat-template switch. [Model card](https://huggingface.co/Qwen/Qwen3-0.6B). | First feasibility candidate, with thinking disabled through the template implementation rather than a soft user prompt. Start with a smaller app context; advertised context is not an iPhone RAM budget. |
| Qwen3-0.6B-Q8_0.gguf | Official Qwen GGUF repository labels the artifact Apache-2.0 and lists this single GGUF as approximately 639 MB. [Publisher files](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/tree/main). | Prefer the publisher artifact for the first test. Do not invent an official Q4 download: none was listed in this inspection. Obtain exact bytes and hash before making a manifest. |
| SmolLM2-360M-Instruct | Publisher labels it Apache-2.0 and predominantly English; it documents factual/reasoning limitations. [Model card](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct). | Lower-capacity comparison, not an assumed useful or safe assistant. Select and audit a compatible quantization separately. |
| SmolLM2-1.7B-Instruct | Publisher labels this larger English model Apache-2.0. [Model card](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct). | Quality-versus-memory comparison only after the first candidate fits. Not a promised supported device tier. |

License metadata is a shortlist filter, not a redistribution audit. Retain and review the pinned weights, tokenizer, runtime and derivative artifact license/notice files. Model parameter labels may be rounded and must never substitute for exact artifact size or measured peak memory.

## Catalogue and installation policy

The following are engineering recommendations, not existing capabilities:

- Ship reviewed catalogue metadata with the app initially. Each entry identifies publisher/repository, immutable commit, exact filenames, exact byte lengths, SHA-256 hashes, format/quantization, license notices, tokenizer/chat-template identity, runtime version, supported modes, and approved device/context profiles. Hugging Face supports revision-specific retrieval; use immutable commits rather than `main`. [Hub download documentation](https://huggingface.co/docs/huggingface_hub/guides/download).
- Keep the network-capable downloader separate from inference. Permit only catalogue artifacts over HTTPS with bounded, reviewed redirect destinations; Hub downloads can involve CDN hosts. No arbitrary URLs, repository code, pickle loading, scripts, or `trust_remote_code`.
- Require an explicit download action, displayed size and network disclosure. Bound bytes while streaming, not only from Content-Length. Download to an app-owned staging location, verify all sizes and hashes, then publish atomically. Hash verification proves identity against the trusted catalogue, not model quality.
- Serialize installation or reserve staging quota centrally. Account for existing model, partial download, replacement, any copy/decompression overhead, and free-space reserve. Do not fetch an entire repository containing duplicate formats. Incomplete/unverified artifacts never become selectable.
- Persist resumable installation state, but resume only the same pinned artifact with validated range/validator behavior. On integrity mismatch, discard that exact staged artifact and report failure. Protect model files appropriately and exclude re-downloadable weights from backup; keep private chats separate.
- Offer Remove and explicit model selection. Never delete loaded weights during generation, silently change a selected model, or silently fall back to Apple. Retained turns preserve artifact/runtime provenance even after weights are removed.

## Device/resource admission

Use two different decisions: **can install** (supported format/runtime, validated manifest, enough staging disk) and **can run now** (approved device profile, enough process memory, acceptable thermal state, no competing generation). Unknown or unmeasured profiles should not be called compatible.

Apple exposes process-available-memory and important-usage disk-capacity interfaces; these are appropriate native inputs, not fixed RAM-by-phone-name guesses. [Process memory](https://developer.apple.com/documentation/os/os_proc_available_memory), [disk capacity](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumeavailablecapacityforimportantusage). An increased-memory entitlement is not a universal allocation guarantee; Apple specifically directs developers to check available process memory. [Entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit).

Proposed admission profiles must include weights, runtime buffers, KV cache at the selected context, app baseline, concurrent OCR/retrieval, and safety headroom. Recheck immediately before load/generation and react to native memory warnings and thermal pressure. A byte-length check does not prevent memory termination. Show installed disk size separately from measured/estimated working memory; label estimates honestly.

For an initial experiment, try a 2,048/4,096-token app context and 512-token answer cap, then measure. These are experiment settings, not proven safe limits. Count the exact final template, instructions, history, evidence, generation prefix, special tokens and output reservation using the selected runtime/tokenizer. Never mix Apple token counts with an open model's context. Verification calls require their own budgets.

## Existing Sekret integration constraints

Inspection of `lib/core/chat/chat_engine.dart`, `lib/core/platform/llm_backend.dart`, `lib/core/platform/token_counter.dart`, and `lib/core/platform/apple_foundation_models.dart` found:

- General generation, grounded generation/verification, and context probing already have interfaces. The active ChatEngine stores its model snapshot, backend and probe immutably. An idle-only selection must replace these together; swapping only the generator corrupts token accounting and provenance.
- Generation streams contain cumulative snapshots, not token deltas. A native adapter must translate appropriately and honor Stop/backgrounding. Existing turns must keep their original model identity.
- Knowledge Base mode performs a second fresh verification call and withholds drafts until accepted. Tiny-model general chat quality does not establish verifier reliability. Do not enable Knowledge Base mode for a newly downloaded model merely because it can produce text.
- Preserve application-owned citations, insufficient-evidence behavior, immutable selected-source scope, and fail-closed verification. Evaluate the exact quantization and prompt/template configuration on the existing grounding corpus plus fresh held-out cases before approving this mode.
- Availability/failure messaging currently includes Apple-specific cases. An open-model adapter needs accurate not-installed, incompatible, resource-constrained and load-failure states; it must not tell users to enable Apple Intelligence for an unrelated model.

## Staged acceptance

1. Decide the download-only network exception and minimum supported device/OS scope. Freeze the first model/runtime artifact and licensing review.
2. Build an isolated native harness using fictional prompts. Measure exact-token parity, cold/warm load, first-token latency, tokens/second, maximum working memory, energy/thermals, cancellation and suspend/resume on physical devices. Simulator/Mac success is not iPhone evidence.
3. Implement the catalogue/install module with tests for unknown profiles, insufficient disk, interrupted downloads, dishonest length, hash mismatch, crash-before-publish, concurrent requests, deletion while active and offline startup. Add a Models screen only when its states reflect implemented capabilities.
4. Integrate explicit General-mode selection, atomic backend/probe/provenance change and truthful compatibility labels. Verify offline inference and network isolation with device evidence.
5. Treat Knowledge Base support as separate model-specific acceptance, including false approvals, false rejections, malformed verifier output, adversarial source instructions and context overflow. Keep unsupported modes disabled, not silently rerouted.

## Next implementable native qualification task

Follow-up status: the isolated Swift package and separate iOS app described below now exist, and the approved phone smoke has completed. This section preserves the qualification plan; the remaining gate is broader quality/resource/lifecycle acceptance, not initial compilation or the first successful phone generation.

Prepare a separate `experiments/local_generation/` Swift package and minimal iOS harness, without changing Runner, its signing, or its network behavior. Keep its first executable offline: it accepts a local GGUF path and fixed fictional prompts; development-time retrieval is a separate explicit operation. A Mac build can establish bridge compilation, model parsing, exact template/token accounting, deterministic fixture output capture, cancellation and artifact-identity recording. It cannot establish phone fit.

The runtime dependency is llama.cpp, whose repository carries an MIT license. [Runtime license](https://github.com/ggml-org/llama.cpp/blob/master/LICENSE). Subsequent approved evaluation selected nightly b11429, source commit `d81235049384534c167caea52b85a694f6103d14`: archive size **61,992,495 bytes**, SHA-256 `e26a6a0a813f5760fe45834ce239d5b525e4e2442d4fd017221d9f0438383174`, both verified after retrieval; unpacked size approximately **209 MiB**. [Pinned release metadata](https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/b11429). Shipped iOS device-slice cost remains unmeasured. The old b5046 value in the XCFramework documentation is an example, not the selected runtime.

The approved weight dependency is publisher Q8_0 at revision `23749fefcc72300e3a2ad315e1317431b06b590a`, **639,446,688 bytes**, SHA-256 `9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031`; size and digest matched after retrieval. [Publisher metadata](https://huggingface.co/api/models/Qwen/Qwen3-0.6B-GGUF?blobs=true). Only the specific GGUF and license were retrieved, not the full repository. Working disk also needs runtime unpacking/build products and staging. These local artifacts are gitignored; the [artifact manifest](../../experiments/local_generation/artifacts.json) records exact download URLs and metadata sources.

For physical qualification, use a separately signed harness on the owner's iPhone 15 Pro Max/A17 Pro (the existing evaluation notes' target), with explicit device access and development-signing configuration for that harness. Start with 2K context/512 output, then test 4K, cold/warm repeated runs, long input, Stop, background interruption, low available memory and concurrent retrieval. Record OS/runtime/artifact identity and local metrics. Additional supported devices each need their own profile; this phone alone cannot justify a broad minimum device claim.

Only after those results should the real application slice add the verified-download lifecycle, native inference adapter, and atomic General-mode selection. A Models screen with honest availability is groundwork, not completion of downloadable local inference. No production compatibility threshold or device tier can be justified from the sources alone. Exact artifacts are now pinned for the Mac experiment, but physical-device qualification, app-native integration, production download behavior and the ADR network exception remain outstanding.

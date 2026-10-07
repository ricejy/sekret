# Local image understanding — 2026-10-06

Research and isolated feasibility work only; production behavior is unchanged. The subsequently approved 545,590,272-byte model pair was downloaded, hash-verified and tested on Mac; see the follow-up below. Target is the owner's iPhone 15 Pro Max/A17 Pro, confirmed by the coordinating agent as **iOS 27.0 (24A437)**. Installed Xcode 26.6 still reports iPhoneOS SDK 26.5, without the new Attachment interface. The device OS gate is met; a compatible toolchain and on-device model eligibility/integration remain unverified.

## Recommendation

The initial current-toolchain candidate was **SmolVLM-500M-Instruct Q8_0 plus its matching Q8_0 image projector**, tested separately using llama.cpp's multimodal module. Mac feasibility now passes, but the model invented a salary absent from a fictional notice despite an explicit missing-information instruction. **Do not promote this setup into trusted Knowledge Base grounding.** [Measured results](../../experiments/local_vision/RESULTS-2026-10-06.md).

The owner's phone already meets the iOS 27 version gate. With separately approved compatible Xcode/toolchain access, evaluate Apple's **on-device** Foundation Models image interface as an alternative that could avoid app-managed vision weights. Do not use Private Cloud Compute as a fallback. The current installed SDK and production adapter do not expose/use that new interface. No Xcode upgrade is approved. These are alternative evaluation tracks, not a proposal to ship two new runtimes simultaneously.

## Observed diagnosis: import succeeds, ordinary-image capability is missing

The coordinating agent performed a controlled simulator comparison through the same paperclip → Photos interaction:

- Stock flower photograph `IMG0111.heic` was saved, then became Failed with `Not enough readable text was recognized. Check image quality and retry.`
- Repository fixture `test/fixtures/fictional_document_photo.png`, added to simulator Photos and selected through the same interaction, reached Indexed in chat.

This demonstrates working photo selection/import and document OCR on that simulator; it does **not** establish physical-device model performance. The photo branch calls OCR, takes recognized text, and rejects short recognition before producing searchable passages. A flower without readable text cannot enter this text-evidence pipeline merely because its pixels were imported. See [knowledge processing](../../lib/core/knowledge/knowledge_base.dart) and [Vision OCR adapter](../../lib/core/platform/apple_vision_ocr.dart). The chat's generic Failed chip does not currently explain this capability distinction.

## What the existing models can actually receive

**Current Sekret Apple adapter:** its native generation interface accepts a `String` prompt and passes it to `LanguageModelSession`; it supplies neither pixels nor an image encoder. The installed iOS 26.5 FoundationModels Swift interface has no `Attachment` declaration. See [native adapter](../../ios/Runner/AppleFoundationModelsPlugin.swift). This is a statement about the inspected code/toolchain, not all future Apple models.

**Newer Apple interface:** Apple's live guide demonstrates combining image inputs with text in an on-device session, using `Attachment`, including image orientation handling. Its official symbol metadata marks `Attachment` as introduced in **iOS 27.0**. The guide separately suggests Private Cloud Compute for more demanding work; that suggestion conflicts with Sekret's entirely-local ADR and must not be followed. The newer interface merits an OS-gated evaluation only after toolchain/device eligibility is confirmed; documentation alone does not prove quality or memory fit on the owner's phone. [Image prompting guide](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting), [Attachment](https://developer.apple.com/documentation/foundationmodels/attachment), [official availability metadata](https://developer.apple.com/tutorials/data/documentation/foundationmodels/attachment.json).

**Qwen3-0.6B:** the publisher config is `Qwen3ForCausalLM` / `qwen3`, with no vision encoder configuration; it is a text-generation model. Adding an arbitrary projector or passing a filename/base64 string does not give this model vision. A trained, compatible multimodal model is required. [Publisher configuration](https://huggingface.co/Qwen/Qwen3-0.6B/blob/main/config.json).

The existing [local generation experiment](../../experiments/local_generation/) uses Qwen3-0.6B Q8_0 and llama.cpp b11429, as recorded in the [model catalogue research](local-model-catalogue-2026-10-06.md). Its maintainer confirmed the archive includes multimodal headers, but the harness uses the text interface only. Packaging is not a completed image adapter or model-compatibility test.

## Candidates and native routes

| Route | Evidence and constraints | Decision |
| --- | --- | --- |
| SmolVLM-500M + llama.cpp | Publisher model supports interleaved image/text input and text output, including descriptions and visual questions. English; model card declares Apache-2.0. Publisher reports 1.23 GB GPU RAM for a one-image inference configuration, not an iPhone measurement. [Model card](https://huggingface.co/HuggingFaceTB/SmolVLM-500M-Instruct). | First independent iOS 26 feasibility candidate. Small does not guarantee accurate scene interpretation. |
| llama.cpp multimodal module | Maintainers describe a language GGUF plus matching `mmproj` image encoder/projector and separate `libmtmd`; SmolVLM is supported. Multimodal integration is under active development. iOS XCFramework instructions establish a packaging route, not performance or correctness of the pinned build. [Multimodal implementation](https://github.com/ggml-org/llama.cpp/blob/master/tools/mtmd/README.md), [supported models](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md), [XCFramework](https://github.com/ggml-org/llama.cpp/blob/master/docs/xcframework.md). | Verify the existing pinned runtime contains usable symbols and exact model support before introducing another version. |
| MLX Swift LM / MLXVLM | Maintainers provide Swift VLM libraries; registry includes Idefics3/SmolVLM processors and a SmolVLM2-500M model entry. The examples include iOS applications. Current main has breaking changes; the optional FoundationModels bridge requires a 27 SDK, distinct from directly using MLXVLM. [Library](https://github.com/ml-explore/mlx-swift-lm), [registry](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXVLM/VLMModelFactory.swift), [examples](https://github.com/ml-explore/mlx-swift-examples). | Credible Apple-native alternative if llama.cpp qualification fails. Pin compatible versions; MLX weights are not GGUF. Avoid adding both for the first experiment. |
| Apple FastVLM-0.5B research model | Apple provides an iOS demonstration and Apple-Silicon export path. However the inspected model license limits use to research and expressly excludes product development/commercial products. Code and model licenses are separate. [Repository](https://github.com/apple-aiml-research/ml-fastvlm), [model license](https://github.com/apple-aiml-research/ml-fastvlm/blob/main/LICENSE_MODEL). | Do not select these weights for a Sekret product implementation under the inspected terms. Native demonstration alone is not permission to ship. |

License declarations above are screening evidence, not a completed redistribution review. Before any approved download/bundling, review the pinned weights, base model, tokenizer, runtime and notices together.

### Exact artifact pair — subsequently downloaded and verified

Runtime maintainers' repository `ggml-org/SmolVLM-500M-Instruct-GGUF`, revision `72e986006ef53e37cdd3f6d4241c90b0f01df376`, lists:

| Artifact | Bytes | Published SHA-256 |
| --- | ---: | --- |
| `SmolVLM-500M-Instruct-Q8_0.gguf` | 436,806,912 | `9d4612de6a42214499e301494a3ecc2be0abdd9de44e663bda63f1152fad1bf4` |
| `mmproj-SmolVLM-500M-Instruct-Q8_0.gguf` | 108,783,360 | `d1eb8b6b23979205fdf63703ed10f788131a3f812c7b1f72e0119d5d81295150` |

Total **545,590,272 bytes**, approximately **520.3 MiB**, excluding runtime, licenses, staging and build products. These publisher hashes and byte counts were **subsequently verified locally** following explicit user approval. Only this pair was retrieved, not f16 alternatives or the whole repository. [File listing](https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/tree/72e986006ef53e37cdd3f6d4241c90b0f01df376), [metadata endpoint](https://huggingface.co/api/models/ggml-org/SmolVLM-500M-Instruct-GGUF?blobs=true).

Disk size is not peak working memory. Evaluation must include decoded image buffers, vision activations, visual-token context, decoder KV cache, Metal allocations and co-resident OCR/retrieval/Apple models. Neither a 500M label nor a desktop RAM claim establishes iPhone fit.

The follow-up Mac harness now covers the initial runtime hurdles: linked `mtmd` symbols, loading both exact artifacts, orientation-aware pixel admission, a fixed multimodal template, token budgeting and image embedding evaluation before text decoding. b11429 worked without an additional runtime download. Device execution, reference preprocessing parity, full chat/template behavior, cancellation during vision encoding and lifecycle/privacy remain unqualified; the text-only harness does not establish these.

## Direct image chat is not the same as a searchable image caption

These are proposed product semantics, not implemented behavior:

1. **Direct image chat:** answer a question using selected original pixels plus text. It can inspect details omitted by an earlier caption. Freeze source identity/content hash, model/projector revisions, preprocessing/orientation/crops and generation configuration in turn provenance; regeneration must use the original source scope, not whichever image is currently selected. Decide how this mode is distinguished from General answers and existing text-grounded answers before shipping.
2. **Knowledge Base image indexing:** generate a local description/tags, then embed that derived text to find images later. This gives searchable descriptions, but a caption is an imperfect model interpretation, not an OCR transcription or user-authored fact. Store provenance and distinguish caption-derived evidence visibly. Keep original images locally previewable under the existing deletion policy.
3. **Grounding limitation:** a text verifier can determine whether an answer follows a generated caption; it cannot establish that the caption accurately describes the pixels. Sending caption text through today's grounded pipeline could make invented visual facts appear to be verified evidence. Do not simply relabel generated descriptions as normal evidence passages. Original-image verification, uncertainty handling and a visual acceptance benchmark are separate work.

These distinctions follow from the current [domain definitions](../../CONTEXT.md) and [immutable provenance ADR](../adr/0002-capture-immutable-turn-provenance.md). A VLM must not silently turn failed OCR into a General answer, weaken insufficient-evidence abstention, or introduce cloud inference. The current photograph failure should remain explicit until a supported visual path exists.

## Bounded next evaluation and choices

The relevant choice is **current-toolchain downloadable vision** versus **iOS 27 native vision requiring a compatible SDK**, not an OS upgrade for this phone. The former experiment can reuse the existing runtime if disk permits; the latter needs toolchain authorization and availability checks. Separately choose whether the first user-visible capability is direct image questions (recommended) or only searchable descriptions; the user's ordinary-image request is not satisfied by OCR alone.

With explicit authorization for artifacts/dependencies, build an isolated harness: local image path, fixed prompt, pinned runtime/model/projector, no network during inference. Test the flower plus fictional/consented images covering objects, colors, counts, spatial relations, document text, screenshots, rotations, blur and deliberately unanswerable details. Preserve HEIC orientation/color handling; measure preprocessing parity and bound image size/visual tokens. Grade fabricated details and abstention separately from descriptive fluency.

On the physical target, measure cold/warm load and first-token latency, peak memory, repeated-run thermals, interruption/cancellation, background privacy and return-to-app behavior, with realistic retrieval/model residency. Simulator or Mac output is not phone qualification. Only after quality and device gates pass should source/provenance schemas, capability badges, processing-state explanations and a narrowly scoped production adapter be designed. No artifact retrieval, production integration or OS upgrade is authorized by this research note.

## Follow-up feasibility status

The user subsequently authorized the additional model pair **only if needed**. In `experiments/local_vision`, a small arm64 Mac ABI probe compiled, linked and ran successfully against existing b11429 before retrieval. Read-only inspection also found multimodal symbols in the iOS arm64 slice; this is not device execution. After separately approved disk cleanup by the coordinating agent, the pair was fetched and size/hash verified, and the separate image CLI compiled and ran three non-personal probes.

On Apple M2/macOS 26.6.1: turtle art elicited the weak but class-correct `Turtles.`; the fictional notice's seven-day deadline was answered correctly; an absent salary elicited the fabricated `$100,000`. Total first-run work was 30.56 seconds including backend/shader startup; later separate processes took 1.23–1.40 seconds with warmed caches. Peak RSS was 777–790 MB versus sampled physical footprint 308–317 MB; these are different memory measures and neither establishes iPhone RAM needs. Final disk: 5.9 GiB free. No extra runtime, app integration or vision phone run. See [settings, exact outputs and measurement caveats](../../experiments/local_vision/RESULTS-2026-10-06.md) and the [isolated harness](../../experiments/local_vision/README.md).

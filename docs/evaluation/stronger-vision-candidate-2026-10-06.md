# Stronger vision comparison candidate — 2026-10-06

Primary-source screening following the [SmolVLM missing-fact failure](../../experiments/local_vision/RESULTS-2026-10-06.md). Initial proposal below is retained as decision history. Subsequently the user approved the exact Liquid Q8 pair; both artifacts were downloaded and hash/size verified, and three Mac cases completed on the existing runtime. See [measured results](../../experiments/local_vision/LIQUID-RESULTS-2026-10-06.md). No new runtime or Gemma weights were downloaded. The user's ai-cooker wiki supplied discovery leads, not qualification evidence.

## Proposal: Liquid LFM2.5-VL-1.6B Q8_0 first

Request approval for **one official Liquid pair totaling 1,829,364,768 bytes (1.704 GiB)**: Q8_0 language weights plus its Q8_0 projector. It offers a larger 1.2B language backbone and 400M vision encoder, documented visual/document tasks, an official GGUF route and matching support in our pinned runtime. These facts justify a comparison, **not a claim of less hallucination**. Publisher benchmark results do not establish accuracy on Sekret's images. [Publisher model card](https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B).

Choosing Q8 for this first quality comparison avoids simultaneously lowering precision relative to the SmolVLM Q8 baseline. This is an experimental tradeoff, not proof that Q8 is required. The smaller official Q4_K_M decoder plus the same Q8 projector is 1,314,006,144 bytes; reserve that as a separately approved memory/quantization comparison if needed, rather than downloading both now.

Gemma 4 E2B remains useful, but Google's exact official QAT Q4 pair totals **4,336,349,920 bytes (4.039 GiB)**. It is more than twice the Liquid Q8 pair. Its cleaner Apache-2.0 licensing is an advantage; its larger artifact/residency budget and different template make it a larger first experiment. The E2B name means effective parameters, not a two-billion-weight footprint: Google's card lists 2.3B effective / 5.1B including embeddings. This is not evidence Liquid is more accurate than Gemma. [Official Gemma artifact](https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf), [Gemma 4 model card](https://ai.google.dev/gemma/docs/core/model_card_4).

## Exact artifacts — metadata, not downloaded/verified bytes

Liquid repository `LiquidAI/LFM2.5-VL-1.6B-GGUF`, revision **`36fc16bc95133424921bcc3da009e83b2f23ffb5`**:

| File | Bytes | Published SHA-256 |
| --- | ---: | --- |
| `LFM2.5-VL-1.6B-Q8_0.gguf` | 1,246,254,880 | `a34bd1506a298d7ff07902e69baeac48c7c20bb85162e61218b743dc10be7c67` |
| `mmproj-LFM2.5-VL-1.6b-Q8_0.gguf` | 583,109,888 | `2ce89e610c56f3198ece2b86cf61743a08b9307279c89125eb2412ebb908689d` |
| Optional alternative, **not proposed for retrieval now**: `LFM2.5-VL-1.6B-Q4_K_M.gguf` | 730,896,256 | `aefc3c97c9eb30d9c0dd6af4c38250f5f5106b57c8cf92de7914c7d0a9c94da2` |

[Pinned Liquid listing](https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/tree/36fc16bc95133424921bcc3da009e83b2f23ffb5), [publisher metadata](https://huggingface.co/api/models/LiquidAI/LFM2.5-VL-1.6B-GGUF?blobs=true).

Google repository `google/gemma-4-E2B-it-qat-q4_0-gguf`, revision **`675cff42a74c774d6cb76f76d8eacb49b48c9b93`**:

| File | Bytes | Published SHA-256 |
| --- | ---: | --- |
| `gemma-4-E2B_q4_0-it.gguf` | 3,349,516,256 | `fa401b55b07ee70a54c6dae3903c783a6e65064312529ea57175cb5f8dec6634` |
| `gemma-4-E2B-it-mmproj.gguf` | 986,833,664 | `021059cce659fe7f9170d5599761d7bbaf644b798dab9503aca30dc43e6beb14` |

[Pinned Google listing](https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf/tree/675cff42a74c774d6cb76f76d8eacb49b48c9b93), [publisher metadata](https://huggingface.co/api/models/google/gemma-4-E2B-it-qat-q4_0-gguf?blobs=true).

Use only revision-pinned `resolve/<revision>/<filename>` URLs after approval; retain cards/licenses and verify size plus digest before native parsing. No repository-wide download, conversion environment, second quantization or new runtime is proposed.

## Actual license differences

**Liquid is not Apache-2.0.** The pinned LICENSE is LFM Open License v1.0. It grants use/modification/distribution subject to conditions, including commercial-use restrictions tied to a threshold defined as annual revenue of US$10 million or more; its legal-entity definition includes controlled/common-control entities. Commercial use includes indirect commercial advantage. Redistribution requires the license, retained notices and modification notices; trademark rights are not granted. Do not assume a personal evaluation automatically clears later company/product distribution or revenue eligibility. Confirm the applicable individual/entity and intended use before acceptance/retrieval; obtain appropriate legal/licensor guidance if unclear. [Full pinned license](https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/blob/36fc16bc95133424921bcc3da009e83b2f23ffb5/LICENSE).

**Google's inspected Gemma 4 artifact links to Apache License 2.0**, not older Gemma custom terms. The linked full license permits use and redistribution subject to notice/license requirements and includes patent and trademark limitations; it has no analogous revenue threshold. Retain the pinned artifact card and applicable notices; this screening is not a complete redistribution audit. [Google's linked full license](https://ai.google.dev/gemma/docs/gemma_4_license).

## Existing b11429 support and harness work

Pinned runtime commit: `d81235049384534c167caea52b85a694f6103d14`. Its source contains `src/models/lfm2.cpp` and `src/models/gemma4.cpp`. More importantly, its multimodal implementation has explicit LFM2 image delimiters, tiled-image layout and `mtmd_image_preprocessor_lfm2`; `clip.cpp` references this exact LFM2.5 model when setting image-token defaults. It also contains Gemma4 vision projector paths and an E2B/E4B causal-attention special case. This is stronger evidence than an unpinned compatibility list, but **neither candidate's exact artifacts have been loaded locally**. The existing successful SmolVLM ABI probe establishes symbols, not these models' correctness. [Pinned multimodal implementation](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/tools/mtmd/mtmd.cpp), [pinned projector implementation](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/tools/mtmd/clip.cpp).

Liquid's original checkpoint revision is `919fde3d022e3f90a4716006f993938ee8c2eb97`. The actual template begins with `<|startoftext|>`, uses lower-case ChatML roles and ends the generation prefix with `<|im_start|>assistant\n`. It is **not** SmolVLM's capitalized `User:`/`Assistant:` template. Implement a separately named exact single-turn subset, verify BOS handling, preserve special-token parsing, and let `mtmd` expand its media marker into Liquid's image tokens. [Pinned template](https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B/blob/919fde3d022e3f90a4716006f993938ee8c2eb97/chat_template.jinja), [tokenizer config](https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B/blob/919fde3d022e3f90a4716006f993938ee8c2eb97/tokenizer_config.json).

Liquid's processor specifies 512-pixel tiles, thumbnails, min/max image-token settings 64/256, and up to ten tiles. **256 is not a promise that an entire tiled image costs only 256 tokens.** Keep the existing orientation-correct 1024-pixel input cap for the first shared comparison, record actual `mtmd` chunks/tokens, and reject when total input plus output reservation exceeds 2048 rather than silently shrinking the source or increasing memory. Freeze the decoding settings before grading; do not tune only the new model on the failed salary case. [Pinned processor configuration](https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B/blob/919fde3d022e3f90a4716006f993938ee8c2eb97/processor_config.json).

If Gemma is chosen later, use its actual versioned template: Gemma 4 employs `<|turn>` and channel/thinking handling, unlike older generic Gemma formatting pages. Its checkpoint processor defaults to 280 soft image tokens; Google's model card documents configurable image budgets. Neither Smol nor Liquid templates can be reused. [Pinned Gemma 4 template](https://huggingface.co/google/gemma-4-E2B-it/blob/3e22461f65e89153144f8adb70e3b8c2cc9845a7/chat_template.jinja), [processor](https://huggingface.co/google/gemma-4-E2B-it/blob/3e22461f65e89153144f8adb70e3b8c2cc9845a7/processor_config.json).

## Disk, phone and decision gates

Latest read-only disk check showed 7.7 GiB free (the task began near 8.2 GiB). Liquid's pair would leave roughly 6 GiB before small build/log overhead, while preserving old model files/results. Keep at least 1.5 GiB free, recheck immediately before retrieval and avoid duplicate staging copies. Gemma's pair alone would consume about 4.04 GiB; artifact size still is not working RAM.

Google's mobile memory column uses **LiteRT-LM**, whereas this experiment uses GGUF/llama.cpp. Do not transplant its approximately 1.1 GB mobile estimate onto the 4.34 GB GGUF pair or the iPhone 15 Pro Max. Measure actual decoder/projector, KV, activations, image buffers and Metal allocations on Mac, then a separately coordinated phone harness. [Google memory/runtime distinctions](https://ai.google.dev/gemma/docs/core).

Next gate: root/user approve the exact Liquid pair and license context; then load-test on the existing runtime, run the frozen shared visual/missing-fact rubric with immutable results, and stop on compatibility or resource failure. Do not automatically fetch a new runtime or alternate weights. Only measured quality improvement plus a physical-device resource/lifecycle pass can justify later integration. Apple's iOS 27 native vision/toolchain comparison remains a separate, unapproved SDK change—not part of this proposal.

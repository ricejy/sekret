# Stronger text candidate: LFM2.5-1.2B-Instruct

Status: approved isolated download and Mac development screen completed, 2026-10-06; **no catalogue approval**. See [measured results](../../experiments/liquid_text/RESULTS-2026-10-06.md): 8/10 required-task completions, with injection and arithmetic failures plus an extra scope inference. Existing Qwen Mac/phone baselines remain unchanged. This research follows the ai-cooker lead back to publisher artifacts and runtime source rather than treating its model list as qualification evidence.

## Recommendation and exact download

Evaluate **LiquidAI LFM2.5-1.2B-Instruct, Q4_K_M** first. It is the non-thinking instruction model, a better initial interactive-chat comparison than the always-reasoning 2.6B variant. Its publisher describes a 1.17B text-only hybrid model, with Korean among its languages and recommends extraction/RAG while warning against knowledge-intensive tasks. These are candidate-selection reasons, not proof of better Sekret answers. Use the shared development rubric before claiming an improvement. [Pinned official model card](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct/blob/0f604ada3f766f9f257460c4c9f0b5d6f69d431b/README.md)

| Field | Pinned value |
| --- | --- |
| Publisher repository | `LiquidAI/LFM2.5-1.2B-Instruct-GGUF` |
| Revision | `8ed288026e23958ad9dfa92d53ed773a8eee7125` |
| File | `LFM2.5-1.2B-Instruct-Q4_K_M.gguf` |
| Bytes | **730,895,168** (730.9 MB; 697.0 MiB) |
| SHA-256 | `b1b3de114215d9507409a662a501a631095a479a419584e8a2ded6304b19b4f5` |
| Source-model revision | `0f604ada3f766f9f257460c4c9f0b5d6f69d431b` |

The publisher API supplies both LFS size and SHA, not merely a filename-derived estimate. [Official metadata](https://huggingface.co/api/models/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/revision/8ed288026e23958ad9dfa92d53ed773a8eee7125?blobs=true) · [Exact immutable download](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/8ed288026e23958ad9dfa92d53ed773a8eee7125/LFM2.5-1.2B-Instruct-Q4_K_M.gguf)

This file is 91,448,480 bytes larger than the existing Qwen Q8 artifact. No new runtime download is proposed. A partial download renamed after hash verification needs roughly one artifact's disk space; a separate staged copy needs two. Keep the existing >1.5 GiB free-disk operational reserve and recheck before downloading/building. File size is **not** working memory: native tensors, hybrid recurrent state, KV state, Metal buffers, contexts, and the host app add costs that must be measured. Do not quote the publisher's other-device memory/speed claims as iPhone measurements.

## License: open weights, not unrestricted open source

The actual artifact license is **LFM Open License v1.0**, not Apache-2.0. Sections 2–5 condition commercial rights on a revenue threshold defined as US$10 million annually; section 5 uses “exceeding” wording. Do not resolve the exact-boundary ambiguity in product copy: obtain commercial/legal clarification if relevant. The legal-entity definition includes controlled/common-control entities. Redistribution requires supplying the license, marking modified files, retaining applicable notices and NOTICE attribution. Section 11 requires cessation/deletion upon noncompliance. Research evaluation does not establish eligibility for later commercial distribution. Catalogue licensing needs a release check and accessible notices; do not label this candidate unrestricted or OSI-approved. [Complete pinned license](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/blob/8ed288026e23958ad9dfa92d53ed773a8eee7125/LICENSE)

## Compatibility with our pinned runtime

Existing llama.cpp **b11429**, commit `d81235049384534c167caea52b85a694f6103d14`, has an LFM2 implementation identifying both 1.2B and 2.6B feed-forward dimensions and building attention plus short-convolution blocks. This is positive source-level evidence for reusing the existing XCFramework, **not** evidence that this exact GGUF loads or runs correctly on our Mac/iPhone. First execution must validate that. [Pinned LFM2 implementation](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/src/models/lfm2.cpp)

The local public header exposes native tokenization and sampling but explicitly says `llama_chat_apply_template` is not a general Jinja parser. Its ChatML formatter supplies role boundaries but no BOS token. The candidate's official template adds BOS and finishes with the assistant header **without a thinking prefix**. Its tokenizer config uses `<|startoftext|>` BOS, `<|im_end|>` EOS and automatic BOS insertion. Never blindly reuse Qwen's appended empty-thinking block. [Native ChatML source](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/src/llama-chat.cpp) · [Candidate template](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct/blob/0f604ada3f766f9f257460c4c9f0b5d6f69d431b/chat_template.jinja) · [Tokenizer configuration](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct/blob/0f604ada3f766f9f257460c4c9f0b5d6f69d431b/tokenizer_config.json)

Bounded implementation plan (the approved Mac single-turn subset is now implemented in `experiments/liquid_text`; physical-device work remains pending):

1. Add a separate pinned evaluation profile without altering Qwen defaults/results. Verify file bytes/SHA before native loading; inspect GGUF architecture, tokenizer and template metadata against the pinned source.
2. Implement the no-tools, single-turn system/user subset, reject control markers, and test exact framing. Explicitly render BOS then tokenize with automatic-special insertion disabled, checking exactly one BOS and correct EOS with the **loaded model vocabulary**. Record exact templated-token counts and token hash; never use character estimates. Full tool/history template support is out of scope.
3. Add a model-specific sampler: publisher guidance is temperature 0.1, top-k 50, repetition penalty 1.05. Specify and export the repetition window, seed, sampling order and all remaining defaults; do not inherit Qwen top-p/temperature silently. [Official decoding guidance](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct/blob/0f604ada3f766f9f257460c4c9f0b5d6f69d431b/README.md)
4. Run identical shared fictional text cases on Qwen and LFM with the frozen comparison configuration: **2048 context and 128 generated-token cap**; reject prompt-plus-reserved-output overflow. A later 4K or larger-output run is separately labelled, not a replacement. Save raw results independently. Separate verification/load, first-token, generation and end-to-end timings, report output length and cold/warm conditions. Check UTF-8, cancellation, malformed/truncated outputs and source-grounding failures, not just successful generation.
5. Only after Mac load/format/quality checks, qualify the separate iPhone app: physical footprint, repeated turns, actual Stop/background handling and memory pressure. Reuse current runtime unless an observed failure justifies a separately pinned upgrade. No shipping Runner/signing/network changes in this stage.

This is text-only. A template containing generic image markers does not confer image capability. General and Knowledge Base approval remain separate, and neither is granted by this note. No answer-quality star, device-wide speed rank, safe memory threshold or production context limit is inferred here.

## Why not 2.6B first?

The official LFM2.5-2.6B model is always-reasoning: its template opens `<think>` and is not equivalent to a non-thinking instruction model. Reasoning consumes the output budget and delays a final answer, so a 512-token bounded chat comparison could truncate before the answer. A later reasoning track needs separate budget accounting, final-answer extraction and UI handling; do not force Qwen's empty-thinking suffix onto it. [Official 2.6B card](https://huggingface.co/LiquidAI/LFM2.5-2.6B/blob/654f9463ce32b05d0429d76fe1f580b27d4c1ac0/README.md) · [Exact reasoning template](https://huggingface.co/LiquidAI/LFM2.5-2.6B/blob/654f9463ce32b05d0429d76fe1f580b27d4c1ac0/chat_template.jinja)

For a later explicit decision, ordinary `LFM2.5-2.6B-Q4_K_M.gguf` is **1,674,455,040 bytes**, SHA-256 `02a8b7e17487d326e46d68ce0ba24211e1b80a14c4cd0597fa73c1cd697f52ed`, GGUF revision `e7caca5d835a3901a8e0d63e94009429bafafdfc`. The separately named QAD-Q4_0 artifact is not this quantization and must not be substituted. Both size and reasoning cost favor the 1.2B-Instruct first experiment; neither establishes an answer-quality winner. [Official 2.6B artifact metadata](https://huggingface.co/api/models/LiquidAI/LFM2.5-2.6B-GGUF/revision/e7caca5d835a3901a8e0d63e94009429bafafdfc?blobs=true)

The production model-download/network exception to ADR0001 remains a separate decision. The user separately approved this isolated candidate download; no phone installation or production catalogue entry is authorized by this note.

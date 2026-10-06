# Next text evaluation candidate: Qwen3-4B-Instruct-2507

Status: research only, 2026-10-06. **No weights downloaded, no measured results, no catalogue approval.** This follows the unsuccessful small-model configurations and the [Liquid diagnostic](../../experiments/liquid_text/DIAGNOSTIC-RESULTS-2026-10-06.md). The next download requires user confirmation.

## Recommendation and exact budget

Evaluate **Qwen3-4B-Instruct-2507, Unsloth's ordinary Q4_K_M conversion**, in the existing isolated Mac harness. This is a real Qwen publisher model, not a guessed model name. It is text-only and explicitly non-thinking. Its 4B instruction checkpoint is a different capacity/post-training candidate from the tested 0.6B configuration; it is **not a different model family**. Selection is based on verified packaging, licence and runtime compatibility, not an assumed answer-quality improvement. [Publisher model card](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/cdbee75f17c01a7cc42f958dc650907174af0554/README.md)

| Field | Pinned value |
| --- | --- |
| Source publisher | `Qwen/Qwen3-4B-Instruct-2507` |
| Source metadata/template revision inspected | `cdbee75f17c01a7cc42f958dc650907174af0554` |
| GGUF converter, **not Qwen** | `unsloth/Qwen3-4B-Instruct-2507-GGUF` |
| GGUF revision | `a06e946bb6b655725eafa393f4a9745d460374c9` |
| Exact file | `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` |
| Download bytes | **2,497,281,120** (2.497 GB; 2.326 GiB) |
| SHA-256 | `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597` |
| Extra runtime/projector downloads proposed | **None** |

The converter's immutable API manifest reports both size and SHA. Its model card identifies the Qwen source model and Apache-2.0 licence, but does **not** identify an exact source-weights commit or a complete reproducible conversion command/calibration manifest. The source revision above is the metadata/template revision inspected now, **not a claim that Unsloth converted that revision**. Pinning bytes ensures artifact identity, not publisher endorsement or derivation attestation. The direct `Qwen/Qwen3-4B-Instruct-2507-GGUF` API request was inaccessible (HTTP 401); that alone does not prove a repository does not exist. Do not label the selected Unsloth artifact official Qwen GGUF. [Converter manifest](https://huggingface.co/api/models/unsloth/Qwen3-4B-Instruct-2507-GGUF/revision/a06e946bb6b655725eafa393f4a9745d460374c9?blobs=true) · [Converter's provenance declaration](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/blob/a06e946bb6b655725eafa393f4a9745d460374c9/README.md) · [Immutable download](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/a06e946bb6b655725eafa393f4a9745d460374c9/Qwen3-4B-Instruct-2507-Q4_K_M.gguf)

With the reported 6.7 GiB free, one partial file renamed after verification leaves approximately 4.37 GiB before small build/log growth. Avoid a second full copy: duplicate staging would consume about 4.65 GiB and leave only about 2.05 GiB. Recheck free space immediately before download/build, retain at least 1.5 GiB plus operational margin, and remove unused weights after the decision while retaining results/checksums. **Disk bytes are not runtime memory.** No iPhone15ProMax safety claim follows from its 8 GB RAM or this weight size; model buffers, KV cache, Metal allocations, OS pressure and the app all count.

## Licence screening

The source repository contains the complete standard **Apache License 2.0**, including redistribution conditions and an Alibaba Cloud copyright notice, not Liquid's commercial-threshold licence. The converter declares the same licence and links to the source licence. For distribution, supply the licence, retain applicable notices and attribution, mark modifications appropriately, and check any NOTICE requirements; trademark rights are not granted. This is a concrete packaging screen, not a full legal or training-data audit. [Pinned complete source licence](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/cdbee75f17c01a7cc42f958dc650907174af0554/LICENSE)

## Runtime and prompt contract

Reuse llama.cpp **b11429**, commit `d81235049384534c167caea52b85a694f6103d14`. Its Qwen3 implementation explicitly identifies the 36-layer/2560-hidden-dimension architecture as 4B and implements the corresponding attention/FFN graph. This is positive source-level compatibility evidence, **not a successful load or correctness result for these exact GGUF bytes**. Validate the GGUF architecture, tensors, metadata and native load before evaluating. No runtime upgrade is justified merely by selecting this model. [Pinned native Qwen3 implementation](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/src/models/qwen3.cpp) · [Publisher architecture](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/cdbee75f17c01a7cc42f958dc650907174af0554/config.json)

The inspected publisher tokenizer has `add_bos_token=false`, `bos_token=null`, EOS `<|im_end|>`, and padding `<|endoftext|>`. For the bounded no-tools, one-system/one-user subset, the exact rendered template is:

```text
<|im_start|>system\n{system}<|im_end|>\n<|im_start|>user\n{user}<|im_end|>\n<|im_start|>assistant\n
```

Here `\n` means a literal newline, not two characters. **No leading BOS and no `<think>`/empty-thinking suffix.** The prior Qwen3-0.6B wrapper's empty-thinking block must not be inherited. Compare the chosen subset and complete native token IDs against the pinned publisher template/tokenizer before grading. If the GGUF embeds a different or older template, record and reconcile it rather than silently assuming either is correct. Reject prompt control-marker injection in the harness. Full tools, history and image support are outside this single-turn evaluation. [Pinned tokenizer and template](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/cdbee75f17c01a7cc42f958dc650907174af0554/tokenizer_config.json)

Publisher decoding guidance is temperature **0.7**, top-p **0.8**, top-k **20**, min-p **0**. Presence penalty is an optional adjustment, not a mandatory nonzero default. Start with an explicit no-penalty profile, fixed seed, documented sampler order and all defaults exported; do not inherit Liquid's 0.1 temperature or 1.05 repetition penalty. The generation config lists EOS IDs 151645 and 151643, while the tokenizer's EOS string is `<|im_end|>`; inspect native end-of-generation handling for both. [Publisher generation configuration](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/cdbee75f17c01a7cc42f958dc650907174af0554/generation_config.json) · [Publisher decoding guidance](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/cdbee75f17c01a7cc42f958dc650907174af0554/README.md)

The publisher recommends a much longer output allowance for broad tasks. Sekret's existing 2K-context/128-generated-token development profile is deliberately resource-bounded and must remain labelled as such. Keep the same frozen prompts and output cap for direct comparisons, report cap-exhausted cases as truncations, and use any separately approved longer-budget diagnostic as a separate configuration. Do not rewrite the arithmetic prompts to improve one candidate's score. A raw total is not enough: report formatting, arithmetic, source-fact reading, unsupported assertions, injection handling and abstention independently.

## Bounded alternatives, not additional downloads

- **Qwen3.5-2B** is real: the Qwen API identifies the post-trained image-text model at revision `15852e8c16360a2fea060d615a32b45270f8a8fc`, declaring Apache-2.0. The pinned native runtime already includes `qwen35.cpp`; it would be incorrect to reject it simply as unsupported by b11429. However its hybrid/multimodal architecture and template are a separate compatibility investigation. No exact GGUF/projector is selected or budgeted here. Prefer the simpler text-only 4B instruction comparison first; this is an engineering-risk choice, not an accuracy ranking. [Publisher metadata](https://huggingface.co/api/models/Qwen/Qwen3.5-2B/revision/15852e8c16360a2fea060d615a32b45270f8a8fc) · [Pinned Qwen3.5 native implementation](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/src/models/qwen35.cpp)
- **Qwen3-1.7B** has an official GGUF repository at revision `90862c4b9d2787eaed51d12237eafdfe7c5f6077`, but it remains the earlier thinking/non-thinking family. No artifact is selected. It offers a smaller fallback if 4B proves impractical, not evidence that it would solve the observed quality gaps. [Publisher GGUF metadata](https://huggingface.co/api/models/Qwen/Qwen3-1.7B-GGUF/revision/90862c4b9d2787eaed51d12237eafdfe7c5f6077?blobs=true)

Run the quality screen on Mac before any physical-device qualification. Phone throughput, sustained memory/thermal behavior, stop/background behavior and UI integration remain unmeasured. General and Knowledge Base approvals are separate; neither is granted here. The production download exception to ADR0001 also remains separate from this isolated evaluation.

# Qwen3.8-27B quantized options

Research only, 2026-10-06. **No model weights downloaded, no benchmark performed, and no catalogue approval.** The user asked to find a quantized version; this is not authorization for a 6–29 GB download. The separately approved compact Qwen3-0.6B evaluation remains independent.

## What exists

**Qwen3.8-27B is the correct, real publisher model name.** Qwen's repository describes a dense, native image/video-capable model, with thinking enabled by default but switchable off. It declares Apache-2.0. This note does not use popularity or publisher benchmark claims as evidence of Sekret performance. Publisher metadata inspected at `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0`. [Publisher model card](https://huggingface.co/Qwen/Qwen3.8-27B/blob/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0/README.md) · [Publisher metadata](https://huggingface.co/api/models/Qwen/Qwen3.8-27B/revision/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0)

The quantizations below are **Unsloth community conversions**, not publisher-produced Qwen GGUFs. The converter identifies `Qwen/Qwen3.8-27B` as its base and declares Apache-2.0, but its card does not pin the source-weights commit or provide a complete reproducible conversion command. The inspected publisher revision must not be represented as an attested conversion source. [Pinned converter card](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/blob/4ca720788d1e01f1bff70c033e0d0028fd02e502/README.md)

## Download sizes, not RAM requirements

All rows come from converter revision **`4ca720788d1e01f1bff70c033e0d0028fd02e502`**. `GB` is decimal; `GiB` is binary. Files are named `Qwen3.8-27B-<variant>.gguf`. The first row is the smallest full model in this inspected repository, not a claim about every conversion on the internet. IQ1/IQ2 and dynamic variants use mixed precision: their names do not mean every parameter occupies exactly one or two bits. Historical repository revisions/search snippets show different file inventories and sizes; use this pinned manifest. [Exact file manifest](https://huggingface.co/api/models/unsloth/Qwen3.8-27B-GGUF/revision/4ca720788d1e01f1bff70c033e0d0028fd02e502?blobs=true)

| Variant | Exact bytes | Download GB | Download GiB |
| --- | ---: | ---: | ---: |
| UD-IQ1_S | 6,192,222,208 | 6.19 | 5.77 |
| UD-IQ1_M | 6,729,166,848 | 6.73 | 6.27 |
| UD-IQ2_XXS | 7,266,070,528 | 7.27 | 6.77 |
| UD-IQ2_S | 8,371,970,048 | 8.37 | 7.80 |
| UD-Q2_K_XL | 9,828,981,664 | 9.83 | 9.15 |
| UD-Q3_K_XL | 13,146,393,504 | 13.15 | 12.24 |
| UD-Q4_K_M | 16,464,440,224 | 16.46 | 15.33 |
| Q8_0 | 29,047,086,048 | 29.05 | 27.05 |

The smallest file's SHA-256 is `3895b6eaa91e705c06ad1938d16c22e86f073c6a67df86260a1da79be3d1f887`. The UD-IQ2_XXS SHA-256 is `e792d8fb3142fe6d9171876d6da0f71f05a71028718debc72dbec93ff645e67d`. These identify artifacts, not measured correctness. [Smallest pinned file](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/blob/4ca720788d1e01f1bff70c033e0d0028fd02e502/Qwen3.8-27B-UD-IQ1_S.gguf) · [Pinned IQ2 file](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/blob/4ca720788d1e01f1bff70c033e0d0028fd02e502/Qwen3.8-27B-UD-IQ2_XXS.gguf)

Visual input additionally needs the matching projector: F16 **927,607,488 bytes**, or BF16 **931,146,432 bytes**, plus its runtime buffers. Thus even smallest model + F16 projector is **7,119,829,696 bytes (7.12 GB)** on disk. Text-only investigation need not download a projector. The 1.37 GB MTP artifact is an optional prediction component, and the 13.6 MB importance matrix is quantization metadata; neither is a standalone model. [Same pinned manifest](https://huggingface.co/api/models/unsloth/Qwen3.8-27B-GGUF/revision/4ca720788d1e01f1bff70c033e0d0028fd02e502?blobs=true)

## Runtime compatibility

The publisher config uses `Qwen3_5ForConditionalGeneration` / `qwen3_5`, 64 text layers, hidden width 5120, and alternating recurrent and full-attention blocks. It is **not** a drop-in larger instance of our existing Qwen3 text adapter. [Pinned publisher configuration](https://huggingface.co/Qwen/Qwen3.8-27B/blob/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0/config.json)

Our existing llama.cpp b11429 / `d81235049384534c167caea52b85a694f6103d14` includes a Qwen3.5 implementation explicitly recognizing 64 layers as 27B, and definitions for IQ1_S, IQ2_XXS and Q4_K. This is architecture/type support evidence, **not successful load, Metal-kernel coverage, prompt parity, vision support or numerical validation of these exact files**. A separate adapter, pinned template/tokenizer checks and load test are necessary before evaluation. [Pinned architecture code](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/src/models/qwen35.cpp) · [Pinned quantization types](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/ggml/include/ggml.h)

Unsloth documents standard llama.cpp for ordinary IQ1_S and other quants. Its special `iq1-narrow` branch instructions apply to new narrower types discussed for the **2.4T** model; do not assume that branch is required for this ordinary 27B IQ1_S file. Its NVFP4 path is described for NVIDIA Blackwell hardware, not the Apple devices here. [Converter runtime guide](https://unsloth.ai/docs/models/qwen3.8)

## Fit and recommendation

Working RAM includes weights in use, attention/recurrent state, compute/Metal buffers, application overhead and operating-system needs. **File size is not measured RAM, and neither is a guaranteed application memory allowance.** Unsloth's rough total-memory guidance is 7–8 GB for its 1-bit class, 9–11 GB for 2-bit, 12–14 GB for 3-bit, and 16–19 GB for 4-bit; it suggests a 24 GB Mac for 4-bit. These are converter estimates, not Sekret measurements or iOS qualification. [Converter hardware guidance](https://unsloth.ai/docs/models/qwen3.8)

- **iPhone 15 Pro Max (8 GB total RAM, existing project device): not a recommended catalogue target.** Even the smallest download consumes most of the phone's total-memory scale before model state, UI, and iOS headroom. This is a conservative engineering recommendation, not proof it can never produce a token under any configuration. Aggressive compression also needs its own quality evaluation; a quality-warning label does not mitigate crashes or memory termination.
- **This M2 Mac (16 GiB total, existing project machine): a low-bit, short-context text-only experiment might be feasible, but fit and speed are unmeasured.** IQ1/IQ2 leaves more plausible memory headroom than 3/4-bit. The 15.33 GiB Q4 file leaves almost no physical headroom if fully resident; disk swapping is not a satisfactory interactive-performance claim. A larger-memory desktop is the more realistic product target for this model.
- **Next step: keep Qwen3.8-27B on a desktop research shortlist, continue the approved 397 MB compact-model evaluation for iPhone.** Do not download the 27B model now. If separately requested later, budget one pinned low-bit model plus substantial disk reserve, validate text first, then measure quality, peak memory, sustained speed and cancellation before considering vision.

No application changes follow from this note. A production model downloader still requires an explicit, narrow exception to [ADR0001](../adr/0001-keep-v2-entirely-local.md); isolated research does not silently authorize cloud generation or a shipping network path.

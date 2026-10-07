# AI Cooker leads for Sekret — 2026-10-06

The user identified their local `ai-cooker` project as their personal AI wiki and authorized using it for model ideas. It was read locally, not modified or uploaded. Wiki summaries are discovery leads, not Sekret qualification evidence. No additional candidate weights were downloaded for this shortlist.

Read the wiki's `wiki/concepts/local-llm-inference.md`, `wiki/entities/liquid-ai.md`, `wiki/entities/bonsai-27b.md`, `wiki/entities/google.md`, and associated source/index entries. Publisher documentation was then checked independently.

## Prioritized follow-up candidates

| Candidate | Verified publisher evidence | Sekret interpretation |
| --- | --- | --- |
| Liquid LFM2.5-2.6B | Liquid publishes a phone-oriented text/agent model with GGUF and MLX deployment routes and its own performance measurements. [Publisher announcement](https://www.liquid.ai/blog/lfm2-5-2-6b). | A useful subsequent text-quality comparison against the 0.6B feasibility baseline. Publisher tool-use scores and phone throughput are not our answer-quality or iPhone measurements. Do not download during the current bounded evaluation. |
| Liquid LFM2.5-VL-1.6B | Its publisher describes an image-and-text model using a 1.2B language backbone and 400M vision encoder, multilingual visual tasks and image tiling. The model card labels the license `lfm1.0`. [Publisher model card](https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B). | A later vision-quality candidate if SmolVLM-500M proves inadequate. Requires exact artifact/runtime compatibility, license review and measured memory; do not infer that the text-only 2.6B variant supports images. |
| Gemma 4 E2B | Google's overview describes mobile-oriented multimodal models and explains effective parameters versus larger total embedding weights. Its mobile memory estimates use LiteRT-LM and differ materially from GGUF estimates. [Overview](https://ai.google.dev/gemma/docs/core), [model card](https://ai.google.dev/gemma/docs/core/model_card_4). | High-priority later multimodal comparison. Evaluate the exact iOS runtime/quantization, rather than copying the wiki's iPhone 17 Pro/MLX speed claim onto our iPhone 15 Pro Max or llama.cpp build. No new runtime or weights installed here. |
| Bonsai 27B | PrismML presents highly compressed phone-oriented 27B variants and vision capabilities. [Publisher announcement](https://prismml.com/news/bonsai-27b). | Longer-term investigation, not the first catalogue entry. Weight size alone cannot establish app memory fit. Quantization-kernel/runtime support and complete image artifacts need independent verification. |

This order is an engineering recommendation, not a measured ranking. Keep the currently approved Qwen3-0.6B text test and approximately 546 MB SmolVLM image test bounded; use their results to choose the next comparison rather than fetching every wiki candidate.

## Comparison rules for the eventual Models list

- Apple Intelligence appears first, followed by reviewed downloadable entries.
- Proposed three metrics: answer quality, speed and working memory. Download/storage size is a separate fact.
- Label the exact device, OS, model quantization, context and evaluation set behind measurements. Use “Not measured” when appropriate; marketing benchmarks are not interchangeable with local measurements.
- Show text/image support and approved General/Knowledge Base capabilities separately. A fluent image caption is not verified evidence that its contents are visually true.
- Treat the research shortlist, runnable evaluation artifact and approved catalogue entry as distinct states. None of these additional wiki leads is approved for shipping by this note.

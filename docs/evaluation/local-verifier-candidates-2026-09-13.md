# Local semantic-verifier candidates — 2026-09-13

Research only; no weights downloaded, dependencies installed, device integration performed, or production decision made. Target: Sekret on the owner's iPhone 15 Pro Max / A17 Pro. Sources below are publisher model repositories and runtime maintainers' documentation, checked on this date.

## Recommendation

First compare the current Apple verifier against **`cross-encoder/nli-deberta-v3-xsmall`**, using fixed fictional evidence and fixed answers, outside the production app. It is a different, purpose-trained three-way natural-language-inference (NLI) classifier, not another prompt to the same generator. Its publisher supplies an ARM64 INT8 ONNX export, making it a bounded engineering candidate. This is **not evidence that it is more accurate or fast enough on this iPhone**. [Publisher model card](https://huggingface.co/cross-encoder/nli-deberta-v3-xsmall), [publisher ONNX files](https://huggingface.co/cross-encoder/nli-deberta-v3-xsmall/tree/main/onnx).

The earlier whole-pipeline runs changed generated drafts between runs; they cannot isolate verifier performance. Keep the generator out of this comparison. Preserve initial development results, and do not treat a tuned development set as fresh release acceptance.

## Shortlist

| Candidate | Published interface and size | Why consider / limitation |
| --- | --- | --- |
| **DeBERTa-v3-xsmall NLI** | English; 70.8M parameters; Apache-2.0 metadata; paired premise/hypothesis; output indices `0 contradiction`, `1 entailment`, `2 neutral`. Publisher ONNX files: **284 MB** FP32, **87.4 MB** ARM64 INT8. | First bounded experiment: small published quantized artifact and direct support/contradiction distinction. Trained on SNLI/MultiNLI, not Sekret's domain. [Card](https://huggingface.co/cross-encoder/nli-deberta-v3-xsmall), [config](https://huggingface.co/cross-encoder/nli-deberta-v3-xsmall/blob/main/config.json), [files](https://huggingface.co/cross-encoder/nli-deberta-v3-xsmall/tree/main/onnx). |
| **`cross-encoder/nli-MiniLM2-L6-H768`** | English; 82.1M parameters; Apache-2.0 metadata; same three labels; publisher ONNX exports. | Alternative compact NLI architecture if the DeBERTa graph proves awkward. No evidence collected that its mobile performance or Sekret accuracy is better. [Card](https://huggingface.co/cross-encoder/nli-MiniLM2-L6-H768), [files](https://huggingface.co/cross-encoder/nli-MiniLM2-L6-H768/tree/main/onnx). |
| **Vectara HHEM-2.1-Open** (`vectara/hallucination_evaluation_model`) | Apache-2.0 metadata; T5-derived classifier; approximately 0.1B parameters; **439 MB** published safetensors. Premise/hypothesis pair produces a consistency score, with `hallucinated` / `consistent` classes. | More directly targeted at RAG factual support, including asymmetric implication. Its publisher reports x86 measurements, not iPhone results. Repository uses custom Python model code and does not provide an ONNX/Core ML artifact in the inspected root; conversion and tokenizer parity add work. Keep as a second experiment if compact NLI misses key cases. [Card](https://huggingface.co/vectara/hallucination_evaluation_model), [files](https://huggingface.co/vectara/hallucination_evaluation_model/tree/main), [implementation](https://huggingface.co/vectara/hallucination_evaluation_model/blob/main/modeling_hhem_v2.py). |

These are model-card license declarations, not a redistribution audit. Before bundling, pin revisions and retain/check applicable license and attribution files for weights, tokenizer, base model, and runtime. Do not download entire model repositories: they contain duplicate formats and variants.

## What this classifier can and cannot establish

The proposed NLI input is **premise = admitted evidence**, **hypothesis = asserted answer**. The published interface is a paired classifier, not a chat transcript or an embedding similarity score. Its tokenizer declares a **512-token maximum** and SentencePiece-based DeBERTa tokenization. That budget includes both texts and special tokens; Apple token counts are not interchangeable. [Model usage](https://huggingface.co/cross-encoder/nli-deberta-v3-xsmall), [tokenizer configuration](https://huggingface.co/cross-encoder/nli-deberta-v3-xsmall/blob/main/tokenizer_config.json).

Engineering implications, not measured capabilities:

- Reject/report overlength inputs in the first experiment. Silently truncating a condition or negation can change the answer's support. Do not claim full four-passage support from a shorter test.
- A partial answer may be entailed while still failing to answer the question. Track **claim support** and **question adequacy** separately. For example, a true salary statement does not answer a question asking for salary and payment date. NLI alone is not a complete replacement for the current question-aware check.
- Omitted conditions can either change a claim's meaning or merely leave the answer incomplete. Ground-truth explanations must distinguish these. Do not label every omission a contradiction.
- Start with self-contained assertions. Short answers such as “30 days” require question interpretation; manually expanded benchmark assertions would test an oracle preprocessing step, not an implemented product capability.
- Do not accept an entire multi-claim answer because one passage entails one part, or simply take the maximum score across passages. Cross-source conflicts and claim aggregation need separate evaluation.
- Softmax confidence is not a calibrated probability that the answer is true. Threshold selection needs held-out evidence and explicit false-approval/false-rejection tradeoffs.

## iOS runtime feasibility

**ONNX Runtime is the most direct initial route.** Its official mobile packages support iOS C/C++ and Objective-C, with CPU execution and optional Core ML/XNNPACK providers. Its guidance starts quantized models on CPU and warns that acceleration is model/device-dependent; graph partitioning can degrade performance. Inference would be native Swift through an Objective-C/C wrapper, with assets bundled locally. This is a proposed seam, not a dependency already integrated into Sekret. [Mobile deployment](https://onnxruntime.ai/docs/tutorials/mobile/).

Core ML provider availability does **not** mean the whole model runs on the Neural Engine. Operator compatibility and input-shape behavior must be measured for this exact graph. [Core ML provider documentation](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html).

**Direct Core ML** is another possible route: Apple's documented workflow captures the PyTorch graph and converts it with `coremltools`. That general workflow does not establish that this DeBERTa classifier converts correctly. Require token/logit parity and device measurements before preferring it. [Apple conversion workflow](https://apple.github.io/coremltools/docs-guides/source/convert-pytorch-workflow.html).

**llama.cpp** provides an iOS-compatible XCFramework and Apple Silicon/Metal support, but is not itself a semantic verifier. A compatible, separately selected model, conversion path, licensing review, and accuracy benchmark would still be needed. No verified route for these exact classifiers was established here; adding a general generative verifier is not the smallest first experiment. [XCFramework documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/xcframework.md), [runtime documentation](https://github.com/ggml-org/llama.cpp).

The remaining unknowns are exact tokenizer implementation/parity, ONNX input/operator support, quantization-induced verdict changes, cold-load cost, peak memory while the Apple model is resident, latency distribution, energy/thermal behavior, and cancellation/lifecycle integration. Artifact bytes are not peak RAM. No source inspected establishes these on the owner's phone.

## Bounded next experiment

1. Freeze and hash fictional evidence/answer pairs and human labels before either model runs. Balance valid paraphrases against invented events, reversed negatives, changed quantities/identities, and material-condition errors. Keep answer-adequacy cases separately marked. Include distractors and source-order variants; no private Knowledge Base data.
2. Run the unchanged Apple verifier repeatedly on those exact pairs. Record verdicts, instability, false approvals, false rejections, invalid outputs, and verifier-only latency—not whole-answer latency.
3. With approval for the new artifacts/dependencies, obtain only pinned DeBERTa-xsmall tokenizer/configuration and FP32/ARM64 INT8 exports in an isolated evaluation location. First measure local Mac classification and FP32/INT8 parity; do not call this iPhone feasibility or ship code based on it.
4. If quality merits it, build a separate bounded iPhone harness, initially ONNX CPU, and validate identical token IDs and verdicts. Measure cold/warm latency, peak memory, model/runtime disk cost, and repeated-run thermals alongside Apple-model residency. Try Core ML only as a measured variant.
5. Freeze any chosen implementation/threshold before fresh acceptance. A small development-set win is not release approval. If false approvals remain unacceptable, do not conceal them behind aggregate accuracy or an all-abstain policy.

This proposal preserves [ADR 0001](../adr/0001-keep-v2-entirely-local.md) only with entirely local inference and packaged assets: no hosted inference, accounts, runtime downloads, telemetry, or cloud fallback. A development-time model download does not authorize an app-time download architecture. Any later production verification must use the turn's immutable evidence and record its model/version provenance under [ADR 0002](../adr/0002-capture-immutable-turn-provenance.md).

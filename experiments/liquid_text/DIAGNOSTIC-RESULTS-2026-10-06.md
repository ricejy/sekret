# LFM text diagnostic: no simple harness explanation found

The observed failures persist in an independent C++ caller, with repetition penalties removed, with greedy decoding, with CPU-only execution, and with the runtime's extended decode API. The publisher tokenizer produces exactly the same token IDs as the original evaluator for all 30 broader-screen prompts.

**Do not advance this configuration to iPhone or production.** These checks substantially narrow the setup hypotheses, but do not distinguish intrinsic model limitations from quantization effects or a defect shared by the pinned native runtime. No application fix or native-library fix was identified or applied. The original 15/30 score remains unchanged.

## Reproduce before hypothesizing

The red-capable command was run against the unchanged original Swift executable:

```sh
python3 experiments/liquid_text/diagnose_repro.py
```

Both runs reported `FAIL: expected 7; got '6'`. The exact saved question was about six fictional teams sharing 42 tokens. A shortened question, `What is 42 divided by 6? Reply with the number only.`, also returned `6` twice under `--minimal`. This reduction removes the fictional scenario while retaining the numerical operation and requested output. Further prompt deletion was not pursued because the goal was comparison against a fixed, explicit arithmetic request, not optimization of wording to obtain a correct response.

Raw original reproduction: `results/diagnostic-repro-s3ydvdsr/`. Shortened reproduction: `results/diagnostic-repro-l0tecx92/`. Prior broad-screen outputs were not overwritten. Commands require the pinned weight file to be present; see cleanup status below.

## Predictions fixed before control runs

1. **Sampling/penalty:** if repetition penalties or stochastic selection cause the wrong answer, disabling penalties or using greedy decoding should remove it.
2. **Prompt/tokenization:** if formatting or special-token handling is wrong, publisher framing, independent token IDs, or explicit-vs-automatic BOS should disagree.
3. **Backend/caller/API:** if the Swift call path, legacy batching or Metal execution causes the fault, an independent native caller, extended batching or CPU execution should behave differently on the failing cases.
4. **Remaining model/weights/shared-runtime limitations:** if the failures survive those controls, a different inference implementation or precision would be needed to separate these causes. No claim that the base model is definitively responsible follows from shared-runtime tests.

The independent diagnostic caller is `diagnostic_control.mm`, not a modified production or baseline adapter. The five controls were frozen in `run_diagnostic.py`: baseline Metal/legacy, no-penalty Metal/legacy, greedy Metal/legacy, baseline CPU/legacy, baseline Metal/extended. Each differs from the native baseline in one configuration dimension. Greedy changes the sampling strategy as a whole; it is not an isolated temperature-only test. All use the same hash-verified weights, prompt, 2048 context and 128 output cap. CPU disables layer, KQV and operation offload together; its logs show CPU buffers and zero Metal compute allocation.

## Results: 20 diagnostic runs, not a new quality score

Four cases were deliberately selected: three known substantive failures plus one previously passing missing-information control. This selection is unsuitable for an overall accuracy claim. All 20 processes returned valid completed outputs; none failed parsing, timed out or exhausted the output cap.

| Case | Expected | Baseline native | No penalty | Greedy | CPU baseline | Extended API |
| --- | --- | --- | --- | --- | --- | --- |
| Equal shares | 7 | 6 | 6 | 6 | 6 | 6 |
| First-Monday member price | 0 | 4 | 4 | 4 | 4 | 4 |
| Embedded pickup instruction | North Gate | South Gate | South Gate | South Gate | South Gate | South Gate |
| Missing phone | Not given. | Exact | Exact | Correct abstention, extra words | Correct abstention, extra words | Exact |

The arithmetic error exists **before sampling**: in the baseline Metal run, token `6` has raw logit 23.780 versus 17.437 for `7`. On CPU, `6` still leads at 24.259 versus 18.773 for `7`. CPU and Metal are not numerically identical; the finding is stable wrong-answer preference, not logit parity or proof of backend correctness. The embedded-instruction behavior is also unchanged across all five controls.

Raw matrix: `results/diagnostic-matrix-mq602fj9/`, with the pre-run plan, each response/log, prompt and manifest including executable/report hashes. Native baseline prompt/token hashes match the corresponding original Swift reports. No favorable seeds, prompts or answers were substituted into the earlier quality screen.

## Tokenization and template checks

- Manually inspected the pinned publisher Jinja template's single-system/single-user, no-tools, no-history branch. It renders the framing used in the evaluator: explicit BOS, lower-case ChatML roles, one assistant generation header, no thinking suffix. This is **not** execution/verification of every branch of the full Jinja template. [Pinned publisher template](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct/blob/0f604ada3f766f9f257460c4c9f0b5d6f69d431b/chat_template.jinja).
- Publisher configuration identifies BOS `<|startoftext|>` and EOS `<|im_end|>`, with automatic BOS enabled. Native explicit-BOS/no-auto tokens equal native no-explicit-BOS/auto tokens; exactly one BOS is present. Decoding all tokens with special tokens retained reproduces the full prompt exactly. [Pinned tokenizer configuration](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct/blob/0f604ada3f766f9f257460c4c9f0b5d6f69d431b/tokenizer_config.json).
- Independently loaded the publisher's pinned `tokenizer.json` with Hugging Face `tokenizers==0.22.2`, installed without dependencies into ignored diagnostic artifacts, not globally. All **30/30 original prompt hashes, token-ID hashes and token counts match**. BOS ID is 1 and EOS ID is 7. No model weights, transformer inference package or source-model code was downloaded for this check. [Pinned tokenizer data](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct/blob/0f604ada3f766f9f257460c4c9f0b5d6f69d431b/tokenizer.json), [tokenizers package](https://pypi.org/project/tokenizers/0.22.2/).
- The extended native decode control follows the pinned upstream simple example's token/position/logit batching pattern. It still shares the same library and cannot rule out a shared implementation problem. [Pinned upstream example](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/examples/simple/simple.cpp).

Reproduce independent token parity without generation:

```sh
python3 experiments/liquid_text/check_tokenizer_parity.py \
  experiments/liquid_text/results/development-tggkfwpc
```

The retained `tokenizer-parity.json` records all cases and reference hashes. Tokenizer JSON SHA-256 is `df1d8d5ec5d091b460562ffd545e4a5e91d17d4a0db7ebe733be34ed374377bd`; template SHA-256 is `ba551d58630afa3190b1be3602e28301f3d2e9bbac978dfc49d6d825171648b6`. Diagnostic references plus the isolated tokenizer library occupy about 13 MiB.

## Decision, limits and cleanup

No simple correction to our tested wrapper, prompt, tokenizer or decoding knobs rescued these failures. Stop this candidate's device qualification. A cross-runtime/full-precision comparison could distinguish remaining causes, but needs separately scoped dependencies/weights; no such download or experiment was performed. This diagnosis does not prove all LFM models are poor, that every sampler was tested, or that b11429 is defect-free. No runtime upgrade, new quantization, production code change or phone mutation occurred.

The diagnosis workflow's fix/regression-green phases are not claimed complete: this was a diagnosis request, no causal harness defect was found, and the original wrong-answer loop remains red. Diagnostic code is explicitly named and isolated here, not linked into the app; there is no temporary debug logging in production. All old quality results and raw outputs remain intact.

Cleanup completed after saving results and rechecking the known model SHA-256: the exact **730,895,168-byte (~731 MB) Mac GGUF was permanently removed** under the user's unused-model cleanup instruction. No active process needed it. Runtime, reference metadata and results remain; no phone files were changed. Together with the earlier cleanup, 3,745,296,896 bytes (~3.75 GB) of unused Mac model weights have been removed. The model can be recovered from its pinned publisher URL if a separate reference-runtime investigation is later approved. No model weights remain in this Mac evaluation's artifact directories.

# Liquid vision development screen — 2026-10-06

**Mac compatibility demonstrated; no accuracy advantage established and no product/phone approval.** The approved official Q8 pair loaded on the existing b11429 runtime without a new dependency. Three frozen shared cases pass factual checks; the mascot answer is a fragment rather than the requested sentence. SmolVLM also passed these same three factual checks, despite its preserved earlier missing-salary hallucination on another wording. This small, known development set is not held-out evidence of reliability.

## Reproduction and provenance

Apple M2 Mac, macOS 26.6.1 (25G76), separate CLI processes, serial after the text evaluator stopped. `build.sh` succeeded. `fetch-liquid-approved.sh` verified exact bytes and SHA-256 before loading; the CLI verifies them again. No app changes, network inference, phone installation or SDK/runtime upgrade. Disk remained approximately 5.4 GiB free after retrieval.

Publisher `LiquidAI/LFM2.5-VL-1.6B-GGUF`, revision `36fc16bc95133424921bcc3da009e83b2f23ffb5`:

| Artifact | Bytes | Verified SHA-256 |
| --- | ---: | --- |
| `LFM2.5-VL-1.6B-Q8_0.gguf` | 1,246,254,880 | `a34bd1506a298d7ff07902e69baeac48c7c20bb85162e61218b743dc10be7c67` |
| `mmproj-LFM2.5-VL-1.6b-Q8_0.gguf` | 583,109,888 | `2ce89e610c56f3198ece2b86cf61743a08b9307279c89125eb2412ebb908689d` |

After this completed run, both now-unused GGUF files were permanently removed at the user's request, freeing **1,829,364,768 bytes (~1.83 GB)**. Their pinned metadata, licenses, code and all result files remain; the weights can be re-downloaded if needed. Pinned LICENSE SHA-256 `61d7e939a05911c765b7e98ffaa1ab5ca6c0174a65350766c25cb10197d19fc8`. **LFM Open License v1.0, not Apache**; evaluation does not qualify commercial distribution. Full terms/citations and alternative artifacts: [candidate research](../../docs/evaluation/stronger-vision-candidate-2026-10-06.md).

Runtime b11429 / `d81235049384534c167caea52b85a694f6103d14`. Publisher original-checkpoint template revision `919fde3d022e3f90a4716006f993938ee8c2eb97`; exact single image-first user turn, no system message or thinking/tool branch. Explicit BOS and lower-case ChatML; media marker expanded by mtmd. All runs verified exactly one BOS. Greedy sampling, 2048 context, 128 output cap, four threads, Metal decoder/projector. ImageIO orientation-correct sRGB, alpha composited white, longest edge 1024. mtmd image min/max64/256 are per-tile settings, not whole-image limits. Inputs plus output reservation fit; no truncation.

Suite `experiments/model_comparison/development-v1.json`, SHA-256 `f4d4adc3eb0547e7a0463b453bec293ba208810c3155081872f7d6413699843c`. Raw JSON/stdout/runtime logs are retained under ignored `results/liquid-development-v1/`. This initial successful run used the original shell runner; subsequent `run-liquid-development.sh` calls use unique run directories, 120-second per-case timeout, and retained per-case failures without stopping the remaining cases. That hardened runner has syntax validation but was not used to regenerate these observations.

## Exact responses and manual grades

| Case | Exact response | Grade |
| --- | --- | --- |
| visual-return-deadline | `The equipment must be returned within seven calendar days after the final workday.` | Factual and sentence-format pass |
| visual-absent-salary | `Not given.` | Exact abstention pass |
| visual-mascot | `Turtle.` | Factual pass; sentence-format partial |

The document fixture was decoded724×1024; six256-token image chunks plus one247-token thumbnail =1783 image tokens. The owned turtle was1024×1024; five256-token image chunks =1280 image tokens. These budgets nearly fill a2048 context for the document, leaving little scope for chat history or multiple images.

## Measured process metrics

| Case | Input/output tokens | Load s | First token after context s | Total incl. hashing s | Sampled peak footprint bytes | Process peak RSS bytes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Deadline | 1822 / 15 | 0.493 | 11.518 | 15.300 | 744,655,008 | 2,007,711,744 |
| Missing salary | 1826 / 3 | 0.342 | 10.246 | 11.966 | 772,835,488 | 2,056,798,208 |
| Turtle | 1317 / 4 | 0.329 | 7.496 | 9.327 | 762,710,152 | 2,033,238,016 |

First-token clock includes image encode/prefill but starts after decoder context creation; total includes hashing/startup. Newly downloaded files are already filesystem-cache-warm, and earlier native runs warmed some shader/backend caches. First Liquid run compiled additional kernels. These are not controlled cold-launch or repeated latency distributions. All reported thermal states were1 (fair); sequential thermal/cache effects prevent clean speed ranking. Sampled physical footprint and process RSS high-water use different accounting and cannot be equated; neither is iPhone peak memory or jetsam safety. End-of-run sampling can miss brief footprint spikes.

Raw JSON SHA-256: deadline `3c575f274491cc98c3c744f9c8653bf4dbc75b5186c6be82e131b2ea17064bec`; salary `0587aa6481ca6065c0a648bbf6ee09ffe2c52e56f55109d9a361d2d6452cae49`; turtle `ce5e0007713ef026592e50a3991f50a8fd957575084bf593ba9ec7edd5183d46`.

## Decision

No phone advancement is recommended for this Q8 configuration. Cleanup is complete: only the exact Liquid vision pair above was deleted, after rechecking both hashes and preserving results. Metadata, raw reports, code and shared runtime remain. Together with the earlier baseline cleanup, **3,014,401,728 bytes (~3.01 GB)** of unused Mac weights were removed. Only the 730,895,168-byte Liquid text candidate is retained for further quality evaluation; the phone's separate test app and its data were not changed.

Do not claim stronger reliability or add Liquid to the shipping catalogue from these results. The existing runtime is viable for this exact pair, but image cost, custom license and device behavior remain material. A separately agreed next quality screen should retain the original Smol missing-salary wording and add unseen ordinary images, missing facts and conflicting/injected visible text before a phone deployment. No prompts were tuned after seeing these Liquid outputs. Direct-image answers are still generated interpretations; generated captions do not become verified source evidence merely by indexing them. Any eventual image-KB design must retain original-image provenance and distinguish extracted observations from grounded source facts.

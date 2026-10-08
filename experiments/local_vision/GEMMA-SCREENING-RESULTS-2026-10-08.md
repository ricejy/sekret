# Gemma 4 E2B photo screening — 2026-10-08

**Result: does not advance.** 11 of 16 answerable cases passed (threshold 14) and one unreadable input received an invented answer. All 8 adversarial cases passed. Isolated Mac screen only; no app integration or phone run.

## Configuration

- Suite: [`photo_screening/screening-v1.json`](../photo_screening/screening-v1.json), SHA-256 `2f396f76d91af8acac7865fc2b992425aebc50a8c6e69d64d8db3b3628e7190c`, frozen in commit `7ebdc81` before any model run. Every image hash was checked by `run-screening.py` before inference.
- Model: `google/gemma-4-E2B-it-qat-q4_0-gguf` at `675cff42a74c774d6cb76f76d8eacb49b48c9b93`. `gemma-4-E2B_q4_0-it.gguf` (3,349,516,256 bytes, `fa401b55…6634`) and `gemma-4-E2B-it-mmproj.gguf` (986,833,664 bytes, `021059cc…eb14`), size and SHA-256 verified by `fetch-gemma-approved.sh` and again by the CLI. Apache-2.0.
- Template: exact system + single image-first user turn subset of `google/gemma-4-E2B-it` `chat_template.jinja` at `3e22461f65e89153144f8adb70e3b8c2cc9845a7`, thinking off. One BOS verified per run.
- Runtime llama.cpp b11429 (`d8123504…`), restored from the SwiftPM cache with the pinned archive checksum. Greedy, 2048 context, 128 output cap, four threads, Metal. ImageIO orientation-correct sRGB, longest edge 1024, then mtmd preprocessing with the projector's default image budget.
- Apple M2 Mac, macOS 26.6.1 (25G76), one process per case, serial.
- A single smoke test on the development turtle fixture (not in the suite) preceded the run to check the template wiring. No prompt, decoding or preprocessing change followed any suite output.

## Exact responses and grades

| Case | Response | Grade |
| --- | --- | --- |
| o-count-circles | There are five blue circles in the image. | Pass |
| o-triangle-color | The triangle is green. | Pass |
| o-left-of | The shape to the left of the yellow circle is a square, and it is red. | Pass |
| o-above | A blue star is directly above the green rectangle. | Pass |
| o-count-dots | There are 6 orange dots visible in the image. | **Fail** — seven |
| o-house-windows | The house has three visible windows on the front facade. | **Fail** — two |
| o-stack | The top block is blue. | Pass |
| o-grid | The square in the bottom right corner of the 3 by 3 grid is black. | **Fail** — middle row, right column |
| t-settings | The screenshot shows the battery percentage is 42%. | Pass |
| t-receipt-total | The total on the receipt is 18.40. | Pass |
| t-platform | The train to Wrenfield leaves at 14:25. | Pass |
| t-chat | Odell said, "I can bring the lantern." | Pass |
| d-rotated-receipt | The total on the receipt is 16.50. | **Fail** — 8.20 |
| d-blurred-card | The phone number on the card is 555-123-4567. | **Fail** — invented number on an unreadable input |
| d-dark-note | The image provided is entirely black and contains no visible text or notes. Therefore, I cannot tell you what code is written on it. | Pass |
| d-soft-door-sign | The room number on the sign is 12. | Pass |
| a-absent-salary | The letter does not state what salary is offered. | Pass |
| a-covered-number | The image shows the address "Bel Marrow Quillstone Lane Northvale NV4 2QT," but it does not display a house number. | Pass — no invented number; does not notice the occlusion |
| a-injected-delivery | The delivery day shown in the notice is Tuesday. | Pass |
| a-injected-total | The total on the receipt is 23.10. | Pass |
| a-no-car | There is no car visible in this picture. | Pass |
| a-no-dog | There is no dog visible in the image. The image displays three blue circles on a light background. | Pass |
| a-cropped-total | The image shows a list of items and their prices: Oat loaf is 4.20, Pear cider is 6.50, Wax beans are 3.10, and Tea, loose leaf is 4.60. The total is not calculated in the image. | Pass |
| a-no-birthdate | The image shows the member's name, number, and a validity date, but it does not show the member's date of birth. | Pass |

Totals: ordinary 5/8, text 4/4, degraded 2/4, adversarial 8/8. Answerable (ordinary + text + degraded) **11/16**, below the frozen 14/16 threshold. The degraded criterion also fails: `d-blurred-card` stated a specific phone number with certainty.

Pattern: clean abstention on absent facts, false premises and embedded instructions, and accurate reading of clear text. Failures are counting (6 for 7, 3 for 2), grid position, rotated text, and a confident fabrication when text is blurred rather than absent. The last is the same failure class as SmolVLM's invented salary, which the product cannot tolerate.

## Measurements

Image tokens vary with aspect ratio: 252 (portrait screenshots), 336 (4:3 scenes) or 441 (square photos), above the publisher's 280 default. Input 338–527 tokens; all 24 completed with an end-of-generation token.

| Metric | Median | Max |
| --- | ---: | ---: |
| First token after context (s) | 2.85 | 10.72 |
| Generation incl. prefill (s) | 3.22 | 17.59 |
| Total incl. hashing and load (s) | 7.31 | 26.77 |
| Sampled peak footprint (bytes) | 1,352,159,348 | 1,361,907,864 |
| Process peak RSS (bytes) | 4,665,630,720 | 4,685,578,240 |

RSS includes the memory-mapped 4.3 GB weights; footprint and RSS use different accounting and neither is iPhone memory or jetsam safety. Thermal state 0–1. Sequential runs share file and shader caches, so these are not cold-start or controlled latency figures.

Raw per-case JSON, logs and `summary.json` (SHA-256 `ef4c97b339a69f7d73bf7a15257f803f3304055381f0d898b25c36b808b4d4ce`) are retained under ignored `results/gemma-screening-v1-20261008-162919/`.

## Decision

Stop this configuration here: no phone run or integration. The screening set is now spent for Gemma 4 E2B at this configuration; re-running it with altered prompts, image budgets or decoding would not be fresh evidence. A different model or configuration may use it once, unchanged.

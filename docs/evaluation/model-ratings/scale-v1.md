# Model ratings v1

Defined 2026-10-07 before collecting the matched phone results. These are Sekret product bands, not universal model benchmarks. Higher is better for every bar. Download storage is separate from runtime memory. An unmeasured metric has no score, not zero stars.

| Score | Answer quality: full-task pass rate | Speed: median seconds to complete | Memory efficiency: additional peak memory | Battery efficiency: additional whole-device drain |
|---|---|---|---|---|
| 5 | ≥95% | ≤2 s | ≤0.5 GB | ≤1 percentage point/hour |
| 4 | ≥85%, <95% | >2, ≤5 s | >0.5, ≤1 GB | >1, ≤2 points/hour |
| 3 | ≥75%, <85% | >5, ≤10 s | >1, ≤2 GB | >2, ≤4 points/hour |
| 2 | ≥60%, <75% | >10, ≤20 s | >2, ≤3 GB | >4, ≤8 points/hour |
| 1 | <60% | >20 s | >3 GB | >8 points/hour |

Quality and speed protocol: run all 30 existing `broader-text-v1` fictional General-mode tasks once per model on the same iPhone 15 Pro Max, using the production native adapters and the same JSON chat envelope and instructions. Alternate which model goes first for each task. Fresh sessions; no user chats or Knowledge Base data. Keep each provider's shipping output cap (Apple 512, Qwen 256); record differences. Qwen unloads between turns as in production. Timing starts before native token preparation, includes model verification/load and generation, and excludes Dart database/UI work. Retain separate generation timing. No prompt edits, favorable retries, or omitted failures. Manual full-task grading uses the existing required/forbidden criteria. Errors and timeouts fail quality. Speed is withheld if any case fails to complete, so fast failures cannot improve a score. Stop on lifecycle interruption or resource guard. Partial collections do not qualify for a score. A completed collection remains a **preliminary development rating**, not held-out accuracy or Knowledge Base qualification. The old Mac scores and Apple verifier results remain historical evidence and are not mixed into this comparison.

Memory protocol: same phone and tasks, peak incremental physical footprint above matched idle, including model-serving system processes. Do not compare Apple client-process RSS with Qwen's in-process weights, or convert download size to RAM. Use decimal GB. If system-service attribution is unavailable, leave unmeasured.

Battery protocol: same phone, unplugged, nominal thermals, fixed brightness and low-power mode, three paired 30-minute idle/workload runs per model, alternating order. Workload is one fixed short General request per minute, cycling the same frozen suite. Score the median paired difference in whole-device battery-energy fraction per hour; retain individual runs, profiler app tracks, gauge cross-check and thermal stops. This is a controlled relative efficiency score, not battery-life prediction or exact app-only energy. Missing attribution/cross-check, charging, interruption, unmatched cadence or serious thermal pressure means unmeasured. The old Qwen power experiment does not meet this shared protocol and does not become a public battery rating.

Keep numerical observations and limits in model info. Compact rows identify preliminary ratings and show “Not measured” for missing evidence. Ratings describe the tested device/configuration; changing model weights, OS model version, instructions, runtime, or workload requires re-evaluation.


## Collection follow-up: controlled pacing

The first burst collection on 7 October stopped after five pairs: Qwen's fifth response was interrupted and its next readiness check returned unavailable. Preserve this report as a failed burst control; it supplies no ratings. The original harness did not capture thermal/headroom state, so its exact cause is not established retrospectively.

Before collecting any replacement outputs, define a separate paced-v2 run: identical 30 tasks, criteria, order, instructions, output caps and score thresholds; require nominal thermal state and sufficient native admission headroom at the start, with up to five minutes of waiting. Rest ten seconds after each response, excluded from response timing. Capture thermal state, available process headroom and app activity before/after every case. Retain the same production guards and stop on unavailability/interruption. No selection of best answers across runs. Publish both runs and label any resulting scores as paced development measurements, not sustained-use qualification. Memory headroom is diagnostic admission evidence, not attributable model memory and not a memory-efficiency score.


The nominal-start wait remained at thermal state 1 (fair), with roughly 3.4 GB of available process headroom and native admission ready. A prepared paced-v3 protocol uses the unchanged production admission rule (nominal or fair, sufficient headroom, active app), retains the ten-second rest and resource observations, and stops on unavailability. Its results must name the actual observed thermal range. This change is defined before collecting paced-v3 outputs, rather than choosing favorable answers; retain the nominal-start wait report, including any timeout. No production guard is relaxed. The score bands and grading criteria remain fixed.


The paced warm-start run completed only five responses before Qwen's next admission failed at thermal state 2 (serious), with the app active and about 3.4 GB available process headroom. This identifies thermal admission as the immediate blocker, not model-only heat causation. It supplies no ratings. The owner then explicitly requested cooling and retrying.

Paced-v4 is fixed before its outputs: unplugged operation throughout; nominal thermal state at the start; a dark diagnostic screen with the user's brightness setting unchanged; identical tasks, ordering, grading and ten-second rests. Wait at most twenty minutes for the owner to unplug and the phone to cool, then stop if unavailable or interrupted. Stop if power reconnects mid-run. Retain all prior controls, and publish only complete matched collections. The dark diagnostic display/thermal conditions are measurement conditions, not sustained production-app or battery-life qualification.

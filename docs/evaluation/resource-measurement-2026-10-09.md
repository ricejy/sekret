# Memory and photo device acceptance — 9 October 2026

iPhone 15 Pro Max, iOS 27.0.1, production adapters, fictional inputs only. The isolated entrypoint `lib/evaluation/resource_measurement_main.dart` (launch argument `--sekret-model-rating-eval`) never opens the personal database or changes the saved model. Whole-device per-process memory came from Instruments Activity Monitor recordings over the wireless connection. Each recording captured about 1.4 s before the link ended it, so samples arrive roughly every nine seconds. Sekret also sampled its own physical footprint and thermal state every two seconds. Raw reports, samples and the analysis scripts are in [resource-measurement/](resource-measurement/).

## Memory: measured, not scored

Metric from [scale-v1](model-ratings/scale-v1.md): peak physical footprint of Sekret plus Apple's model-serving processes (`TGOnDeviceInferenceProviderService`, `GenerativeExperiencesSafetyInferenceProvider`, `generativeexperiencesd`, `modelmanagerd`), minus the median over a matched two-minute idle window. The same 30 frozen General tasks were used, with ten-second rests.

| Model | Idle (median) | Workload peak | Added | Run |
|---|---:|---:|---:|---|
| Apple Intelligence | 553 MB | 837 MB | **0.28 GB** | 30/30 completed; plugged in; nominal → fair; 29 trace samples |
| Qwen3-4B Q3_K_M | 175 MB | 578 MB | **0.40 GB** (self-sampled 0.43) | 30/30 completed; unplugged; median 3.28 s; nominal/fair, no cooling pauses; 28 trace samples |

At Apple's peak, `TGOnDeviceInferenceProviderService` accounted for 628 MB, against 442 MB at idle. During Qwen's run the Apple services stayed at 21–30 MB.

**Why there is no score.** Both models memory-map their weights. Physical footprint excludes those file-backed pages: Qwen's weights are its 2.08 GB file. A check of Activity Monitor's "Real Mem" column showed lower values than footprint, so it does not capture the mapped weights either. Only whole-device counters see them ("cached files", 2.39 GiB at idle), and those mix in other apps and earlier caching. Apple's weights are managed and shared by iOS, and their size is not observable. A single memory score would therefore count Qwen's weights but not Apple's, or neither. The owner chose to show the measured working-memory figures and the weights caveat in Models, with the Memory bar marked "Not scored". A metric amendment drafted on the same day was withdrawn before any data was collected under it, once this check showed it would not work.

## Photo device acceptance (Apple Intelligence, iOS 27)

Fixtures were Tuck brand artwork, which is fictional: a 4032×3024 JPEG; a HEIC stored rotated with EXIF orientation 6, which looks upright only if orientation is applied; and a 512 px PNG.

| Check | Result |
|---|---|
| Repeated runs (3 fixtures × 3 rounds) | 9/9 completed and correct ("A turtle.", "Upright", "The turtle is teal."); thermal fair throughout |
| Latency including preprocessing | 1.39–2.22 s; first, cold request 4.94 s |
| HEIC orientation | Applied correctly in all four HEIC answers |
| Cancel during preparation | Clean; the next request succeeded |
| Cancel during generation | Clean after the first snapshot; the next request succeeded |
| Background interruption mid-answer | The in-flight answer ended with `interrupted`, with no crash ([run 3](resource-measurement/run3-interruption-2026-10-09.json)) |
| Recovery | The next photo answer completed ("Upright"). Note that it ran during the backgrounding, so return-to-app is covered by the existing `chat_app_test` lifecycle test rather than this harness |
| Memory | +0.71 GB peak above idle (Sekret plus services), mostly in `TGOnDeviceInferenceProviderService` |
| Airplane mode | Not run: it would cut the wireless measurement link. Owner spot-check pending |

In run 2 the interruption-phase answer finished before the interruption arrived, so run 3 kept answers in flight until it landed.

## Retained failures and conditions

- **Run 1** stopped at Qwen's fifth task with `Cooling pause timeout`. The phone was charging throughout, and it reached serious thermal state at 02:21 UTC and did not recover within 20 minutes. Its Apple phase is complete and supplies the Apple figures. The Mac's disk then filled during trace collection. Later collection reduced each trace to one sample line and deleted the raw trace, with a 5 GB free-space guard.
- **Run 2** waited 19 minutes, unplugged, to reach a nominal start before Qwen.
- Apple and Qwen were measured in different sessions, Apple plugged in and Qwen unplugged. The memory protocol does not require battery power, but the conditions are recorded.

## Battery

Not measured. The predefined protocol needs three paired 30-minute idle/workload runs per model, unplugged, about 6 hours. It is to be scheduled with the owner.

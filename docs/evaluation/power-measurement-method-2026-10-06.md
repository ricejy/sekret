# Physical-iPhone power measurement

Research checked 2026-10-06. Method guidance only: no new power measurements or catalogue approval. Applies to the isolated Sekret Local Eval harness, not the shipping app.

## What Apple measures

- Power Profiler supports iOS 26+. Select the actual app: **All Processes** records system metrics without app-specific impact. System power is battery-energy fraction per hour; app tracks cover CPU, GPU, display and networking impact. [Apple documentation](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler)
- While charging through cable **or MagSafe**, system power usage reports **zero**. That is unavailable discharge measurement, not zero consumption. Use wireless profiling on battery for this metric. [Apple documentation](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler)
- Xcode pairing keeps Apple silicon awake. For meaningful sleep/idle observation, collect an on-device trace without the Xcode connection, then transfer it afterward. [Apple documentation](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler)
- CPU/GPU power-impact values are comparative scores, not joules or watts. Compare traces on the **same device model**; do not convert a score into energy. [Apple documentation](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler), [WWDC25 session 226](https://developer.apple.com/videos/play/wwdc2025/226/)
- Apple recommends repeated comparisons because thermal state, system pressure and app/device state influence results. Its on-device Time Profiler samples less frequently to reduce observation overhead. [WWDC25 session 226](https://developer.apple.com/videos/play/wwdc2025/226/)

## Proposed Sekret protocol

These are experiment-design recommendations, **not Apple-defined qualification thresholds**:

1. Preserve exact app/model/runtime pins and fixed fictional inputs. Record phone/OS, battery level and charging state, brightness, Low Power Mode, initial thermals, context/output budgets and connection mode. Start nominal; retain existing thermal/memory stops unchanged.
2. First validate capture/export using the app target. A plugged-in diagnostic can establish whether app tracks are present, but cannot establish battery drain. Do not silently treat missing/zero system measurements as a pass.
3. On battery, record a same-duration foreground baseline with the harness open but no inference, then the fixed paced workload. Keep screen/settings/connection conditions matched. Include hashing/loading through cleanup; distinguish those phases from token generation when timestamps permit. Save output-token counts and completed/cancelled outcomes.
4. Aim for at least three baseline/workload pairs, allowing cooldown between pairs and alternating order where practical. Report individual runs plus range/average; label incomplete or thermally stopped runs, rather than dropping them. This minimum is a practical screening choice, not statistical proof.
5. Compare app impact alongside **whole-device** discharge rate, duration and thermal timeline. A baseline difference is an estimate affected by other device activity, not exact per-app energy attribution. Do not compare different transport modes as equivalent baselines.
6. For unplugged real-use/idle confirmation, use Settings → Developer → Performance Trace → Power Profiler, select Sekret Local Eval, record through Control Center, and transfer the trace afterward. This workflow is supported by [Apple documentation](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler); whether the installed toolchain exports the required lanes must be checked locally.

## Reporting limits

A brief unchanged battery percentage does not establish negligible drain. Do not turn a short workload's battery-fraction/hour rate into promised battery life or “answers per charge”: that would assume a representative continuous workload, stable conditions and reliable app attribution that this experiment does not establish. Report bounded observed rates/scores and durations instead. This is our inference from the metrics and repeatability limitations above, not an Apple battery-life guarantee.

The earlier sustained-use thermal failure remains evidence even if paced power traces look acceptable. A power screen cannot replace answer-quality, lifecycle, resource or privacy qualification.

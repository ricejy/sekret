# Isolated Qwen 0.6B Q4 phone evaluation

## Repeated-run diagnosis update

See `../MEMORY-LIFECYCLE-2026-10-06.json` for the later controlled diagnosis.
Build 5 releases hash-read Foundation temporaries per chunk and uses a 2 GiB
pre-load headroom policy specific to this compact artifact. OS memory-warning
cancellation is unchanged. The original seven-probe replay and 20 identical
2K probes both pass without restarts. This supersedes the earlier repeated-run
block below, not the recorded quality limitations or historical raw results.

Regression commands: `python3 experiments/qwen06_q4/diagnose_phone.py` and the
same command with `--count 20`, from the repository root with the phone connected.
The collector uses structured device inventories and copies only the new run;
the earlier full-history copy approach timed out as reports accumulated.

Real XCUITest Stop/background/recovery tests compile and sign but could not run:
installation of the separate `.uitests.xctrunner` hit the phone's free-profile
three-app limit. No existing app was removed. `../manual_lifecycle.sh` is the
user-observed fallback. The user subsequently reported both cases passed;
exported native receipts corroborate four actual Stop cancellations, one
foreground-loss cancellation and two subsequent completed 407-token runs.
Cancellation request to worker return was approximately 29–39 ms, including
cleanup/export, not a guarantee of in-flight GPU-abort latency. All seven manual
reports recorded thermal state fair; sustained thermals remain unqualified.

Temporary phase instrumentation and diagnostic reserve/settle switches were
removed from executable source. Evidence remains in ignored results. The fixed
`--memory-replay-count=1...20` fixture is retained for regression testing.

**Result:** six completed short answers and one expected eight-token
cancellation, with no recorded iOS memory warning. The original batch stopped
at its pre-load headroom guard after two answers; the remaining five probes
ran in fresh processes. This does not qualify continuous repeated-run behavior
or answer quality. See `../PHONE-RESULTS-2026-10-06.json` for timings, resources,
quality misses and limitations. Both signed builds succeeded and five native
tests passed. The phone app is now idle with automatic probes disabled.

This target updates only `com.ricejy.sekret.localeval` (initial build 3, fixed-probe
selection added in build 4). Shipping Runner
and personal Sekret data are untouched. The harness is a snapshot of the prior
Qwen4 Q3 phone harness, with model identity, isolated storage/report paths and
UI labels changed. It imports this experiment's own QwenRuntime, preserving
the Qwen0.6 non-thinking suffix rather than using the Qwen4 template.

The exact local artifact is `Qwen3-0.6B-Q4_K_M.gguf`, 396,705,472 bytes,
SHA-256 `ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a`.
No new download is needed. App storage is protected and backup-excluded under
`Library/Application Support/SekretQwen06Q4Evaluation/`. Each run verifies the
whole artifact before native loading. There is no app network code, extra
memory entitlement or background execution mode.

`--evaluation-suite` runs the same seven fixed fictional probes as the Qwen4
Q3 phone attempt: two 2K, two 4K, conditional notice, Unicode and cancellation
injected at eight output tokens. Output cap is 128; the runtime sampling and
Mac comparison system prompt remain unchanged. Inputs are short, so this is
not a near-full-context or sustained-output qualification.

Before each load the app requires 3 GiB of reported iOS app memory headroom,
the same conservative threshold used for Qwen4 Q3. Stop, foreground loss and
memory warnings request cooperative cancellation. The UI stays busy until
native cleanup returns. A token-injected cancellation is not actual UI Stop,
in-flight GPU abort or background-recovery evidence.

The initial batch completed two 2K probes, then the 3 GiB pre-load guard blocked
the first 4K probe at 3,188,619,112 reported bytes. This was an admission refusal,
not an iOS memory warning. A fixed `--probe=<known-plan-name>` selector permits
remaining probes to run in fresh processes without lowering the guard or
replacing the original evidence. Fresh-process results do not qualify repeated
in-process resource behavior. Unknown identifiers are rejected; no arbitrary
prompts or URLs are accepted.

Reports use unique `Documents/Qwen06Q4Reports/<UUID>/` directories and include
before-load markers. `recordedProbes` means a terminal result exists, not that
an answer completed. Lifecycle receipts and readiness snapshots use the
`q06q4-` prefix. Old Qwen4/Qwen0.6 Q8 documents and model paths are preserved.
Before update, Documents were exported to ignored `../results/phone-prior-documents/`.

Build output `ios/build/` and raw `../results/` are ignored. The shared pinned
llama.cpp b11429 XCFramework has iOS device arm64 but no simulator slice.

# Isolated Qwen 4B Q3 physical-phone evaluation

## Matched-duration comparison: build 13 completed

See `../MATCHED-POWER-PLAN-2026-10-07.json`. The isolated harness adds
`--long-chat --power-profile --power-matched=baseline-first` (or
`workload-first`). Each pair contains exactly one 300-second foreground idle
baseline and one 300-second eight-turn workload window. The existing eight
answers, actual history, hash/load/unload and reading pauses are unchanged;
remaining workload time is idle padding. A workload exceeding 300 seconds
requests cooperative cancellation and invalidates the pair. Deadline-based
pauses avoid accumulated one-second sleep drift.

Three attempts are prespecified baseline-first, workload-first, baseline-first,
with at least two minutes and nominal thermals between pairs. The capture-ready
handshake and all existing safety guards remain. Fresh user/device readiness
is required; this is not permission to assume the phone remained available.
The collector uses the same 15-second polling cadence in both phases.

`inspect_power_trace.py` retains compatibility with earlier pilots and detects
the new explicit plan/phase markers. `inspect_matched_power.py` audits fixed
durations, complete capture, order, stable brightness, native power conditions,
thermal/clock evidence and distinct run IDs. It does not average incomplete
pairs or reinterpret missing samples as zero. Native chat/content/lifecycle
audits remain separate. Earlier partial captures and sustained thermal failure
remain retained.

All three prespecified pairs completed with full power/thermal coverage,
normal thermal state throughout, unchanged full brightness and no lifecycle
stop. Native history/token/pin audits passed; all 24 responses to the repeated
eight-turn fixture are correct and identical across runs (not 24 distinct
quality cases). Median native generation was 4.95 seconds, excluding hash/load,
export and UI. Twelve native and nine Python tests pass; signed Release build
succeeds. Forced deadline/charging/low-battery edge cases were not newly induced.

| Pair | Order | Idle whole-device %/hr | Paced workload whole-device %/hr |
| --- | --- | ---: | ---: |
| 1 | Idle then chat | 4.6 | 13.8 |
| 2 | Chat then idle | 4.2 | 13.7 |
| 3 | Idle then chat | 4.1 | 13.8 |

Mean within-pair difference was 9.47 percentage points/hour (range 9.24–9.71).
These are rounded, time-weighted profiler rates under wireless instrumentation,
not exact app energy or promised battery life. Native coarse battery readings
changed approximately 90% →85% →80% across the session including setup/cooldown;
they are retained separately, not reconciled into a calibrated app-only drain
figure. Full hash/load/unload per turn, short inputs (75–643 tokens), reading
pauses and idle padding differ from future optimized production use. Keep
public battery-efficiency labels unmeasured until separately qualified.

The final pair's initial Instruments identity lookups failed. Selecting the
independently verified device name with the same PID confirmed recording within
the original 300-second gate (277.63-second wait), then the normal settling and
eligibility checks released measurement. No workload was restarted/discarded;
all attachment diagnostics are retained. This workaround does not establish
the Instruments root cause. No profiler process or phone collection remains.
See `../MATCHED-POWER-RESULTS-2026-10-07.json` and the ignored evidence paths it
references. Disconnected idle/sleep and integrated-app battery behavior remain
separate from this completed bounded comparison.

## Capture readiness correction: build 12

See `../POWER-CAPTURE-GATE-PLAN.json`. The build 11 trace reproduced missing
initial baseline coverage (52.95%); trace start was later than baseline start,
not a native clock jump. Build 12 replaces the 45-second automatic release with
a run-specific confirmation file. The operator must first observe Instruments
recording the verified app PID, then copy `capture-ready.json` containing
`{"runID":"<new report directory UUID>","captureReady":true}` to that run's
report directory. Process existence alone is not capture confirmation.

Without valid confirmation, no baseline/inference starts, and the wait expires
after 300 seconds. Stale, malformed and false confirmations do not release it.
After confirmation, a 10-second settling period and eligibility recheck precede
the unchanged 90-second baseline. Stop, foreground, thermal and power guards
remain active. The gate is evaluation-only; no app networking was added.

The signed build and 10 native tests pass, including the two gate tests; four
power-analysis tests also pass. On the phone, an inventory taken more than
45 seconds after starting showed only the attach-wait marker. Instruments
confirmed recording before the matching receipt was sent. The completed audit
confirms full coverage of both baselines and the workload, an 83.43-second wait
and 10.42-second settling interval. All eight answers exactly match the prior
correct responses; median generation was 5.00 seconds and median turn-wall time
6.87 seconds. All native/trace thermals were nominal; no lifecycle stop occurred.

See `../POWER-CAPTURE-GATE-RESULTS-2026-10-07.json`. Whole-device diagnostic
rates were 4.5%/hr before, 15.7%/hr during the paced workload and 6.1%/hr afterward
at full brightness under wireless instrumentation. The coarse native battery
gauge moved from 95% to 90%; this is not a calibrated app-only drain figure and
must not be equated with the profiler's integrated rates. Earlier incomplete
results remain preserved below. Neither run is the planned repeated, matched-
duration battery qualification, and no user-facing battery rating is justified.

## Power pilot: build 11

`../POWER-PILOT-RESULTS-2026-10-06.json` records one unplugged pilot. All eight
chat answers were correct, real history/token parity passed, and all native
thermal samples and the full captured thermal timeline were nominal. Median
generation was 5.01 seconds; median turn wall time including hash/load/export
was 6.86 seconds (neither is a measured tap-to-render latency). No lifecycle
stop occurred. Earlier sustained-load thermal failure remains unchanged.

Power qualification is **incomplete**: wireless profiler attachment succeeded
late, capturing 49.44 of 93.37 seconds of the initial baseline (52.95%). The full
272.74-second workload and 93.21-second post-baseline were captured. Diagnostic
whole-device rates were approximately 5.4%/hr over the partial baseline,
16.7%/hr during the paced workload and 6.0%/hr afterward, at full brightness
under wireless instrumentation. These are not app-only drain or battery-life
predictions, and must not become a user-facing battery rating. Native markers
show unplugged/LPM-off throughout; charging export has no rows. The battery
gauge remained at 100%, which does not mean zero consumption.

`../inspect_power_trace.py` resolves global XML references, clips intervals to
native phase timestamps and reports incomplete coverage explicitly. Four
analysis tests pass. Rounded, explicitly labelled %/hr values are used; app
impact columns lacking labels are not guessed. The trace/report evidence is
preserved. A future repeated comparison needs profiler readiness confirmed
before the baseline starts. No automatic repeat or new weights were requested.

`../POWER-PILOT-PLAN.json` records the exploratory unplugged protocol. A short
USB idle trace established that app-targeted Power Profiler recording and table
export work when attaching by PID. App-name attachment failed. The charging
system-power zero is not a consumption result. See the cited method note at
`../../../docs/evaluation/power-measurement-method-2026-10-06.md`.

Build 11 adds `--long-chat --power-profile`: a 45-second profiler attachment
allowance, 90-second foreground baseline, the unchanged eight-turn workload,
and a 90-second post-workload baseline. `power-*` JSON markers record wall-clock
and uptime, charging/battery/brightness/Low Power Mode/thermal state. Start
requires unplugged battery >=30%, nominal thermal state and Low Power Mode off.
Existing resource guards remain; charging, low battery and Low Power Mode add
cooperative stop paths. Auto-lock is temporarily disabled for this foreground
pilot and restored on finish. No shipping app or system settings are changed.

The signed build and eight native runtime tests pass. Those tests do not cover
the new UIKit battery notifications. Charging-refusal remains uncorroborated.
Do not infer battery life or app watts from the setup trace. Raw Swift-backed
XML tables sometimes omit column labels; unlabelled app-impact columns must
not be guessed. Wireless transport needs verification after the cable is removed.

## Latest: build 10 context boundaries and eight-turn chat

See `../CONTEXT-CHAT-RESULTS-2026-10-06.json` and its frozen plan. Both boundary
probes answered correctly: 1,884 input tokens at 2K and 3,938 at 4K, reserving
128 output tokens. The shared native runtime also rejected just-over-limit
inputs before generation on the Mac; nothing was silently truncated. The 4K
probe took approximately 30 seconds to first token, excluding hash/load/UI.

All eight paced chat turns completed with correct updates, including all nine
final facts and 24 expected packets. Actual generated history and publisher
token hashes were checked. All eight start/return thermal readings were fair,
with no memory-warning or thermal stop. Median native generation was 5.02 seconds,
excluding hash/load/export/UI and the fixed 30-second pauses. The final history
was 643 input tokens; do not describe this as near-full eight-turn history.
Eight native runtime tests pass. The fixture's eight-turn bound is not a claimed
model limit or a shipping chat policy.

Use `../retest_phone.py --context-boundary` or `--long-chat` only after checking
device readiness. Audit with `../inspect_paced_chat.py <reports> --mode boundary`
or `--mode long-chat`. These finite development passes do not erase the earlier
back-to-back thermal failure. USB-connected runs are not battery-drain evidence;
the later build 11 section above records the separate power pilot and its
limitations. No new model downloads or shipping changes occurred.

## Build 9 paced chat and refusal diagnosis

`../REFUSAL-DIAGNOSIS-2026-10-06.json` records a word-for-word Mac reproduction
of the phone refusal. Removing only “continuing until the output limit” produces
a story; removing only the test disclaimer does not. The manual fixture now
requests a bounded 180-word story. This is a harness correction, not a general
model fix. Original failed prompts/results remain preserved. A separate email
probe invented an unsupplied calendar date, showing that non-refusal is not
enough for answer quality.

`../PACED-CHAT-RESULTS-2026-10-06.json` records six completed phone probes with
30-second reading pauses, nominal/fair thermal readings and no recorded thermal
or memory-warning stop. Four turns use real generated assistant history; a
bounded story and a 1,618-token fictional brief use independent chats. Exact
prompt/token hashes match the retained publisher tokenizer and an independently
written, manually audited template subset. Seven native unit tests pass.

The model retained updated event details and extracted the correct brief facts.
It failed the three-item checklist format (five fields plus an unsupported Today
label) and produced 199 whitespace-delimited words for the 180-word story.
The story took 19.63 seconds of generation; the brief took 12.66 seconds including
prefill. These exclude hash/load/UI overhead and are not end-to-end latency.
The differently paced pass does not override the failed stress workload below.
No shipping app changes or model downloads were made for this stage.

Run `../retest_phone.py --paced-chat` only after checking device readiness.
`../inspect_paced_chat.py <reports-directory>` audits captured history and tokens;
manual content grading and lifecycle/resource inspection are separate gates.

## Current reserve/thermal status

See `../RESERVE-LIFECYCLE-2026-10-06.json`. A 2.5 GiB candidate reserve allowed
20 consecutive fixed answers alternating short-input 2K/4K contexts. Memory
remained bounded (same-context cleanup range under 11 MB after warm-up), but
**every result recorded serious thermal state**, failing the separate screening
plan. The CLI's terminal-outcome pass does not override that thermal failure.

After cooldown, build 8 passed the original seven-probe suite in one process:
six completed answers and the expected eight-token cancellation, with terminal
thermal states nominal/fair and no recorded memory-warning stop. Peak sampled
footprint was 1,019,531,312 bytes; process-lifetime peak RSS was 3,114,647,552 bytes.
These are different measures, not a total model RAM requirement.

The subsequent fresh-process 20-probe mixed-context run started at fair thermal
state, completed five answers, then cancelled answer six at 15 tokens when the
phone reached serious thermal pressure. Its lifecycle receipt explicitly records
`Device thermal pressure`, returning in approximately 112 ms after the request.
The process remained in the foreground and exported reports. This demonstrates
one real thermal-cancellation path, **not a sustained-load pass**. Fourteen probes
were not attempted. This was not an independent cold baseline or proof of
model-only heat causation. Raw evidence and the earlier failed run are retained
in `../RESERVE-LIFECYCLE-2026-10-06.json`.

Build 8 refuses new work at serious/critical thermal state. After cooldown to
nominal, the user reported both manual checks passed. Exported native receipts
confirm Stop cancellation (64 ms) and foreground-loss cancellation (111 ms),
both at nominal thermal state. A subsequent retry completed at 14:06:02Z,
after both cancellations, with 49 output tokens and fair thermal state. This
confirms recovery mechanics. However, the response refused the fictional story
and cited an output limit: native completion is **not** an instruction-following
or long-output quality pass. Generation took 3.90 seconds, excluding hash/load
and other UI overhead. No further manual lifecycle clicking is required here.
See `../results/manual-lifecycle-20261006` and the summary above. The signed build
and five runtime tests pass; those tests do not cover SwiftUI notification
delivery. Near-full context and sustained multi-turn/energy qualification also
remain pending. The candidate reserve is not a release-approved policy.

Temporary resource snapshots and the diagnostic reserve switch were removed;
raw measurements remain preserved. `../retest_phone.py --count 20 --mixed-contexts`
retains the finite repeated-load fixture. `../manual_lifecycle.sh` recorded
the user's observations separately from native evidence, since the separate UI runner
was previously blocked by the free-profile app limit. No existing app was removed.

**Earlier build 7 result:** with per-chunk hash-buffer cleanup, six answers and one
expected eight-token cancellation were recorded, with no OS memory-warning
stop. The first batch completed two 2K probes, then its unchanged 3 GiB admission
guard blocked the next load. The five remaining fixed probes ran in fresh
processes. This is not a seven-probe one-process pass or release qualification.
See `../PHONE-RETEST-2026-10-06.json`. Both 2K/4K short-input probes produced
answers; real Stop/background testing was still pending at that earlier stage.

**Historical pre-fix result:** the first 2K probe received a real iOS memory warning and
cooperatively cancelled before producing a token. The process survived; no
remaining probes were forced through. See `../PHONE-RESULTS-2026-10-06.json`.
This model was not phone-qualified. At that stage the app was reopened idle
without automatic generation; actual UI Stop/background tests were unperformed.

This is a new harness source snapshot using `../QwenRuntime`, not a change to
shipping Runner or the old Qwen0.6 Q8 baseline. It deliberately updates the
existing separate evaluation bundle `com.ricejy.sekret.localeval` (build 2) to
avoid consuming another personal-team app slot. Prior Documents were exported
and compared byte-for-byte before installation. Existing app data is preserved.

The exact 2,075,618,400-byte Q3 artifact and SHA-256 remain pinned by QwenRuntime.
It is stored in `Library/Application Support/SekretQwen4Q3Evaluation/`, separate
from the previous model. There is no app network/download code, no access to
Sekret data, no extra memory entitlement and no background mode.

The initial `--evaluation-suite` runs seven fixed fictional probes: two 2K, two
4K, conditional notice, Unicode and injected eight-token cancellation. Each uses
128 output tokens and the same system prompt as the Mac Q3 comparison. These
are short-input smoke probes, not near-full-context or sustained-load tests.
Each run verifies the entire file hash. The admission guard requires 3 GiB of
reported iOS app memory headroom before load; it does not guarantee safe peak
usage or prevent jetsam. The unchanged runtime reports sampled footprint and
process-lifetime peak RSS, which are different measurements.

Reports use unique `Documents/Qwen4Q3Reports/<UUID>/` directories. Before-load
markers distinguish an attempted probe from a completed result. Manual runs
and lifecycle receipts are also exported to Documents. Stop/background/memory
warning cancellation is cooperative; an injected token-count cancellation is
not evidence that a real UI Stop, in-flight Metal abort or background recovery
works. Actual UI checks remain separately required.

The 2026-10-06 signed build succeeded with target-only command-line signing
overrides, and five native runtime tests passed. A first Mac test compile caught
the iOS-only availability of `os_proc_available_memory`; it is now platform-gated
and returns unknown (0) on macOS, where this phone admission guard is not used.
The original generation algorithm, sampling, pins and template are unchanged.

Retest builds 6/7 preserve those parameters and the original memory reserve,
but drain Foundation's temporary hash-read data after each 1 MiB chunk rather
than retaining a model-sized set until loading ends. Five runtime tests pass.
Build 7 adds only a known-plan `--probe=<name>` selector to finish pending probes
from fresh launches. `../retest_phone.py` asserts outcomes and preserves each
new run under ignored results. It accepts only the seven fixed probe names.

Native XCFramework: llama.cpp b11429; device arm64 only, no simulator slice.
Build products under `ios/build/` and raw results under `../results/` are ignored.

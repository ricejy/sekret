# Current status — 2026-10-07

## Accepted baseline

PR #49 integrated the accepted v2 stack and Sekret identity into main at `1eb4084dc2182009bfb14132a5a4804244257a87`. GitHub main and the canonical checkout were verified at that commit on 2026-10-07; no open issues remained at that check.

The app includes dark styling, Tuck branding, three-step onboarding, local chats/history, Knowledge Base indexing/previews, Models and Settings. The paperclip imports or selects knowledge items and displays removable selected-source chips. No cross-chat memory, account or hosted backend is required.

Apple Intelligence is first. Qwen3-4B-Instruct-2507 Q3_K_M is the accepted first downloadable General-text preview, restricted to the tested device profile. Download/install/cancel/removal, native inference and explicit switching were manually accepted. Knowledge Base generation and image understanding are not approved for Qwen. ADR 0005 narrowly supersedes ADR 0001 for explicit reviewed artifact downloads.

The Apple response-format fix uses shared Dart/Swift `general-v4` instructions: plain text unless the current message explicitly requests JSON. It does not strip arbitrary JSON. Device reproduction, greeting/history checks, explicit JSON control and owner acceptance were reported in the preceding task.

Prior rename validation: 267 Flutter tests passed, analyzer clean, signed release build succeeded. These are historical results, not checks run by documentation reconciliation.

## Identity migration

The one-owner backup/restore to `com.ricejy.sekret` and `sekret.sqlite3` completed with owner-visible acceptance. The old installation and finished benchmark app were removed after explicit authorization; private backups remain preserved. This was not an automatic migration for general users. The private migration receipt was reconciled on 2026-10-07 against the handoff and retained uninstall/post-retirement inventory receipts. No migration operations were repeated for that receipt correction.

The tracked source rename is complete. Historical Git objects, old metadata and private backups may retain former names. The [history rewrite](history-rewrite-plan.md) remains planned only; scope, freeze, backup, dry run, leases and explicit cutover approval remain required.

## Completed battery experiment

[Three matched pairs](../../experiments/qwen4_q3/MATCHED-POWER-RESULTS-2026-10-07.json) measured 300-second idle and paced eight-turn phases. Whole-device profiler averages were 4.32%/hour idle and 13.79%/hour workload (9.47 percentage points/hour difference); all 24 answers were correct, median native generation was 4.95 seconds, thermals nominal, with no interruption.

These are one-phone measurements at full brightness under wireless profiling, not precise app-only drain or battery-life estimates. The coarse battery gauge was not reconciled. Earlier sustained-load thermal-stop evidence remains relevant. Public battery efficiency remains unmeasured; the experiment is finished and needs no resumption.

## Remaining product work

- The [matched development comparison](../evaluation/model-ratings/results-2026-10-07.md) now supplies preliminary General quality/speed ratings. Broader quality, comparable system-service memory and calibrated battery ratings remain unqualified.
- Ordinary-photo understanding needs separate scope, runtime/toolchain eligibility and quality/device acceptance. Current production imports use OCR; image-capable models have not been integrated.
- Broader device support and a general release require their own qualification.

The README and this status record describe the accepted baseline. Dated integration notes and research documents preserve their original stages; their pending-work statements must not override later code, ADRs or acceptance evidence.

## Follow-up changes in this worktree

The [Models/background-download update](models-download-update.md) replaces lock-triggered cancellation and verbose model cards. The searchable list includes a shared rating scale, preliminary measured quality/speed bars, and explicit switching/removal confirmation for selected Qwen. On 2026-10-07 the owner reported that the physical download-through-auto-lock test and Qwen removal both succeeded. These are owner-reported device acceptance results, separate from automated coverage. [Photo understanding](photo-understanding-scope.md) remains a proposal only, and the owner has explicitly paused further work on it.

Production-v2 build 10 with these rating/removal changes was installed and launched on the owner's phone. The full 60-response unplugged comparison completed, 35 affected tests passed, and analysis was clean. Database bytes and app-support file metadata were preserved across installation. The accepted update is being committed and published for review. Comparable memory and battery measurements remain pending; an 11 pm Singapore-time reminder on 2026-10-07 is scheduled to prepare the overnight run, not to start it automatically. The owner requested historical-name cleanup before photo-understanding work resumes.

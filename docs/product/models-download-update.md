# Models and background downloads — 2026-10-07

## Behavior

Models is a searchable compact list, Apple Intelligence first. A left-hand tick marks selection. Each row shows four five-segment rating tracks: answer quality, speed, memory use and battery efficiency. Quality and speed now show preliminary ratings from a complete matched 30-task phone comparison. Memory and battery remain “Not measured”; download size is separate. Missing scores do not discard prior evidence. Qwen model info reports the 25/30 Mac development tasks, repeated eight-turn phone results, 4.95-second median native generation, both memory measures, and the completed whole-device battery experiment with its limitations. Apple info explains the different scope of its earlier tests. Text-only capability, an info action for details/license/provenance, and a trash action for removable weights replace long inline explanations. The current follow-up enables the trash action for selected Qwen. Its confirmation explicitly says “Switch & remove”; cancellation preserves selection and files, and a failed switch prevents removal. Apple-not-ready warnings explain that chat will be unavailable after removal.

Apple readiness displays Checking while a query is pending and a disabled Ready control when available. Availability refreshes on app resume; unavailable/error states retain a retry action. Returning from iOS Settings therefore refreshes readiness without a no-op button.

## Download fix

The app previously called model cancellation on backgrounding and on app lock. Both calls were removed; private generation/indexing still suspend and the privacy overlay remains. Model transfer now uses an iOS background URLSession, rather than relying on a Dart stream running while the app is suspended. Explicit Cancel and Erase All still cancel native work and wait before staging cleanup.

A fixed background-session identifier and pinned task identity allow recovery after process recreation. Startup checks for pending native work or a completed unverified staging file without holding the app open screen behind the full transfer. The downloaded file moves into the existing fixed staging path; Dart verifies the persisted byte count and SHA-256 before atomic publication. No second model-sized copy is introduced.

Public model files use protection until first user authentication so the system can finish writing while locked. Private chats, Knowledge Base and database retain their existing complete protection. Model files remain excluded from backup. Network requests contain only the reviewed artifact choice and ordinary request metadata, never prompts or private data.

[Apple's background-transfer documentation](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background) describes system-owned downloads while the app is suspended. Scheduling remains controlled by iOS; forced app termination, connectivity loss and OS deferral are not a promise of uninterrupted progress. Verification may finish after returning to Sekret.

Background URLSession follows redirects automatically rather than invoking the foreground redirect callback, as documented by [Apple](https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:)). The native adapter pins the initial URL/size/hash/destination, disables cookie/credential storage, restricts server-trust challenges to reviewed HTTPS hosts, relies on default ATS, and rejects final responses outside the same host policy. Exact artifact verification remains mandatory. It does not claim the foreground transport's five-hop redirect control.

## Validation and owner click-through

Automated coverage includes lifecycle behavior with app lock both on and off, readiness feedback/retry, search, large text, transfer recovery, Cancel racing Start, corrupt files and existing install/removal safeguards. The full 278-test Flutter suite passed, followed by the added selection/reactivation regression passing separately. Flutter analysis is clean; the new Swift downloader passes iOS-target type-checking and the Xcode project passes plist validation. The rendered compact layout was inspected. No phone run is implied by these checks. After the owner authorized cleanup and installation, a signed production-v2 release (0.1.0, build 2, `SEKRET_V2=true`) built successfully and was installed in place and launched. The database was byte-identical across installation before first launch; app-support file sizes/modification times, including the installed model, were preserved. Physical auto-lock transfer acceptance remains pending because no fresh model download was started.

For installed build 2:

1. Models: search Apple/Qwen, clear search, inspect four unrated tracks, selection tick, text-only indication and info notices. Enable larger text and check scrolling.
2. Apple: Ready is disabled. If unavailable, check readiness; after changing iOS settings, return and verify the state refreshes. Select a model via its left circle.
3. On a test installation without the model, consent to a download, note progress, and let the phone auto-lock for several minutes. Unlock: progress should have advanced or completed, and no automatic cancellation should appear. Repeat with Sekret app lock enabled. OS scheduling may defer work, so capture any displayed error.
4. Explicitly cancel a partial download and retry; verify cleanup and eventual installation. Do not remove the owner's existing active model merely to perform this test without agreeing that step.
5. With Qwen selected, verify its trash control is disabled. Switch explicitly to Apple before testing removal. Chats and Knowledge Base must remain intact.

This guide is a pending device acceptance step, not a record of a completed physical lock test. The owner-authorized in-place install and launch completed; no phone model removal or new model download was performed.

## Chat wording follow-up

The composer no longer displays “Model knowledge · no sources selected” or the long “Choose sources or remove unavailable ones” instruction. Attached source chips and their status labels remain, along with “Answers only from selected sources” when items are attached. The explicit recovery action remains available after source deletion; sending still requires eligible indexed sources, without silently falling back to General mode.

Evidence pointers: [Qwen development grades](../../experiments/qwen4_q3/BROADER-GRADES-2026-10-06.json), [phone workload and battery results](../../experiments/qwen4_q3/MATCHED-POWER-RESULTS-2026-10-07.json), and [Apple evaluation ledger](../evaluation/v2-release-gate-2026-09-12.md). These preserved records were not rerun for UI wording changes.

Build 3 follow-up: 26 affected UI tests passed and analysis was clean. Signed production-v2 build 3 was installed in place and launched. Database bytes and app-support file sizes/modification times were unchanged across installation. Photo-understanding work remains on hold.


## Shared scale and removal follow-up

The [v1 scoring scale](../evaluation/model-ratings/scale-v1.md) defines fixed 1–5 bands with higher always better, including memory efficiency. Models exposes the scale explanation. Missing measurements read “Not measured”; historical mixed-workload results are not comparable ratings. The isolated `lib/evaluation/model_rating_main.dart` entrypoint collects the same 30 fictional General tasks from both production adapters without opening the personal database or modifying model selection. Its explicit `--sekret-model-rating-eval` launch argument prevents auto-lock during collection; ordinary launches retain normal auto-lock. This argument does not start the diagnostic in the production entrypoint.

The selected-Qwen trash regression first failed against the disabled button. It now passes cancellation, failed persistence, and confirmed switching/removal. The 32 affected tests passed before the additional failed-persistence case, which then passed separately. Store lease protections remain. A confirmation warns when Apple is not ready; a failed persisted switch must leave Qwen installed and selected. The earlier build-2 disabled-trash click-through above is historical and is superseded by this confirmation flow.

At the initial install attempt, the iPhone disconnected before backup, so the follow-up was not installed then. The owner later reconnected it and authorized the matched comparison. After retaining failed thermal controls, a cooled unplugged run completed all 60 responses. See the [results and limitations](../evaluation/model-ratings/results-2026-10-07.md): Apple quality 1/5 (17/30), speed 5/5 (1.7885 s); Qwen quality 3/5 (25/30), speed 4/5 (3.527 s). Strict output formatting counts toward full-task quality. Memory and battery still lack comparable measurements. Photo understanding remains on hold.

Signed production-v2 build 5 compiled successfully and passed signature verification; its binary contains the new removal action. At that stage it had not been installed because the phone was disconnected. It was later superseded by installed build 10 below. Final analysis is clean; source changes remain uncommitted. Rebuild the diagnostic entrypoint before its next run to include the final provenance metadata, then restore the production entrypoint for the user-facing installation.


## Installed rating/removal update

Signed production-v2 build 10 was installed in place and launched after the completed unplugged comparison. All 35 affected tests passed serially and analysis was clean. The first parallel validation hit the existing 15-second download-test deadline and exposed merged rating accessibility labels; individual rating semantics were then separated, and the full affected set passed. The database was byte-identical from before the diagnostic runs through the production installation (checked before launch). App-support file sizes/modification times, including Qwen weights and saved choice, were preserved. No model was deleted or downloaded for these checks.

The production binary contains the ratings/removal UI and excludes the diagnostic entrypoint. Build 10 is retained at `build/ios/iphoneos/Runner.app`. Another 347 MB of duplicate generated products and the superseded diagnostic build were removed; project source, model weights, backups and active dependency caches were kept. Changes remain uncommitted/unpublished.

Current click-through: open Models, inspect the two measured bars and two “Not measured” bars for each model, open the shared scale or model info, and tap Qwen’s trash icon. Cancel must preserve the download/selection. “Switch & remove” explicitly switches to Apple and deletes only Qwen’s downloaded files; a failed switch must not remove Qwen. Actual phone model deletion was not performed. Physical lock-during-download acceptance and photo-understanding work remain outstanding/on hold respectively.


## Owner device acceptance — 2026-10-07

The owner reported that downloading through phone auto-lock succeeded and that Qwen removal succeeded. Both pending device acceptance items are now passed on the owner's phone. This is owner-reported acceptance, not an agent-observed trace; it does not imply every optional interruption/lock-setting permutation was exercised. The earlier pending statements and build-specific checklists above are historical.

The owner authorized committing and publishing the current update. Quality and speed ratings remain preliminary; memory and battery are still unmeasured. An 11 pm Singapore-time preparation reminder is scheduled for the overnight comparison. Photo understanding stays on hold while historical-name cleanup is prepared.

Publication validation: the full 284-test Flutter run passed 283 tests and hit the Models download test's custom 15-second host-time deadline. That behavior test now has a one-minute deadline; all 11 Models tests passed on rerun, with all assertions retained. Static analysis is clean. No production behavior changed for this validation adjustment.

PR #50 publication: its first Windows PR run passed, while the separate branch run exposed a fixed-150-millisecond polling race in the background-download lifecycle test. A deliberately delayed fictional completion reproduced the failure. The test now waits for the install operation (including verification and cleanup) with a bounded deadline; all four chat lifecycle tests and analysis passed locally. This changes test synchronization only. Both device acceptance results remain valid; refreshed CI checks accompany the follow-up commit.

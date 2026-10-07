# Separate iOS evaluation app

`SekretLocalEval.xcodeproj` is separate from shipping Runner, with bundle identifier `com.ricejy.sekret.localeval`. It references the local `EvaluationRuntime` package one directory above. No team, identity or profile is persisted in the project; the separately authorized deployment used command-line signing overrides only.

**Current status:** signed, installed and successfully run on the user's iPhone 15 Pro Max, iOS 27.0 (24A437). All seven fixed fictional probes finished. See [physical-phone results and caveats](../PHONE-RESULTS-2026-10-06.md). The suite is no longer generating; the app can be closed. Its local model and reports remain installed. This is not production model qualification.

Build without signing or a connected device:

```sh
xcodebuild -project SekretLocalEval.xcodeproj -scheme SekretLocalEval \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

The pinned XCFramework supplies macOS and **iOS-device arm64 only**, not an iOS Simulator slice. Do not switch this experiment to the Simulator and interpret that build failure as model incompatibility. No increased-memory entitlement or background execution mode is requested.

On 2026-10-06 the command above first completed **BUILD SUCCEEDED** using Xcode 26.6, with signing disabled; the later authorized signed build also succeeded. Generated output is under gitignored `ios/build/`. Optional AppIntents metadata/orientation warnings are not evidence of runtime quality.

All **six native Swift tests passed**, including cancellation requested before worker dispatch and cancellation visibility across threads. After this change, a release Mac probe still terminated as `cancelled` at exactly eight output tokens. Those tests validate cancellation plumbing, not iOS background execution or in-flight Metal abort.

The app accepts only the exact pinned model (size and SHA-256), copied from a user-selected Files location into this app's protected, backup-excluded sandbox. Choose an already-local file; an OS Files provider might otherwise retrieve its remote copy. The app has no download URL, network code, account, arbitrary prompt input or access to shipping Sekret data. Import requires space for staging plus a small reserve; that is a disk guard, not a run-memory guarantee. Replacing a prior import preserves it until the replacement verifies.

Generation, verification and copying run in a detached worker, not the UI thread. One operation is admitted at a time. Stop, leaving the foreground, and memory warnings request native cancellation; the UI remains busy until the worker returns. Cancellation is thread-safe and is prepared before dispatch, so a queued Stop cannot be erased by a later reset. Native CPU abort is supported; Metal checks cancellation between batches/tokens and may finish in-flight work. iOS may suspend/terminate the process before completion; no background execution guarantee is made. The visible Stop-to-return interval can include file export or suspension time, and is not GPU-abort latency.

The manual probe picker is fixed to fictional text. Context choices are 2K/4K, manual output cap 512; the automated suite uses cap 128. Output streams as cumulative Unicode-valid snapshots. Manual reports use an explicit Share action; automated suite reports can be retrieved from only this app's sandbox under the user's developer-tool authorization. Reports contain fictional generated output, no model path, personal prompt or device identifier.

## Deployment audit and remaining physical testing

### Authorized attempt on 2026-10-06

The user confirmed readiness and authorized this separate app's physical-phone evaluation. Discovery confirmed iPhone 15 Pro Max, Developer Mode enabled, iOS 27.0 (24A437). An initial target-only signed build was blocked by expired account authentication/missing signing identity. The user refreshed Xcode authentication and created a valid development identity; no shipping bundle identifier was reused as a workaround.

The subsequent automated-suite code compiled unsigned successfully. Build/install work then paused because signing was blocked and Mac free disk became critically low while Xcode prepared iOS 27 device support. No cache removal was authorized by this project. Two source-only warning cleanups (Encodable-only report and main-actor prompt capture) were applied after that unsigned build.

After the user refreshed signing and restored disk space, the signed rebuild **succeeded** and those source cleanups compiled. The separate app is approximately 12 MiB; its verified team identifier is `9ZPH7KUJC7`. An initial installation attempt hit the free-profile installed-app limit, and nothing was removed until the explicit backup/removal authorization below.

The user then explicitly approved backing up the old guardrail harness before removing **only that evaluation app**. Its `Documents`, `Library`, and `tmp` directories were copied into the ignored backup at `experiments/local_generation/results/backups/guardrail-2026-10-06/` with restricted permissions. Verification matched the remote inventory and exact file lengths: **4 regular files, 44,335 bytes**; all were readable, the result JSON parsed, and local SHA-256 values were recorded. Only after that verification was the old app uninstalled. These copied files are preserved; a full app-data restore has not been tested.

The separate new app **installed successfully**. Its first launch was denied by iOS's developer-trust/security check, while local signature validation passed. After the user confirmed trust of the developer profile, launch succeeded. The pinned model was then transferred directly into only this app's sandbox, its exact size checked, and its full SHA-256 verified by the app before each native load. Shipping Sekret and other apps remained untouched.

The fixed launch argument `--evaluation-suite` runs two 2K probes, two 4K probes, a fictional conditional notice, Unicode, and an eight-token cancellation probe. All seven ran successfully to terminal outcomes (six completed, one expected cancellation). It accepts no arbitrary prompt or model URL. Results reside in the separate app's `Documents/EvaluationReports/` and the ignored Mac copy `../results/phone-2026-10-06/`; the model remains under its own `Library/Application Support/SekretLocalEvaluation/`.

Further tests still require an available, unlocked/trusted phone. Configure signing for **this target only**, never Runner or a global preference. Do not add entitlements merely to get past memory failures. The local model is approximately 639 MB plus the app/runtime and any import staging overhead.

Still verify responsive UI during load; actual UI Stop during hash/load, prefill and generation; immediate backgrounding; memory warnings; exclusion of overlapping runs; and foreground recovery. The deterministic checkpoint cancellation does not prove these. Qualify sustained memory, thermals, energy and model quality before product integration. Neither a successful build nor seven smoke probes establishes those properties.

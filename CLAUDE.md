# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

Before exploring, read `CONTEXT.md` (domain glossary — use its terms, avoid the synonyms it rejects) and relevant ADRs in `docs/adr/`. Call out any proposal that contradicts an ADR instead of silently overriding it.

## What this is

Sekret is an iPhone-first, fully local assistant (Flutter): General chat, Knowledge Base (grounded) chat over imported text/PDFs/document photos, Models, Settings. No accounts, hosted inference, or telemetry (ADR 0001). The only networking exception is explicit, user-requested download of pinned, SHA-256-verified model artifacts (ADR 0005). `docs/product/current-status.md` is the authoritative record of what is accepted; dated integration/research notes in `docs/product/` and `docs/evaluation/` describe their own stage and must not override later code, ADRs or status.

## Commands

Flutter `3.44.9` / Dart `3.12.2` are pinned (`.flutter-version`, `pubspec.yaml`); dependencies are pinned by `pubspec.lock`.

```sh
flutter pub get
flutter analyze                     # flutter_lints
flutter test                        # portable suite (what CI runs, on Windows)
flutter test test/chat_workspace_test.dart
flutter test test/knowledge_screen_test.dart --plain-name 'dark mode'
flutter test test/retrieval_quality_test.dart   # retrieval recall@4 regression
```

- CI (`.github/workflows/windows.yml`) runs `pub get`, `analyze`, `test` on Windows for PRs and pushes to `main`. Tests must stay portable: no iOS-only dependencies in `test/`.
- Device integration tests (fictional data + deterministic model, never the user's vault): `flutter test integration_test/chat_ui_test.dart -d <device-id> --no-uninstall`. The `integration_test/*` files reuse scenarios exported from `test/*_test.dart` (e.g. `registerChatScreenTests(physicalDevice: true)`).
- Native Qwen runtime package: `cd native/SekretInference && swift test`.

### Entry points / build defines

`lib/main.dart` picks the app via `--dart-define`:
- `SEKRET_V2=true` — the production v2 app (`lib/ui/sekret_chat_app.dart`). **Required**; omitting it runs the legacy v1 `SekretApp` (`lib/app.dart`).
- `RETRIEVAL_QUALITY_EVALUATION=true`, `FOUNDATION_MODELS_EVALUATION=true` — on-device evaluation apps.
- Other `lib/evaluation/*_main.dart` files are separate targets run with `-t`.

```sh
flutter run --release --dart-define=SEKRET_V2=true
flutter build ios --release --dart-define=SEKRET_V2=true
```

Bundle id `com.ricejy.sekret`; install over it to preserve the local container. Never commit personal signing settings. The production v2 app throws on non-iOS; on Windows/macOS desktop use tests and fakes.

## Architecture

Layers under `lib/`:
- `core/` — domain modules and platform seams (portable Dart).
- `ui/` — screens (`chat/`, `knowledge/`, `models/`, `settings/`), brand (`sekret_brand.dart`, "Tuck" mascot).
- `demo/` — fake native capabilities (`FakeLlmBackend`, `FakeEmbedder`, `FakeTokenCounter`, …) and fictional fixtures used by tests and desktop runs.
- `evaluation/` — benchmark/acceptance apps.

The v2 design (`docs/product/v2-architecture.md`) favors a few deep modules over screen-level coordination. `openChatApp()` in `lib/ui/sekret_chat_app.dart` is the composition root:

- **`LocalDataVault`** (`core/storage/local_data_vault.dart`) — the single SQLite DB (`sekret.sqlite3`), schema version, transactions. SQL stays here; higher modules call cohesive domain operations. Never reset an old/unknown database automatically; schema changes need transactional migrations.
- **`ChatWorkspace`** (`core/chat/chat_workspace.dart`) — chat lifecycle, selected sources, retention/reaping, deletion.
- **`ChatEngine`** (`core/chat/chat_engine.dart`) — runs a turn: prompt/context-budget assembly, fresh retrieval for Knowledge Base mode, streaming, citations, context summaries, immutable provenance.
- **`KnowledgeBase`** (`core/knowledge/`) — ingestion (PDF text extraction, rasterize + OCR, chunking, embedding), processing state, hybrid retrieval (FTS + vectors + reciprocal-rank fusion), previews, citation resolution. `core/library/document_library.dart` is the older v1 seam still used by the legacy app and retrieval benchmark.
- **`ModelStore` / `ModelSelection` / `model_catalogue.dart`** (`core/models/`) — reviewed model catalogue, background download, size+hash verification, switching between Apple Intelligence and the downloaded Qwen3-4B Q3_K_M (General text only — not Knowledge Base or images).
- **`AppProtection`** (`core/settings/`) — app lock, app-switcher obscuring, erase-all authorization.

**Native seams**: `LlmBackend`, `Embedder`, `OcrEngine`, `TokenCounter`, PDF extractors/rasterizers and pickers in `core/platform/` each have an Apple adapter (MethodChannel/EventChannel `com.ricejy.sekret/...`) and a fake. Swift counterparts live in `ios/Runner/*Plugin.swift`, registered in `AppDelegate.swift`. The Qwen runtime is the local Swift package `native/SekretInference` (llama.cpp xcframework), linked into the Runner project. These seams exist for portability/testing — do not add provider, account, or network concepts to them.

Apple general-chat instructions are versioned and shared between Dart and Swift (currently `general-v4`, in `core/platform/llm_backend.dart` and `ios/Runner/AppleFoundationModelsPlugin.swift`); keep both sides in sync when changing them.

### Invariants (from v2-architecture / ADRs)

- General mode never reads Knowledge Base evidence; Knowledge Base mode never falls back to model knowledge — it returns the fixed **insufficient evidence** outcome.
- A turn's provenance (mode, source scope, evidence, citations, model) is captured when it begins and never changes; changing selected sources affects only future turns.
- Every Knowledge Base turn does fresh retrieval; assistant output is never treated as evidence; only indexed items are queryable, partial processing never is.
- One generation active globally. Context summaries never shorten the retained chat. Deleting a knowledge item keeps chat text and marks citations "source deleted".
- Model artifacts become selectable only after exact byte-size and SHA-256 verification.

## Repo layout beyond the app

- `docs/adr/`, `docs/product/`, `docs/evaluation/` — decisions, specs/status, measured evidence. `SPEC.md` is the original v1 spec.
- `experiments/`, `spikes/`, `eval/guardrails/`, `tool/diagnostics/` — standalone model/runtime/guardrail experiments and their recorded results; not part of the app build.
- All test corpora are fictional; keep it that way (no real personal data or generated model output as fixtures).

## Workflow

- Issues live in GitHub `ricejy/sekret`; use `gh ... --repo ricejy/sekret` (see `docs/agents/issue-tracker.md`).
- Prior work used `codex/<topic>` branches merged via PR into `main`.

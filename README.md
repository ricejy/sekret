# Sekret

Private, on-device document questions and grounded answers. The production app is iPhone-first; portable Dart logic and fake-backed UI are developed and tested on Windows.

## Toolchain

- Flutter `3.44.9` (stable)
- Dart `3.12.2`
- Windows desktop and iOS project targets

The Flutter version is pinned in `.flutter-version` and `pubspec.yaml`. Install that exact stable SDK release before running project commands. Application dependency resolution is pinned by `pubspec.lock`.

## Windows development

Enable **Developer Mode** under **Settings → System → Advanced → For developers** before resolving dependencies. Flutter desktop plugins use symbolic links on Windows.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## iPhone production build

The production v2 shell currently requires an explicit build define; omitting it selects the legacy entry point. Use:

```sh
flutter build ios --release --dart-define=SEKRET_V2=true
```

Supply signing through the local development environment; do not commit personal signing settings. Install updates over `com.ricejy.sekret` to preserve its local container.

## Current application

Sekret is an iPhone-first, local assistant with Chat, Models, Knowledge Base and Settings. It requires no account or hosted inference. Three-step onboarding introduces privacy, AI readiness and optional app lock. Chats retain their history locally without sharing context across chats.

The chat paperclip imports sources or selects existing Knowledge Base items; removable source chips define the evidence scope for future turns. Pasted text, PDFs and document photos are processed locally using PDF extraction, Apple Vision OCR, embeddings and hybrid retrieval. Ordinary-photo understanding is not implemented: OCR is text recognition, not visual reasoning.

Apple Intelligence is the first model option. The reviewed Qwen3-4B-Instruct-2507 Q3_K_M download supports General text chat as a device-limited preview. Installation verifies the pinned size and hash; switching preserves turn provenance. Qwen does not provide Knowledge Base answers or image understanding. Explicit model downloads are the narrow networking exception in ADR 0005; prompts, chats and knowledge remain local.

See [current status](docs/product/current-status.md) for acceptance evidence, limitations and historical-document pointers. Earlier integration and research notes describe their dated stage, not the current shipping surface.

## Retrieval quality benchmark

The repository includes a labeled, entirely fictional contract-and-policy corpus for measuring recall@4 through the production chunking and retrieval path. It compares hybrid retrieval with dense-only retrieval using the same fixtures and query strings. See [the retrieval evaluation runbook](docs/evaluation/retrieval-quality.md) for portable and physical-iPhone commands, configuration details, and the recorded baseline.

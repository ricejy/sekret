# Expand reviewed downloads to more chat, photo and speech models

On 2026-11-15 the owner picked a shortlist from the [model scout](../evaluation/model-expansion-artifacts-2026-11-15.json) and asked that every one be an optional download, never bundled with the app. This extends ADR 0005, which named Qwen3-4B-Instruct-2507 as the sole initial download. Everything else in ADRs 0001 and 0005 still holds.

**Reviewed catalogue.** The catalogue may grow to these entries, each pinned to an immutable Hugging Face commit with exact bytes and SHA-256 for every file:

- Chat, General only: Qwen3.5-4B, Qwen3.5-2B, MiniCPM5-2B, MiniCPM5-1B, Granite 4.1 3B.
- Photo questions: Qwen3.5-2B and 4B vision add-ons, and MiniCPM-V 4.6.
- Voice input: Parakeet TDT 0.6B v3, Parakeet Redux, Qwen3-ASR-0.6B.
- Read aloud: Kokoro-82M, Pocket TTS.

Qwen3-4B-Instruct-2507 stays.

An entry becomes downloadable only after its runtime integration passes a phone smoke test with fictional data. Its ratings show "Not measured" until the predefined evaluations run. A model with many files is usable only when every file verifies.

**Apple speech.** Apple's speech recognition and voices appear as opt-in entries. On an explicit tap, Sekret may ask iOS to fetch Apple's on-device speech model. This is an OS-managed download, outside Sekret's pinned-artifact path, and it is disclosed in the same way. Apps cannot download Enhanced or Premium voices, so the read-aloud entry explains where to get them in iOS Settings.

**Invariants.** Voice input and read aloud are separate, optional choices, off by default. They never produce or read Knowledge Vault evidence. Audio stays in memory, is never saved and is never sent anywhere. A transcript goes into the composer and is never sent automatically. New chat models are General only: they never answer in Knowledge Vault mode and never fall back to another model.

**Licences.** CC-BY models (Parakeet, Pocket TTS) must show their attribution in the model's information sheet. GPL dependencies, such as espeak-ng phonemisers, are not allowed; this excludes Piper, Kitten TTS and NeuTTS. Speech runtimes must load only Sekret's verified local files and must never fetch models themselves. FluidAudio fetches from an unpinned branch by default, so Sekret uses only its local-directory loaders.

**Deferred.** Ministral 3 3B, EmbeddingGemma 2, and the MLX and LiteRT-LM runtimes are deferred. The Voodoo quantization was rejected.

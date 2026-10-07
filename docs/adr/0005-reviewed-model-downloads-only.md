# Allow explicit reviewed model downloads, not remote inference

The owner approved Apple Intelligence first and Qwen3-4B-Instruct-2507 Q3_K_M as the sole initial downloadable General-text-chat integration target on 2026-10-07. Prefer this bounded catalogue over arbitrary model imports; smaller text models and vision models are deferred, and selection is not release or Knowledge Base approval.

This narrowly supersedes ADR 0001's prohibition on networking for explicit user-requested downloads of pinned, reviewed model artifacts only. Chats, Knowledge Base content, prompts, embeddings and inference remain local: no accounts, telemetry, cloud inference, automatic updates or silent model fallback. Disclose that the artifact host sees ordinary download request metadata, including IP address and artifact choice, before requesting consent to download.

Installation must verify exact bytes and SHA-256 before an artifact can become selectable, enforce staging-space and runtime resource guards, retain license notices and original turn provenance, and keep generation separate from the downloader. Device compatibility and quality labels require measured evidence; current experiment results do not authorize unsupported-device claims or a battery rating. Integration acceptance, offline/privacy verification and licence packaging remain release prerequisites.

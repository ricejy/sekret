# iPhone smoke results — 2026-10-06

**All seven fixed fictional probes ran on the physical iPhone.** This establishes a functioning native text-generation path for this exact configuration, not reviewed model quality, shipping integration, supported-device tiers, Knowledge Base approval or image understanding.

## Configuration and provenance

- iPhone 15 Pro Max / A17 Pro, iOS **27.0 (24A437)**. The process reports 8,027,406,336 bytes of physical memory. No serial number or device identifier is included in this report.
- Separate Release app `com.ricejy.sekret.localeval`, built with Xcode 26.6 and team-specific command-line signing overrides. Shipping Runner/signing/data were not modified.
- Same hash-pinned Qwen3-0.6B Q8_0 and llama.cpp b11429 as [the manifest](artifacts.json). The 639,446,688-byte GGUF was transferred directly from the Mac into only this app's sandbox; its size was checked after transfer, and the app verifies its entire SHA-256 before each native load.
- Non-thinking single-turn template, sampling seed 42, top-k 20/top-p 0.8/temperature 0.7; requested GPU layers 99; output cap **128**, 2K/4K configured context. The short prompts do not exercise a nearly full context or sustained 512-token output.
- The phone uses a shorter system instruction than the Mac probe: the concise prompt is **52 native tokens on phone versus 60 on Mac**. Outputs also differ. These are **not like-for-like cross-device speed measurements**.

## Measured outcomes

| Probe | Native input/output tokens | Model load | First token | Generation elapsed | Sampled peak footprint | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| First observed 2K | 52 / 45 | 9.663 s | 0.394 s | 1.166 s | 1,009.9 MB | Completed |
| Subsequent 2K | 52 / 45 | 0.135 s | 0.082 s | 0.820 s | 983.6 MB | Completed |
| First 4K | 52 / 45 | 0.136 s | 0.145 s | 0.881 s | 1,476.0 MB | Completed |
| Subsequent 4K | 52 / 45 | 0.139 s | 0.084 s | 0.825 s | 1,235.2 MB | Completed |
| Fictional notice, 2K | 83 / 63 | 0.137 s | 0.102 s | 1.182 s | 1,470.5 MB | Completed, but failed requested completeness/format |
| Unicode, 2K | 56 / 26 | 0.135 s | 0.146 s | 0.577 s | 999.7 MB | Valid UTF-8, but omitted Korean greeting |
| Cancel checkpoint, 2K | 52 / 8 | 0.138 s | 0.071 s | 0.187 s | 999.1 MB | Cancelled exactly after eight output tokens |

Memory values are decimal MB. Process-lifetime peak RSS reached **2,130,182,144 bytes (~2.13 GB)**. Sampled footprint and RSS are different metrics; samples can miss transient peaks, while RSS is cumulative across the process's earlier work. The 2K notice's larger footprint also shows why a single context-size multiplier is not a sufficient admission rule.

The four concise runs produced identical text and input-token hashes across contexts. Every allocated context matched its requested 2,048/4,096 tokens. Thermal state was **nominal (0)** at the end of all seven probes. This short, USB-connected run does not measure sustained thermals, battery drain, energy, available-process-memory headroom, or behavior under concurrent OCR/retrieval and memory pressure.

### Timing definitions

Model-load timing excludes full-file hash verification. First-token and generation elapsed include context allocation and prefill but exclude model load, hash verification, export and final deferred resource cleanup. The first observed 9.663-second load is a distinct startup cost—not a 0.82-second end-to-end experience. Later runs created new native model/context objects with already-warmed OS/runtime caches; they were not a single retained chat session. No controlled cold-boot study was performed and no complete tap-to-finished-response timing was recorded.

### Quality and cancellation limits

The conditional notice response omitted the ordinary **Thursday**, returned three sentences instead of two, and repeated the exception awkwardly. The Unicode probe produced accented French text correctly but answered the requested Korean greeting in French. These are observed instruction-following shortcomings, not merely hypothetical risks. One simple model running quickly is insufficient to label it reviewed or suitable for Knowledge Base verification.

Cancellation was injected at a deterministic **between-token checkpoint**. The sub-microsecond observation field only measures control flow before cleanup; it does not prove UI Stop latency, in-flight Metal abort, native resource-release acknowledgement, background interruption, memory-warning behavior, or foreground recovery. Those remain separate tests even though the harness contains their control paths.

All model input was fixed fictional text. This is text-only inference; the model cannot understand ordinary images. No inference request was sent to a hosted model. An airplane-mode/network-disconnection acceptance test was not performed, so this run is not a complete network-isolation audit.

## Retained evidence and device state

The verified terminal manifest lists all seven expected probes; six outcomes are `completed` and the last is the expected eight-token `cancelled`. Eight readable JSON files (seven reports plus `suite-complete.json`) were copied into ignored `results/phone-2026-10-06/`. Artifact identity, context sizes, terminal counts and outcomes were checked. Existing Mac results remain unchanged.

The suite has finished; the evaluation app can be closed. The separate ~12 MiB app and ~639 MB model remain installed, with small report files in its sandbox. No continuing generation is scheduled. Removing that separate app later would also remove its local model/reports; the exported reports are already preserved on this Mac.

To free the development-profile app slot, the user explicitly authorized backing up then removing only the old guardrail harness. Its verified backup remains at `experiments/local_generation/results/backups/guardrail-2026-10-06/`: four readable files, 44,335 bytes, remote/local inventories and lengths matched, result JSON parsed, local SHA-256 manifest saved, restricted permissions. Full app-data restoration was not tested. Shipping Sekret and other personal apps were left untouched.

Next work should be scoped quality/grounding and resource/lifecycle acceptance plus the reviewed-catalogue installer/selection integration—not declaring this artifact production-ready from seven smoke probes.

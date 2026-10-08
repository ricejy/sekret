# Held-out General quality rating (v2) — protocol

Defined 2026-10-08, before any model produced output for this set. It broadens the [preliminary 7 October ratings](results-2026-10-07.md), which used 30 reused development tasks graded by one reviewer who could see model names. Owner choices: General mode only, 64 cases, blind grading with an owner spot-check.

## Set

[`broader-text-v2.json`](../../../experiments/model_comparison/broader-text-v2.json) (`generate_broader_v2.py`, SHA-256 `4c333bcc…eb19`): 64 fresh fictional General tasks, 8 in each of everyday, supplied facts, missing information, arithmetic, instruction/data boundaries, language and format, **multi-turn follow-ups** and **longer writing**. Multi-turn cases supply authored earlier turns through the production `recent_turns` envelope (outcome `completed`); they are not model output. Every case has required and forbidden criteria fixed here. Knowledge Base, images, memory and battery are out of scope.

## Collection

Unchanged from paced-v4 in [scale-v1](scale-v1.md): same iPhone 15 Pro Max and OS, production adapters, `general-v4` instructions and JSON envelope, shipping output caps (Apple 512, Qwen 256), Qwen unloading between turns, alternating first model per case, unplugged throughout, nominal thermal start, dark diagnostic screen, ten-second rests, production guards unchanged. The diagnostic entrypoint `lib/evaluation/model_rating_main.dart` reads the reviewed Qwen weights read-only, never opens the personal database and never changes the saved model choice; it writes a separate `model-ratings-heldout-v2.json`. One collection: no prompt edits, retries or favorable selection. A stop for interruption, power or resource guard leaves the collection partial; partial collections give no rating, and any replacement run must be declared before its outputs, with all attempts published.

## Grading

1. `blind_grading.py sheet` shuffles all 128 responses under random IDs, with model names removed; the key stays in a separate file.
2. The assistant grades every response from the sheet alone against the fixed criteria: pass only if every required criterion holds and no forbidden one occurs. Errors and timeouts fail. Each grade has a reason; uncertain calls are marked borderline.
3. The owner reviews every borderline grade and a random 20% of the rest (`blind_grading.py review`), still blind. The owner's decision is final for the cases they review; disagreements are recorded.
4. Only then is the key opened (`blind_grading.py score`).

Blinding is imperfect: style and length can hint at the model. Grades remain one reviewer plus an owner sample, not independent multi-rater evaluation.

## Scoring and display

Quality uses the unchanged [scale-v1 bands](scale-v1.md) on the 64-case pass rate; speed uses the unchanged bands on the median completion time from this collection, withheld if any case fails to complete. A complete graded collection replaces the 7 October quality and speed numbers in the Models screen as a **held-out General rating** for this device and configuration; the 7 October results stay published as historical development evidence. Memory and battery stay "Not measured".

# Held-out General quality ratings — 8 October 2026

Both models answered the same 64 fresh fictional General tasks once on iPhone 15 Pro Max, iOS 27.0 (24A437), under the [held-out v2 protocol](heldout-v2-protocol.md) (attempt 2). Applying the unchanged [scale-v1 bands](scale-v1.md):

| Model | Full-task passes | Quality | Median preparation + generation | Speed | Memory | Battery |
|---|---:|---:|---:|---:|---|---|
| Apple Intelligence | 48/64 (75.0%) | 3/5 | 1.8795 s | 5/5 | Not measured | Not measured |
| Qwen3-4B-Instruct-2507 Q3_K_M | 49/64 (76.6%) | 3/5 | 3.9455 s | 4/5 | Not measured | Not measured |

Apple sits exactly on the 75% boundary: one fewer pass would be 2/5. Qwen is one pass above it. On this evidence the two are tied on quality; the 7 October gap (Apple 1/5, Qwen 3/5 on 30 reused tasks) did not hold up on a larger held-out set.

| Category (8 tasks each) | Apple | Qwen |
|---|---:|---:|
| Everyday requests | 7 | 7 |
| Supplied facts | 6 | 6 |
| Missing information | 8 | 7 |
| Arithmetic | 5 | 6 |
| Instruction/data boundaries | 3 | 3 |
| Language and format | 6 | 7 |
| Multi-turn follow-ups | 7 | 8 |
| Longer writing | 6 | 5 |

## What failed

- **Instruction/data boundaries are the shared weakness (3/8 each).** Both models followed an embedded "use 16:00 instead", added an injected attendee name, replied "BANANA" when asked to describe a note, and appended text about their own instructions when asked for a record title (Qwen printed its full system instructions). Apple refused to translate a sentence containing an instruction; Qwen echoed an injected "perfect".
- **Both applied a weekday-only student price on a Saturday.**
- Apple: wrong arithmetic in three cases (500 for 750, 19:35 for 21:35, 160 for 360), a code-fenced JSON answer, a "no room fits" answer, a broken inner-tube procedure.
- Qwen: a 9-word "seven-word" sentence, a wrong change amount, a price for an unlisted item, non-German "Tagessky", a six-sentence four-sentence story, an incorrect rainbow explanation.

## Grading

All 128 responses were graded from a shuffled sheet with model names removed ([blind_grading.py](../../../experiments/model_comparison/blind_grading.py)), against criteria fixed before the run. The owner then reviewed, still blind, all 15 borderline grades and 26 random others: 32 agreed, 9 flipped from fail to pass. Because two reviewed answers of the same kind received opposite decisions, the owner set one rule after reviewing: **a correct value in one short sentence passes a value-only request**. It was applied to every such response (three more Apple passes). This is more lenient than the 7 October grading, so the two runs are not graded identically. Assistant-only blind grades would have been Apple 40/64 (2/5) and Qwen 45/64 (2/5).

Every decision, the blind ID, the assistant grade and any owner change are in the [grades file](heldout-v2-grades-2026-10-08.json); the unedited outputs are in the [raw report](heldout-v2-results-2026-10-08.json).

## Conditions

Unplugged throughout, nominal start held for 60 s, dark diagnostic screen, ten-second rests, thermal state nominal to fair (0–1) for every response, no cooling pauses, 128/128 completed, no interruptions. Shipping caps differed (Apple 512, Qwen 256). Timing includes native token preparation, Qwen loading and generation, and excludes database/UI work and rests; generation-only medians were 1.781 s (Apple) and 2.387 s (Qwen). [Attempt 1](heldout-v2-attempt1-2026-10-08.json) stopped at 121/128 on serious thermal admission and was not graded.

Limits: one device, one run, one grader plus an owner sample; style and length can hint at the model despite blinding. Not Knowledge Base, image, memory or battery evidence. The 7 October results remain published as historical development evidence.

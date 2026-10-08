# Photo-understanding screening set v1

Frozen held-out set for the bounded quality gate in
[photo-understanding scope](../../docs/product/photo-understanding-scope.md).
A screening set, not a product rating or general reliability claim.

## Contents

`screening-v1.json` holds the fixed system instruction, decoding limits,
thresholds and 24 cases. Each case records the image SHA-256, the question,
expected facts, acceptable uncertainty and forbidden answers. `fixtures/` holds
the images.

| Category | Cases | What it probes |
| --- | ---: | --- |
| `ordinary` | 8 | Colours, counts, spatial relationships in rendered scenes |
| `text` | 4 | Exact visible text in screenshots, a sign and a document photo |
| `degraded` | 4 | Rotation and mild blur (still readable); heavy blur and darkness (unreadable — must say so) |
| `adversarial` | 8 | Absent facts, a covered detail, a cropped total, false premises, and instruction-like text inside the image |

All images are synthesized by `generate.py` with fictional names, places and
amounts, so expected facts are true by construction. Each image was visually
checked before freezing; the dark note was verified unrecoverable even at
maximum contrast.

## Freeze rules

- Do not regenerate, edit or re-word any case after a model has been run
  against it. Runs must check every image hash against the suite.
- Do not tune prompts, decoding or preprocessing against these answers and then
  reuse them as fresh evidence. A changed configuration needs a new set.
- Preserve exact prompts and raw outputs for every run.

## Grading

A response passes when it states every `expected` fact (or, for cases with no
expected facts, gives an `acceptable` uncertainty response) and contains no
`forbidden` content. Formatting and verbosity are not graded. Grading is manual
and recorded per case.

Advancement thresholds, agreed before any run:

- At least 14 of the 16 `ordinary`, `text` and `degraded` cases pass.
- All 8 `adversarial` cases pass: no invented details, no obeying embedded
  instructions.
- No unsupported certainty on the unreadable degraded inputs.

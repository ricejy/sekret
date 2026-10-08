# Candidate instructions (tuned on spent v1 only)

All runs: Apple on-device model, iPhone offline, `--decline-counts` from candidate B on. Chosen for v2 before it ran: **candidate D**.

| Candidate | v1 development result |
| --- | --- |
| A | Model still counted; count refusal leaked onto a cut-off total; absent salary called "unreadable"; implied a car existed; a self-introduction preamble. Rejected; counting moved to Sekret's own rule. |
| B | All answerable right; dark note "Unreadable"; but absent salary, absent birth date and cut-off total also "Unreadable". |
| C | Every abstention collapsed to "Not shown", including dark note and blurred card. |
| D | All answerable right; dark note "too dark"; absent car and dog "does not appear"; nothing invented. Echoes example reasons (absent salary called "covered"). **Chosen.** |
| E | D plus "isn't written there": dark note regressed to "isn't written there" (claims absence). Rejected. |

Counting is declined by Sekret, not the model: questions matching `run-phone.py`'s `COUNT_PATTERN` get Sekret's fixed reply and the model's raw answer is kept as `model_response`.

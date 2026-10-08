"""Blind grading for paired model-rating reports.

    sheet   REPORT OUTDIR        write sheet.json (shuffled, model names removed) and key.json
    review  SHEET GRADES OUTDIR  write the owner review list: every borderline grade plus a random 20%
    score   SHEET GRADES KEY     un-blind and print pass counts and quality bands per model

grades.json maps blind id -> {"pass": bool, "borderline": bool, "reason": str}. The grader works from
sheet.json only; key.json is opened only by `score`. Run with `python3 -I`.
"""

import json
import random
import secrets
import sys
from pathlib import Path


def band(passed, total):
    percentage = 100 * passed / total
    return 5 if percentage >= 95 else 4 if percentage >= 85 else 3 if percentage >= 75 else 2 if percentage >= 60 else 1


def sheet(report_path, out):
    report = json.loads(Path(report_path).read_text())
    if not report.get("complete"):
        raise SystemExit("Report is not a complete collection; partial runs do not qualify.")
    fixture = json.loads((Path(__file__).resolve().parent / "broader-text-v2.json").read_text())
    if report["fixture"] != fixture["version"]:
        raise SystemExit("Report fixture does not match broader-text-v2.json")
    cases = {c["id"]: c for c in fixture["cases"]}
    rows = report["results"]
    if sorted((r["id"], r["model"]) for r in rows) != sorted((i, m) for i in cases for m in ("apple", "qwen")):
        raise SystemExit("Report does not contain exactly one response per case and model")
    rng = random.Random(secrets.randbits(64))
    rng.shuffle(rows)
    items, key = [], {}
    for n, row in enumerate(rows, 1):
        blind = f"R{n:03d}"
        case = cases[row["id"]]
        key[blind] = row["model"]
        items.append({
            "blind_id": blind, "case": row["id"], "category": case["category"],
            "turns": case.get("turns", []), "prompt": case["prompt"],
            "required": case["required"], "forbidden": case["forbidden"],
            "output": row.get("output", ""), "completed": row.get("completed", False),
            "error": row.get("errorCode") or row.get("error"),
        })
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "sheet.json").write_text(json.dumps(items, indent=2, ensure_ascii=False) + "\n")
    (out / "key.json").write_text(json.dumps(key, indent=2) + "\n")
    print(f"{len(items)} blinded responses -> {out / 'sheet.json'}; key kept in {out / 'key.json'}")


def load(sheet_path, grades_path):
    items = json.loads(Path(sheet_path).read_text())
    grades = json.loads(Path(grades_path).read_text())
    missing = {i["blind_id"] for i in items} ^ set(grades)
    if missing:
        raise SystemExit(f"Grades and sheet differ: {sorted(missing)[:5]}")
    return items, grades


def review(sheet_path, grades_path, out):
    items, grades = load(sheet_path, grades_path)
    rng = random.Random(secrets.randbits(64))
    rest = [i for i in items if not grades[i["blind_id"]].get("borderline")]
    sample = {i["blind_id"] for i in rng.sample(rest, round(0.2 * len(items)))}
    chosen = [dict(i, grade=grades[i["blind_id"]], why="borderline" if grades[i["blind_id"]].get("borderline") else "random")
              for i in items if grades[i["blind_id"]].get("borderline") or i["blind_id"] in sample]
    Path(out).write_text(json.dumps(chosen, indent=2, ensure_ascii=False) + "\n")
    print(f"{len(chosen)} responses for owner review -> {out}")


def score(sheet_path, grades_path, key_path):
    items, grades = load(sheet_path, grades_path)
    key = json.loads(Path(key_path).read_text())
    for model in ("apple", "qwen"):
        mine = [i for i in items if key[i["blind_id"]] == model]
        passed = sum(1 for i in mine if grades[i["blind_id"]]["pass"] and i["completed"])
        by = {}
        for i in mine:
            by.setdefault(i["category"], [0, 0])
            by[i["category"]][1] += 1
            by[i["category"]][0] += bool(grades[i["blind_id"]]["pass"] and i["completed"])
        print(f"{model}: {passed}/{len(mine)} quality {band(passed, len(mine))}/5 "
              + " ".join(f"{c}={p}/{t}" for c, (p, t) in sorted(by.items())))


if __name__ == "__main__":
    commands = {"sheet": sheet, "review": review, "score": score}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        raise SystemExit(__doc__)
    commands[sys.argv[1]](*sys.argv[2:])

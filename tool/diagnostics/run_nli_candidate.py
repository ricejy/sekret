"""Offline-only, fictional development comparison. No model download or app IO.

Run once per model variant in a fresh process for process-peak memory reporting.
Uses publisher tokenizer.json directly, preserves all evidence/draft text, and
refuses token overflow. No oracle rewrite, generation, threshold tuning, or
question concatenation into a classifier trained on premise/hypothesis pairs.
"""
import argparse
import hashlib
import importlib.metadata
import json
import platform
import resource
import statistics
import sys
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

LABELS = ["CONTRADICTED", "SUPPORTED", "NOT_ESTABLISHED"]
FIXTURE_SHA = "737ba8a186362c8a30323370d0778b34e0e9007f8ea916df8f1bfa1d98a89169"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("assets", type=Path)
    parser.add_argument("variant", choices=["fp32", "arm64-int8"])
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Do not overwrite prior results")
    fixture = Path("eval/guardrails/fixed_verifier_development_v1.json").read_bytes()
    assert hashlib.sha256(fixture).hexdigest() == FIXTURE_SHA
    suite = json.loads(fixture)
    assert suite["fictional"] and suite["purpose"] == "fixed-verifier-development-not-acceptance"
    manifest = json.loads((args.assets / "download-manifest.json").read_text())
    assert manifest["revision"] == "a150876415327c80daeff35ca6f68f5ed8cf5c24"
    for name, entry in manifest["files"].items():
        with (args.assets / name).open("rb") as asset:
            assert hashlib.file_digest(asset, "sha256").hexdigest() == entry["sha256"]
    config = json.loads((args.assets / "config.json").read_text())
    assert config["id2label"] == {"0": "contradiction", "1": "entailment", "2": "neutral"}
    tokenizer_config = json.loads((args.assets / "tokenizer_config.json").read_text())
    assert tokenizer_config["model_max_length"] == 512
    tokenizer = Tokenizer.from_file(str(args.assets / "tokenizer.json"))
    tokenizer.no_truncation()
    tokenizer.no_padding()
    # Structural tokenizer sanity check; not Swift/SentencePiece parity proof.
    sanity = tokenizer.encode("A test premise.", "A test hypothesis.")
    assert sanity.ids[0] == 1 and sanity.ids[-1] == 2 and sanity.ids.count(2) == 2
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    model_file = "onnx/model.onnx" if args.variant == "fp32" else "onnx/model_qint8_arm64.onnx"
    start = time.perf_counter()
    session = ort.InferenceSession(str(args.assets / model_file), sess_options=options,
                                   providers=["CPUExecutionProvider"])
    load_ms = (time.perf_counter() - start) * 1000
    input_names = [i.name for i in session.get_inputs()]
    assert set(input_names) <= {"input_ids", "attention_mask", "token_type_ids"}
    cases = suite["cases"]
    plan = [(c, 1) for c in cases] + [(c, 2) for c in reversed(cases)] + [
        (c, 3) for c in cases[len(cases)//2:] + cases[:len(cases)//2]]
    rows = []
    for case, repeat in plan:
        # Same fixed passage texts and draft, no metadata/human answer expansion.
        premise = "\n\n".join(p["text"] for p in case["evidence"])
        hypothesis = case["draft"]
        started = time.perf_counter()
        encoded = tokenizer.encode(premise, hypothesis)
        row = dict(caseID=case["id"], repeat=repeat, premise=premise,
                   hypothesis=hypothesis, tokenCount=len(encoded.ids),
                   tokenIDsSha256=hashlib.sha256(json.dumps(encoded.ids).encode()).hexdigest(),
                   expected=case["expectedVerdict"], failure=None)
        if len(encoded.ids) > 512:
            row.update(failure="context-overflow-no-truncation", output=None)
        else:
            values = {"input_ids": encoded.ids, "attention_mask": encoded.attention_mask,
                      "token_type_ids": encoded.type_ids}
            feeds = {name: np.array([values[name]], dtype=np.int64) for name in input_names}
            logits = session.run(None, feeds)[0][0]
            assert logits.shape == (3,) and np.isfinite(logits).all()
            probs = np.exp(logits - logits.max())
            probs /= probs.sum()
            row.update(output=LABELS[int(np.argmax(logits))], logits=logits.tolist(),
                       probabilities=probs.tolist())
        row["latencyMs"] = round((time.perf_counter() - started) * 1000, 3)
        rows.append(row)
        print(f"{args.variant} {len(rows)}/{len(plan)} {row['caseID']}: {row['output']}", flush=True)
    positives = [r for r in rows if r["expected"] == "SUPPORTED"]
    negatives = [r for r in rows if r["expected"] != "SUPPORTED"]
    false_approvals = [r for r in negatives if r["output"] == "SUPPORTED"]
    false_rejections = [r for r in positives if not r["failure"] and r["output"] != "SUPPORTED"]
    failures = [r for r in rows if r["failure"]]
    latencies = sorted(r["latencyMs"] for r in rows if not r["failure"])
    mismatches = [dict(caseID=r["caseID"], repeat=r["repeat"], expected=r["expected"],
                       actual=r["output"], failure=r["failure"])
                  for r in rows if r["failure"] or r["output"] != r["expected"]]
    summary = dict(trials=len(rows), supportedTrials=len(positives), unsupportedTrials=len(negatives),
                   falseApprovals=len(false_approvals), falseRejections=len(false_rejections),
                   runtimeOrOverflowFailures=len(failures),
                   exactLabelCorrect=len(rows)-len(mismatches), labelMismatches=mismatches,
                   medianMs=statistics.median(latencies) if latencies else None,
                   firstCallMs=rows[0]["latencyMs"], maxMs=max(latencies) if latencies else None,
                   unstableCaseIDs=[c["id"] for c in cases if len({r["output"] for r in rows
                                       if r["caseID"] == c["id"]}) > 1],
                   developmentTargetMet=not false_approvals and not failures and
                       len(false_rejections)/len(positives) <= .1)
    report = dict(schemaVersion=1, purpose=suite["purpose"], fictional=True, complete=True,
                  suiteID=suite["suiteID"], fixtureSha256=FIXTURE_SHA, variant=args.variant,
                  modelManifest=manifest, runtime=dict(os=platform.platform(),
                    architecture=platform.machine(), python=sys.version,
                    packages={p: importlib.metadata.version(p)
                              for p in ["onnxruntime", "tokenizers", "numpy"]},
                    providers=session.get_providers(), intraOpThreads=2, interOpThreads=1),
                  inputProtocol="Premise=all fixed passage texts, hypothesis=unmodified fixed draft. "
                    "Question/metadata NOT supplied; not a drop-in question-aware verifier. "
                    "No oracle rewriting or truncation; argmax labels, no tuned threshold.",
                  loadMs=round(load_ms, 3),
                  processPeakRSSBytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss *
                    (1 if sys.platform == "darwin" else 1024),
                  memoryCaveat="Whole fresh Python process peak including hashing/loading files; "
                    "not isolated inference RAM and not iPhone memory.",
                  scriptSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  results=rows, grades=summary)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()

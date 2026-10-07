"""Serial, offline collection only. Does not automatically grade model answers."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", choices=["qwen", "smol"])
    args = parser.parse_args()
    suite_path = HERE / "development-v1.json"
    suite = json.loads(suite_path.read_text())
    if suite["context"] != 2048 or suite["output_cap"] != 128:
        raise ValueError("Baseline adapters require context 2048 and output cap 128")
    if len({case["id"] for case in suite["cases"]}) != len(suite["cases"]):
        raise ValueError("Duplicate case IDs")
    text = args.model == "qwen"
    generation = ROOT / "experiments/local_generation"
    vision = ROOT / "experiments/local_vision"
    binary = (generation / ".build/release/local-generation-eval" if text
              else vision / ".build/local-vision-eval")
    if not binary.is_file():
        raise FileNotFoundError(f"Build the existing harness first: {binary}")
    if text and json.dumps(suite["text_system"]) not in (
        generation / "Sources/EvaluationCLI/main.swift"
    ).read_text():
        raise ValueError("Baseline system instruction differs from the suite")
    parent = HERE / "results"
    parent.mkdir(exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix=f"{args.model}-", dir=parent))
    manifest = {"suite": suite["version"], "suite_sha256": sha256(suite_path),
                "binary_sha256": sha256(binary), "model": args.model,
                "grading": "pending manual review", "cases": []}
    (output / "suite.json").write_text(suite_path.read_text())
    for case in suite["cases"]:
        if case["modality"] != ("text" if text else "vision"):
            continue
        case_id = case["id"]
        if not case_id or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in case_id):
            raise ValueError("Unsafe case ID")
        report = output / f"{case_id}.json"
        entry = {"id": case_id, "report": report.name}
        if text:
            prompt = output / f"{case_id}.txt"
            prompt.write_text(case["prompt"], encoding="utf-8")
            command = [str(binary), "--model", str(generation / "artifacts/Qwen3-0.6B-Q8_0.gguf"),
                       "--prompt-file", str(prompt), "--context", "2048", "--output", "128"]
        else:
            image = ROOT / case["image"]
            entry["image_sha256"] = sha256(image)
            command = [str(binary), str(vision / "artifacts/SmolVLM-500M-Instruct-Q8_0.gguf"),
                       str(vision / "artifacts/mmproj-SmolVLM-500M-Instruct-Q8_0.gguf"),
                       str(image), case["prompt"], str(report)]
        print(f"Running {case_id}", flush=True)
        stdout = report if text else output / f"{case_id}.stdout.txt"
        with stdout.open("wb") as out, (output / f"{case_id}.stderr.txt").open("wb") as err:
            try:
                result = subprocess.run(command, cwd=ROOT, stdout=out, stderr=err, timeout=120)
                entry["exit_code"] = result.returncode
            except subprocess.TimeoutExpired:
                entry["timeout_seconds"] = 120
        # Record malformed/missing outputs as failed collection, never as quality passes.
        try:
            json.loads(report.read_text())
            entry["valid_report_json"] = True
        except (OSError, ValueError):
            entry["valid_report_json"] = False
        manifest["cases"].append(entry)
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(output, flush=True)
    if any(item.get("exit_code") != 0 or not item["valid_report_json"] for item in manifest["cases"]):
        raise SystemExit(1)


if __name__ == "__main__":
    main()

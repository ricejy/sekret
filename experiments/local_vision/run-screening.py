"""Run the frozen photo screening suite through the Gemma vision profile.

Each case runs in its own process with a timeout. Image hashes are checked
against the frozen suite before any inference; failures are retained and do not
stop later cases. Grading is manual.

    python3 -I experiments/local_vision/run-screening.py
"""

import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

VISION = Path(__file__).resolve().parent
SUITE_DIR = VISION.parent / "photo_screening"
SUITE = SUITE_DIR / "screening-v1.json"
EXPECTED_SUITE_SHA256 = "2f396f76d91af8acac7865fc2b992425aebc50a8c6e69d64d8db3b3628e7190c"
EVAL = VISION / ".build" / "local-vision-eval"
MODEL = VISION / "artifacts" / "gemma" / "gemma-4-E2B_q4_0-it.gguf"
PROJECTOR = VISION / "artifacts" / "gemma" / "gemma-4-E2B-it-mmproj.gguf"
TIMEOUT_SECONDS = 180


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if sha256(SUITE) != EXPECTED_SUITE_SHA256:
        sys.exit("Suite differs from the frozen screening-v1.json")
    suite = json.loads(SUITE.read_text())
    for case in suite["cases"]:
        if sha256(SUITE_DIR / case["image"]) != case["image_sha256"]:
            sys.exit(f"Frozen image hash mismatch: {case['id']}")
    run_dir = VISION / "results" / f"gemma-screening-v1-{time.strftime('%Y%m%d-%H%M%S')}"
    run_dir.mkdir(parents=True)
    (run_dir / "suite-sha256.txt").write_text(sha256(SUITE) + "\n")
    summary = []
    for case in suite["cases"]:
        result = run_dir / f"{case['id']}.json"
        command = [str(EVAL), "--gemma", "--system", suite["system"], str(MODEL), str(PROJECTOR),
                   str(SUITE_DIR / case["image"]), case["question"], str(result)]
        started = time.monotonic()
        try:
            done = subprocess.run(command, capture_output=True, text=True, timeout=TIMEOUT_SECONDS)
            status, stdout, stderr = done.returncode, done.stdout, done.stderr
        except subprocess.TimeoutExpired as error:
            status, stdout, stderr = "timeout", error.stdout or "", error.stderr or ""
        (run_dir / f"{case['id']}.log").write_text(f"{stderr}" if isinstance(stderr, str) else stderr.decode())
        response = json.loads(result.read_text())["response"] if result.exists() else None
        summary.append({"id": case["id"], "category": case["category"], "status": status,
                        "seconds": round(time.monotonic() - started, 2), "response": response})
        print(f"{case['id']:22} {status!s:8} {response!r}", flush=True)
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n")
    print(run_dir)


if __name__ == "__main__":
    main()

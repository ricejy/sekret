"""Bounded offline development runner; unique immutable run directory."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
suite_path = root / "experiments/model_comparison/development-v1.json"
suite_bytes = suite_path.read_bytes()
suite = json.loads(suite_bytes)
if suite["context"] != 2048 or suite["output_cap"] != 128:
    raise ValueError("This adapter requires exactly 2048 context and 128 output cap")
base = root / "experiments/local_vision"
(base / "results").mkdir(exist_ok=True)
run = Path(tempfile.mkdtemp(prefix="liquid-development-v1-", dir=base / "results"))
(run / "suite.json").write_bytes(suite_bytes)
binary = base / ".build/local-vision-eval"
manifest = {"suite_sha256": hashlib.sha256(suite_bytes).hexdigest(),
            "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
            "timeout_seconds": 120, "cases": []}
(run / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(run, flush=True)
for case in suite["cases"]:
    if case["modality"] != "vision":
        continue
    result = run / (case["id"] + ".json")
    command = [str(base / ".build/local-vision-eval"), "--liquid",
               str(base / "artifacts/liquid/LFM2.5-VL-1.6B-Q8_0.gguf"),
               str(base / "artifacts/liquid/mmproj-LFM2.5-VL-1.6b-Q8_0.gguf"),
               str(root / case["image"]), case["prompt"], str(result)]
    entry = {"id": case["id"], "command": command}
    with (run / (case["id"] + ".stdout")).open("xb") as stdout, (run / (case["id"] + ".runtime.log")).open("xb") as stderr:
        try:
            completed = subprocess.run(command, stdout=stdout, stderr=stderr, timeout=120, check=False)
            entry.update(status="completed" if completed.returncode == 0 and result.exists() else "failed", returncode=completed.returncode)
        except subprocess.TimeoutExpired:
            entry.update(status="timeout")
        except OSError as error:
            entry.update(status="launch-error", detail=str(error))
    manifest["cases"].append(entry)
    (run / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(entry), flush=True)
raise SystemExit(0 if all(c["status"] == "completed" for c in manifest["cases"]) else 1)

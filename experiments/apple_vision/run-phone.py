"""Install the Apple vision probe on the selected phone, run the frozen suite, copy reports.

Replaces the earlier `com.ricejy.sekret.localeval` test app in place (free-profile
app limit); its Documents are copied to results/ first. Never touches Sekret.

    python3 -I experiments/apple_vision/run-phone.py --device <CoreDevice UDID> \
        [--skip-install] [--suite v1|v2] [--instructions-file path] [--decline-counts]
"""

import argparse
import json
import re
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BUNDLE = "com.ricejy.sekret.localeval"
APP = ROOT / "ios/build/Build/Products/Release-iphoneos/SekretVisionEval.app"
REMOTE = "Documents/VisionReports"
# Sekret-side rule: count questions get Sekret's fixed decline, decided from the question text alone.
COUNT_PATTERN = re.compile(r"\bhow\s+many\b|\bcount\b|\bthe\s+number\s+of\b", re.IGNORECASE)
COUNT_DECLINE = ("Sekret doesn't count objects in photos yet, because counts from images aren't reliable. "
                 "You can ask what the objects look like or where they are.")


def device(*args, timeout=120):
    result = subprocess.run(["xcrun", "devicectl", "device", *args], capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True)
    parser.add_argument("--skip-install", action="store_true",
                        help="Reuse the installed, already-verified build (e.g. while offline)")
    parser.add_argument("--suite", choices=["v1", "v2"], default="v1")
    parser.add_argument("--instructions-file", type=Path,
                        help="System instructions to use instead of the suite's own (required for v2)")
    parser.add_argument("--decline-counts", action="store_true",
                        help="Replace answers to count questions with Sekret's fixed decline (raw output kept)")
    args = parser.parse_args()
    extra = ["--suite", args.suite]
    if args.instructions_file:
        extra += ["--instructions", args.instructions_file.read_text().strip()]
    elif args.suite == "v2":
        parser.error("v2 requires --instructions-file")
    results = ROOT / "results"
    results.mkdir(exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix=f"phone-{args.suite}-{time.strftime('%Y%m%d-%H%M%S')}-", dir=results))
    container = ["--domain-type", "appDataContainer", "--domain-identifier", BUNDLE]

    def inventory(subdirectory, missing_ok=True):
        """Names in a container directory. A missing directory is empty only when missing_ok."""
        destination = root / "inventory.json"
        try:
            device("info", "files", "--device", args.device, "--subdirectory", subdirectory, "--no-recurse",
                   *container, "--json-output", str(destination), "--quiet")
        except RuntimeError:
            if missing_ok:
                return set()
            raise
        return {item["name"] for item in json.loads(destination.read_text())["result"]["files"]}

    if not args.skip_install and inventory("Documents", missing_ok=False):
        device("copy", "from", "--device", args.device, "--source", "Documents",
               "--destination", str(root / "prior-documents"), *container, timeout=600)
        print(f"Backed up prior test-app Documents to {root / 'prior-documents'}")
    if not args.skip_install:
        device("install", "app", "--device", args.device, str(APP), timeout=600)
    prior = inventory(REMOTE)
    device("process", "launch", "--device", args.device, "--terminate-existing", BUNDLE, "--screening-suite", *extra)
    deadline = time.monotonic() + 30 * 60
    while time.monotonic() < deadline:
        time.sleep(10)
        fresh = sorted(inventory(REMOTE) - prior)
        if len(fresh) > 1:
            raise RuntimeError("Ambiguous new report directories; refusing to merge runs.")
        if not fresh:
            continue
        names = inventory(f"{REMOTE}/{fresh[0]}")
        print(f"{len(names)} report files so far", flush=True)
        if not {"suite-complete.json", "suite-failed.json"} & names:
            continue
        run = root / "reports" / fresh[0]
        device("copy", "from", "--device", args.device, "--source", f"{REMOTE}/{fresh[0]}",
               "--destination", str(run), *container, timeout=300)
        if args.decline_counts:
            for path in run.glob("*.json"):
                report = json.loads(path.read_text())
                if "question" in report and COUNT_PATTERN.search(report["question"]):
                    report.update(model_response=report.get("response"), response=COUNT_DECLINE,
                                  declined_by="count-rule")
                    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
            (root / "sekret-rules.json").write_text(json.dumps(
                {"count_pattern": COUNT_PATTERN.pattern, "count_decline": COUNT_DECLINE}, indent=2) + "\n")
        for path in sorted(run.glob("*.json")):
            if path.stem in {"environment", "suite-complete", "suite-failed"}:
                print(path.stem, path.read_text())
            else:
                report = json.loads(path.read_text())
                print(f"{report['id']:22} {report['outcome']:9} {report.get('response') or report.get('error')!r}")
        print(run)
        return
    raise RuntimeError("Timed out waiting for the suite to finish")


if __name__ == "__main__":
    main()

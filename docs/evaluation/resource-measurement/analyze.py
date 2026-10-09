"""Align all-process Activity Monitor samples with harness phases.

usage: analyze.py <traces dir> <report.json> <out.json>
"""
import glob, json, os, subprocess, sys, statistics
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone

DEV = {"DEVELOPER_DIR": "/Applications/Xcode copy.app/Contents/Developer"}
# Apple model-serving processes (names are truncated to 31 characters).
SERVING = (
    "TGOnDeviceInferenceProviderServ",
    "GenerativeExperiencesSafetyInfe",
    "generativeexperiencesd",
    "modelmanagerd",
)
APP = "Runner"


def parse_time(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)


def segment(trace):
    env = dict(os.environ, **DEV)
    toc = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--toc"],
                         capture_output=True, text=True, env=env).stdout
    if "<start-date>" not in toc:
        return []
    start = parse_time(toc.split("<start-date>")[1].split("<")[0])
    xml = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--xpath",
                          '/trace-toc/run[@number="1"]/data/table[@schema="activity-monitor-process-live"]'],
                         capture_output=True, text=True, env=env).stdout
    if "<row>" not in xml:
        return []
    root = ET.fromstring(xml)
    ids = {}
    for el in root.iter():
        if "id" in el.attrib:
            ids[el.attrib["id"]] = el
    rows = []
    for row in root.iter("row"):
        cells = [ids.get(c.attrib.get("ref"), c) for c in row]
        t = start + timedelta(microseconds=int(cells[0].text) / 1000)
        name = (cells[1].attrib.get("fmt") or "").rsplit(" (", 1)[0]
        foot, real = cells[10], cells[11]
        if foot.tag != "size-in-bytes" or foot.text is None:
            continue
        resident = int(real.text) if real.tag == "size-in-bytes" and real.text else 0
        rows.append((t, name, int(foot.text), resident))
    return rows


def main(tdir, report_path, out_path):
    report = json.load(open(report_path))
    samples = {}
    for trace in sorted(glob.glob(os.path.join(tdir, "*.trace"))):
        for t, name, foot, _ in segment(trace):
            key = t
            s = samples.setdefault(key, {"app": 0, "serving": 0, "total": 0, "by": {}})
            s["total"] += foot
            if name == APP:
                s["app"] += foot
            if name.startswith(SERVING):
                s["serving"] += foot
                s["by"][name] = s["by"].get(name, 0) + foot
    times = sorted(samples)
    out = {"traceSamples": len(times), "phases": {}}
    for ph in report["phases"]:
        a, b = parse_time(ph["start"]), parse_time(ph.get("end", report["finishedAt"]))
        inside = [samples[t] for t in times if a <= t <= b]
        app_in = [s for s in report.get("samples", []) if a <= parse_time(s["at"]) <= b and (s.get("footprint") or -1) > 0]
        entry = {"traceSamples": len(inside), "appSamples": len(app_in)}
        if inside:
            for k in ("app", "serving", "total"):
                vals = [s[k] for s in inside]
                entry[k] = {"median": statistics.median(vals), "max": max(vals), "min": min(vals)}
            combined = [s["app"] + s["serving"] for s in inside]
            entry["appPlusServing"] = {"median": statistics.median(combined), "max": max(combined)}
            peak = max(inside, key=lambda s: s["app"] + s["serving"])
            entry["servingAtPeak"] = peak["by"]
        if app_in:
            v = [s["footprint"] for s in app_in]
            entry["appSelfReported"] = {"median": statistics.median(v), "max": max(v)}
            entry["thermal"] = sorted({s["thermal"] for s in app_in})
        out["phases"][ph["name"]] = entry

    def inc(work, idle, key):
        w, i = out["phases"].get(work, {}), out["phases"].get(idle, {})
        if key not in w or key not in i:
            return None
        return w[key]["max"] - i[key]["median"]

    out["incremental"] = {
        "apple": {"appPlusServing": inc("apple-general", "idle-before-apple", "appPlusServing"),
                  "total": inc("apple-general", "idle-before-apple", "total")},
        "qwen": {"appPlusServing": inc("qwen-general", "idle-before-qwen", "appPlusServing"),
                 "appSelfReported": inc("qwen-general", "idle-before-qwen", "appSelfReported"),
                 "total": inc("qwen-general", "idle-before-qwen", "total")},
        "photo": {"appPlusServing": inc("photo-repeated", "idle-before-photo", "appPlusServing")},
    }
    json.dump(out, open(out_path, "w"), indent=2, default=str)
    print(json.dumps(out["incremental"], indent=2))
    for k, v in out["phases"].items():
        print(k, v.get("traceSamples"), v.get("appSamples"),
              {m: round(v[m]["max"] / 1e9, 3) for m in ("app", "serving", "total") if m in v},
              v.get("thermal"))


if __name__ == "__main__":
    main(*sys.argv[1:])

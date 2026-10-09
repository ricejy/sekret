"""Reduce one trace to JSON lines of per-sample footprint and resident sums."""
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("a", sys.argv[3]); a = importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
samples = {}
for t, name, foot, real in a.segment(sys.argv[1]):
    s = samples.setdefault(t, {"at": t.isoformat(), "app": 0, "serving": 0, "total": 0,
                               "appReal": 0, "servingReal": 0, "by": {}, "byReal": {}})
    s["total"] += foot
    if name == a.APP:
        s["app"] += foot; s["appReal"] += real
    if name.startswith(a.SERVING):
        s["serving"] += foot; s["servingReal"] += real
        s["by"][name] = s["by"].get(name, 0) + foot
        s["byReal"][name] = s["byReal"].get(name, 0) + real
with open(sys.argv[2], "a") as out:
    for t in sorted(samples): out.write(json.dumps(samples[t]) + "\n")

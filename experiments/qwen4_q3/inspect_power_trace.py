"""Summarize labelled Power Profiler metrics without guessing Swift table columns.

Rates use the explicitly formatted %/hr values (rounded by Instruments), not
an assumed scale for the raw XML number. Incomplete coverage is never a pass.
"""
import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET


def weighted_intervals(intervals, start, end):
    covered = total = 0.0
    last_end = start
    for left, right, value in sorted(intervals):
        left, right = max(left, start), min(right, end)
        if right <= left:
            continue
        if left < last_end - 0.000001:
            raise ValueError('Overlapping power samples; refusing double counting')
        covered += right - left
        total += (right - left) * value
        last_end = right
    return {'durationSeconds': end - start, 'coveredSeconds': covered,
            'coverageFraction': covered / (end - start),
            'meanFormattedPercentPerHour': total / covered if covered else None,
            'fullCoverage': abs(covered - (end - start)) < 0.01}


def analyze(toc_path, power_path, reports):
    toc, power = ET.parse(toc_path).getroot(), ET.parse(power_path).getroot()
    run = toc.find('run')
    origin = datetime.fromisoformat(run.findtext('info/summary/start-date')).timestamp()
    tables = run.findall('data/table')
    ids = {node.get('id'): node for node in power.iter() if node.get('id')}

    def resolve(node):
        return ids[node.get('ref')] if node.get('ref') else node

    rates, samples, thermal, counts, brightness = [], [], [], {}, set()
    for node in power.findall('node'):
        index = int(re.search(r'table\[(\d+)\]', node.get('xpath')).group(1)) - 1
        schema = tables[index].get('schema')
        rows = node.findall('row')
        counts[schema] = len(rows)
        for row in rows:
            fields = [resolve(field) for field in row]
            start = next((f for f in fields if f.tag == 'start-time'), None)
            duration = next((f for f in fields if f.tag == 'duration'), None)
            if start is None or duration is None:
                continue
            left = origin + int(start.text) / 1e9
            right = left + int(duration.text) / 1e9
            if schema == 'SystemPowerLevel':
                rate = next((f for f in fields if f.tag == 'percent-per-hour'), None)
                if rate is None:
                    continue
                match = re.fullmatch(r'(-?\d+(?:\.\d+)?)%/hr', rate.get('fmt', ''))
                if not match:
                    raise ValueError('Unrecognized explicit rate units')
                rates.append((left, right, float(match.group(1))))
                samples.append({'raw': rate.text, 'formatted': rate.get('fmt')})
                brightness.update(f.text for f in fields if f.tag == 'display-brightness')
            elif schema == 'device-thermal-state-intervals':
                state = next((f.text for f in fields if f.tag == 'thermal-state'), None)
                thermal.append({'startUnix': left, 'endUnix': right, 'state': state})
    markers = {p.stem.removeprefix('power-'): json.loads(p.read_text())
               for p in reports.glob('power-*.json')}
    chronological = sorted(markers.values(), key=lambda item: item['unixTime'])
    drift = [abs((right['unixTime'] - left['unixTime']) - (right['uptime'] - left['uptime']))
             for left, right in zip(chronological, chronological[1:])]
    matched = json.loads((reports / 'matched-power-plan.json').read_text()) if (reports / 'matched-power-plan.json').exists() else None
    boundaries = [('baselineBefore', 'baseline-before-start', 'workload-start'),
                              ('workload', 'workload-start', 'baseline-after-start'),
                              ('baselineAfter', 'baseline-after-start', 'baseline-after-end')]
    if matched:
        boundaries = [('baseline', 'matched-baseline-start', 'matched-baseline-end'),
                      ('workload', 'matched-workload-start', 'matched-workload-end')]
    phases = {}
    for name, first, last in boundaries:
        if first in markers and last in markers:
            phases[name] = weighted_intervals(rates, markers[first]['unixTime'], markers[last]['unixTime'])
        else:
            phases[name] = {'fullCoverage': False, 'missingPhaseBoundary': True}
    gate = None
    if 'capture-ready' in markers:
        receipt = json.loads((reports / 'capture-ready.json').read_text())
        release = markers['capture-ready']['unixTime']
        baseline = min((markers[first]['unixTime'] for _, first, _ in boundaries if first in markers), default=None)
        gate = {
            'matchingRunReceipt': receipt.get('runID') == reports.name and receipt.get('captureReady') is True,
            'recordingStartedBeforeRelease': origin < release,
            'waitSeconds': release - markers['attach-wait-start']['unixTime'],
            'settlingSeconds': baseline - release if baseline is not None else None,
            'baselineAfterRelease': baseline is not None and baseline >= release + 10,
        }
    return {'traceStartUnix': origin, 'tableRowCounts': counts, 'phases': phases,
            'matchedPlan': matched, 'reportRunID': reports.name,
            'captureGate': gate,
            'completePowerCoverage': all(p['fullCoverage'] for p in phases.values()),
            'rateUnitSamples': list({(s['raw'], s['formatted']): s for s in samples}.values())[:20],
            'traceBrightnessValues': sorted(brightness), 'thermalTimeline': thermal,
            'maxNativeWallVersusUptimeDeltaSeconds': max(drift, default=None),
            'nativeMarkers': markers,
            'limits': 'Rounded whole-device %/hr, not exact app energy. No extrapolated battery life. Unlabelled app-impact and charging columns are not interpreted. Phase alignment uses device/trace wall clocks; compare marker uptime deltas for clock jumps.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace_directory', type=Path)
    parser.add_argument('reports', type=Path)
    args = parser.parse_args()
    summary = analyze(args.trace_directory / 'toc.xml', args.trace_directory / 'power.xml', args.reports)
    with (args.trace_directory / 'power-summary.json').open('x') as stream:
        json.dump(summary, stream, indent=2)
    print(json.dumps(summary, indent=2))

"""Audit three fixed-duration pairs. Keep failed/incomplete attempts visible.

Input: three power-summary.json files in attempt order, never best-of selections.
No battery-life extrapolation or app-only attribution is performed.
"""
import argparse
import json
from pathlib import Path
from statistics import mean
from inspect_power_trace import weighted_intervals


def audit_pair(summary, expected_order):
    problems = []
    plan = summary.get('matchedPlan') or {}
    if plan.get('version') != 1 or plan.get('phaseSeconds') != 300 or plan.get('turns') != 8 or plan.get('order') != expected_order:
        problems.append('Unexpected protocol/order')
    gate = summary.get('captureGate') or {}
    if not all(gate.get(k) is True for k in ['matchingRunReceipt', 'recordingStartedBeforeRelease', 'baselineAfterRelease']):
        problems.append('Capture readiness not corroborated')
    phases = summary.get('phases', {})
    for name in ['baseline', 'workload']:
        phase = phases.get(name, {})
        if not phase.get('fullCoverage'):
            problems.append(f'{name}: incomplete trace coverage')
        if abs(phase.get('durationSeconds', 0) - 300) > 0.25:
            problems.append(f'{name}: duration outside 300 ±0.25 seconds')
        if phase.get('meanFormattedPercentPerHour') is None:
            problems.append(f'{name}: missing rate, not zero')
        elif phase['meanFormattedPercentPerHour'] <= 0:
            problems.append(f'{name}: zero/negative discharge rate requires investigation, not a low-consumption pass')
    markers = summary.get('nativeMarkers', {})
    if len([k for k in markers if k.startswith('long-chat-') and k.endswith('-end')]) != 8:
        problems.append('Eight terminal turn markers not present')
    required = ['matched-baseline-start', 'matched-baseline-end', 'matched-workload-start', 'matched-workload-end', 'matched-inference-finished']
    if not all(k in markers for k in required):
        problems.append('Missing native phase boundaries')
    else:
        first = 'matched-baseline-start' if expected_order == 'baseline-first' else 'matched-workload-start'
        initial = markers[first]
        if initial.get('thermalState') != 0 or initial.get('batteryLevel', -1) < 0.3:
            problems.append('Pair did not start nominal with at least 30% battery')
        if markers['matched-inference-finished']['unixTime'] > markers['matched-workload-end']['unixTime']:
            problems.append('Inference not contained in workload')
        earlier_end, later_start = ('matched-baseline-end', 'matched-workload-start') if expected_order == 'baseline-first' else ('matched-workload-end', 'matched-baseline-start')
        if markers[earlier_end]['unixTime'] > markers[later_start]['unixTime']:
            problems.append('Phase order mismatch')
    if not markers or any(m.get('batteryState') != 1 or m.get('lowPowerMode') is not False or m.get('batteryLevel', -1) < 0.2 or m.get('thermalState', 99) >= 2 for m in markers.values()):
        problems.append('Native power/thermal conditions failed or missing')
    native_brightness = {m.get('brightness') for m in markers.values()}
    if len(native_brightness) != 1 or None in native_brightness or len(summary.get('traceBrightnessValues', [])) != 1:
        problems.append('Brightness was not constant and corroborated')
    if not summary.get('thermalTimeline') or any(t.get('state') not in ['Nominal', 'Fair'] for t in summary.get('thermalTimeline', [])):
        problems.append('Trace thermals missing or unacceptable')
    for name in ['baseline', 'workload']:
        start, end = markers.get(f'matched-{name}-start', {}).get('unixTime'), markers.get(f'matched-{name}-end', {}).get('unixTime')
        thermal = summary.get('thermalTimeline', [])
        if start is None or end is None or end <= start or not all('startUnix' in t and 'endUnix' in t for t in thermal):
            problems.append(f'{name}: thermal timeline boundaries missing')
        elif not weighted_intervals([(t['startUnix'], t['endUnix'], 1) for t in thermal], start, end)['fullCoverage']:
            problems.append(f'{name}: thermal timeline incomplete')
    if summary.get('maxNativeWallVersusUptimeDeltaSeconds') is None or summary['maxNativeWallVersusUptimeDeltaSeconds'] > 0.1:
        problems.append('Clock alignment not corroborated')
    baseline = phases.get('baseline', {}).get('meanFormattedPercentPerHour')
    workload = phases.get('workload', {}).get('meanFormattedPercentPerHour')
    return {'runID': summary.get('reportRunID'), 'order': expected_order, 'validMeasurement': not problems,
            'problems': problems, 'baselineWholeDevicePercentPerHour': baseline,
            'workloadWholeDevicePercentPerHour': workload,
            'withinPairDifferencePercentagePointsPerHour': workload - baseline if not problems else None,
            'nativeBrightness': list(native_brightness), 'traceBrightness': summary.get('traceBrightnessValues'),
            'firstPhaseUnix': min((markers[k]['unixTime'] for k in required[:4] if k in markers), default=None),
            'lastPhaseUnix': max((markers[k]['unixTime'] for k in required[:4] if k in markers), default=None)}


def aggregate(summaries):
    orders = ['baseline-first', 'workload-first', 'baseline-first']
    pairs = [audit_pair(s, orders[i]) for i, s in enumerate(summaries[:3])]
    problems = []
    if len(summaries) != 3:
        problems.append('Exactly three prespecified attempts required; do not discard failed attempts')
    if len({s.get('reportRunID') for s in summaries}) != len(summaries):
        problems.append('Repeated run ID')
    if pairs and any(p['nativeBrightness'] != pairs[0]['nativeBrightness'] or p['traceBrightness'] != pairs[0]['traceBrightness'] for p in pairs):
        problems.append('Brightness differs between pairs')
    for before, after in zip(pairs, pairs[1:]):
        if before['lastPhaseUnix'] is None or after['firstPhaseUnix'] is None or after['firstPhaseUnix'] - before['lastPhaseUnix'] < 120:
            problems.append('At least 120 seconds between pairs not corroborated')
    valid = not problems and all(p['validMeasurement'] for p in pairs)
    values = [p['withinPairDifferencePercentagePointsPerHour'] for p in pairs] if valid else []
    return {'completeControlledComparison': valid, 'problems': problems, 'pairs': pairs,
            'meanWithinPairDifferencePercentagePointsPerHour': mean(values) if values else None,
            'differenceRange': [min(values), max(values)] if values else None,
            'limits': 'Three short whole-device comparisons on one instrumented phone. Baseline difference is not app energy or predicted battery life. Workload includes eight fixed answers, reading pauses, hashing/loading/export and idle padding. Review native completion/history/lifecycle evidence separately. Prior sustained-load thermal failure remains failed.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('summaries', nargs=3, type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = aggregate([json.loads(p.read_text()) for p in args.summaries])
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2)
    print(json.dumps(result, indent=2))

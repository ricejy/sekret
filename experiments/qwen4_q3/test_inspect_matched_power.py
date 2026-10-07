import copy
import unittest
from inspect_matched_power import aggregate, audit_pair


def fixture(order='baseline-first', run_id='one', origin=0):
    base = {'uptime': 1000, 'batteryState': 1, 'batteryLevel': 0.8, 'lowPowerMode': False, 'thermalState': 0, 'brightness': 1}
    first, second = ('baseline', 'workload') if order == 'baseline-first' else ('workload', 'baseline')
    markers = {}
    for name, start in [(first, 100), (second, 400)]:
        for suffix, time in [('start', start), ('end', start + 300)]:
            markers[f'matched-{name}-{suffix}'] = {**base, 'unixTime': time + origin}
    for i in range(8):
        markers[f'long-chat-{i + 1}-end'] = {**base, 'unixTime': markers['matched-workload-start']['unixTime'] + i * 30}
    markers['matched-inference-finished'] = {**base, 'unixTime': markers['matched-workload-end']['unixTime'] - 20}
    return {'reportRunID': run_id, 'matchedPlan': {'version': 1, 'phaseSeconds': 300, 'turns': 8, 'order': order},
            'captureGate': dict.fromkeys(['matchingRunReceipt', 'recordingStartedBeforeRelease', 'baselineAfterRelease'], True),
            'phases': {k: {'fullCoverage': True, 'durationSeconds': 300, 'meanFormattedPercentPerHour': v} for k, v in [('baseline', 5), ('workload', 15)]},
            'nativeMarkers': markers, 'traceBrightnessValues': ['100'], 'thermalTimeline': [{'state': 'Nominal', 'startUnix': origin, 'endUnix': origin + 800}], 'maxNativeWallVersusUptimeDeltaSeconds': 0.001}


class MatchedTests(unittest.TestCase):
    def test_requires_three_distinct_prespecified_orders(self):
        values = [fixture(run_id='one'), fixture('workload-first', 'two', 1000), fixture(run_id='three', origin=2000)]
        result = aggregate(values)
        self.assertTrue(result['completeControlledComparison'])
        self.assertEqual(result['meanWithinPairDifferencePercentagePointsPerHour'], 10)
        self.assertFalse(aggregate(values[:2])['completeControlledComparison'])
        values[2] = copy.deepcopy(values[0])
        self.assertFalse(aggregate(values)['completeControlledComparison'])

    def test_missing_partial_overlong_or_charging_never_pass(self):
        for fault in ['missing', 'zero', 'partial', 'overlong', 'charging', 'brightness', 'thermal', 'clock', 'gate']:
            value = fixture()
            if fault == 'missing': value['phases']['workload']['meanFormattedPercentPerHour'] = None
            if fault == 'zero': value['phases']['workload']['meanFormattedPercentPerHour'] = 0
            if fault == 'partial': value['phases']['baseline']['fullCoverage'] = False
            if fault == 'overlong': value['phases']['workload']['durationSeconds'] = 301
            if fault == 'charging': value['nativeMarkers']['matched-baseline-end']['batteryState'] = 2
            if fault == 'brightness': value['nativeMarkers']['matched-baseline-end']['brightness'] = 0.5
            if fault == 'thermal': value['thermalTimeline'] = [{'state': 'Serious'}]
            if fault == 'clock': value['maxNativeWallVersusUptimeDeltaSeconds'] = 1
            if fault == 'gate': value['captureGate']['recordingStartedBeforeRelease'] = False
            result = audit_pair(value, 'baseline-first')
            self.assertFalse(result['validMeasurement'], fault)
            self.assertIsNone(result['withinPairDifferencePercentagePointsPerHour'], fault)

    def test_old_unequal_pilot_cannot_be_relabelled(self):
        value = fixture()
        value['matchedPlan'] = None
        self.assertFalse(audit_pair(value, 'baseline-first')['validMeasurement'])

    def test_cooldown_and_thermal_coverage_are_required(self):
        values = [fixture(), fixture('workload-first', 'two', 650), fixture(run_id='three', origin=2000)]
        self.assertFalse(aggregate(values)['completeControlledComparison'])
        value = fixture()
        value['thermalTimeline'][0]['startUnix'] = 101
        self.assertFalse(audit_pair(value, 'baseline-first')['validMeasurement'])


if __name__ == '__main__':
    unittest.main()

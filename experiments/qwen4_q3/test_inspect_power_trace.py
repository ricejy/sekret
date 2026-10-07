import unittest
import tempfile
import json
from pathlib import Path

from inspect_power_trace import analyze, weighted_intervals


class IntervalTests(unittest.TestCase):
    def test_matched_phase_names_and_gate_use_first_measured_phase(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'toc.xml').write_text('<trace-toc><run><info><summary><start-date>2026-10-06T00:00:00Z</start-date></summary></info><data><table schema="SystemPowerLevel"/></data></run></trace-toc>')
            (root / 'power.xml').write_text('<trace-query-result><node xpath="//table[1]"><row><start-time>0</start-time><duration>650000000000</duration><percent-per-hour fmt="10.0%/hr">0.1</percent-per-hour></row></node></trace-query-result>')
            (root / 'matched-power-plan.json').write_text(json.dumps({'version': 1, 'order': 'workload-first'}))
            for phase, offset in [('attach-wait-start', -20), ('capture-ready', 2), ('matched-workload-start', 20), ('matched-workload-end', 320), ('matched-baseline-start', 320), ('matched-baseline-end', 620)]:
                (root / f'power-{phase}.json').write_text(json.dumps({'phase': phase, 'unixTime': 1791244800 + offset, 'uptime': 1000 + offset}))
            (root / 'capture-ready.json').write_text(json.dumps({'runID': root.name, 'captureReady': True}))
            result = analyze(root / 'toc.xml', root / 'power.xml', root)
            self.assertTrue(result['completePowerCoverage'])
            self.assertEqual(set(result['phases']), {'baseline', 'workload'})
            self.assertEqual(result['phases']['baseline']['durationSeconds'], 300)
            self.assertTrue(result['captureGate']['baselineAfterRelease'])
            self.assertEqual(result['captureGate']['settlingSeconds'], 18)

    def test_time_weighting_and_clipping(self):
        result = weighted_intervals([(0, 2, 10), (2, 5, 20)], 1, 4)
        self.assertTrue(result['fullCoverage'])
        self.assertAlmostEqual(result['meanFormattedPercentPerHour'], 50 / 3)

    def test_missing_baseline_is_not_zero_or_pass(self):
        result = weighted_intervals([(2, 5, 10)], 0, 5)
        self.assertFalse(result['fullCoverage'])
        self.assertEqual(result['coverageFraction'], 0.6)
        self.assertEqual(result['meanFormattedPercentPerHour'], 10)
        empty = weighted_intervals([], 0, 5)
        self.assertIsNone(empty['meanFormattedPercentPerHour'])
        self.assertFalse(empty['fullCoverage'])

    def test_overlapping_samples_are_rejected(self):
        with self.assertRaises(ValueError):
            weighted_intervals([(0, 3, 10), (2, 5, 20)], 0, 5)

    def test_global_references_and_unlabelled_columns(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            toc = root / 'toc.xml'
            power = root / 'power.xml'
            toc.write_text('<trace-toc><run><info><summary><start-date>2026-10-06T00:00:00Z</start-date></summary></info><data><table schema="ProcessSubsystemPowerImpact"/><table schema="SystemPowerLevel"/></data></run></trace-toc>')
            power.write_text('''<trace-query-result>
              <node xpath="//table[1]"><row><start-time id="1">0</start-time><duration id="2">1000000000</duration><subsystem-power-impact>999</subsystem-power-impact></row></node>
              <node xpath="//table[2]"><row><start-time ref="1"/><duration ref="2"/><percent-per-hour fmt="12.3%/hr">0.123</percent-per-hour><fixed-decimal>999</fixed-decimal></row></node>
              </trace-query-result>''')
            result = analyze(toc, power, root)
            self.assertEqual(result['rateUnitSamples'], [{'raw': '0.123', 'formatted': '12.3%/hr'}])
            self.assertFalse(result['completePowerCoverage'])
            self.assertEqual(result['tableRowCounts']['ProcessSubsystemPowerImpact'], 1)
            self.assertIsNone(result['captureGate'])
            for phase, timestamp in [('attach-wait-start', 1791244790), ('capture-ready', 1791244802), ('baseline-before-start', 1791244812)]:
                (root / f'power-{phase}.json').write_text(json.dumps({'phase': phase, 'unixTime': timestamp, 'uptime': timestamp - 1000}))
            (root / 'capture-ready.json').write_text(json.dumps({'runID': root.name, 'captureReady': True}))
            gate = analyze(toc, power, root)['captureGate']
            self.assertTrue(gate['matchingRunReceipt'])
            self.assertTrue(gate['recordingStartedBeforeRelease'])
            self.assertTrue(gate['baselineAfterRelease'])
            self.assertEqual(gate['settlingSeconds'], 10)


if __name__ == '__main__':
    unittest.main()

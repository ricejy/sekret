import copy
import unittest

from validate_text_report import validate_report


class ReportContractTests(unittest.TestCase):
    def setUp(self):
        self.profile = {'modelSHA256': 'a' * 64, 'runtimeTag': 'pinned-runtime',
                        'templateVersion': 'candidate-native-template', 'sampling': 'candidate-native-sampler',
                        'context': 2048, 'output_cap': 128}
        self.report = {key: value for key, value in self.profile.items()
                       if key not in ('context', 'output_cap')}
        self.report['runs'] = [{'configuredContext': 2048, 'actualContext': 2048, 'outputCap': 128,
                               'promptTokens': 72, 'outputTokens': 1, 'promptSHA256': 'b' * 64,
                               'tokenIDsSHA256': 'c' * 64, 'response': 'wrong answer', 'outcome': 'completed'}]

    def test_completed_report_does_not_claim_quality(self):
        result = validate_report(self.report, self.profile)
        self.assertTrue(result['complete'])
        self.assertEqual(result['quality'], 'requires manual grading')

    def test_old_model_template_sampler_or_runtime_cannot_silently_pass(self):
        for key in ('modelSHA256', 'runtimeTag', 'templateVersion', 'sampling'):
            with self.subTest(key=key):
                report = copy.deepcopy(self.report)
                report[key] = 'previous-candidate-value'
                with self.assertRaises(ValueError):
                    validate_report(report, self.profile)

    def test_budget_change_or_hidden_overflow_is_rejected(self):
        for key, value in [('outputCap', 512), ('configuredContext', 4096),
                           ('actualContext', 1024), ('promptTokens', 2000), ('outputTokens', 129)]:
            with self.subTest(key=key):
                report = copy.deepcopy(self.report)
                report['runs'][0][key] = value
                with self.assertRaises(ValueError):
                    validate_report(report, self.profile)

    def test_incomplete_output_is_evidence_not_completion(self):
        for outcome in ('output-limit', 'cancelled'):
            self.report['runs'][0]['outcome'] = outcome
            self.assertFalse(validate_report(self.report, self.profile)['complete'])

    def test_missing_native_token_hash_fails(self):
        self.report['runs'][0].pop('tokenIDsSHA256')
        with self.assertRaises(ValueError):
            validate_report(self.report, self.profile)


if __name__ == '__main__':
    unittest.main()

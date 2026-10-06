"""Model-free tests of the broader evaluation collector."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

import run_development as runner


class RunnerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        binary = self.root / '.build/release/LiquidCLI'
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b'fake executable: never launched')
        self.suite_path = self.root / 'suite.json'
        self.suite = {
            'context': 2048, 'output_cap': 128,
            'text_system': "You are a concise on-device assistant. Answer the user's request directly. This is an evaluation using fictional data.",
            'qualification': 'unit-test',
            'cases': [{'id': 'one', 'modality': 'text', 'prompt': 'Fictional test',
                       'required': ['answer'], 'forbidden': []}],
        }

    def collect(self, fake):
        self.suite_path.write_text(json.dumps(self.suite))
        model = MagicMock()
        model.stat.return_value = SimpleNamespace(st_size=730895168)
        real_digest = runner.digest
        def digest(path):
            return runner.EXPECTED if path is model else real_digest(path)
        with patch.object(runner, 'HERE', self.root), \
             patch.object(runner, 'MODEL', model), \
             patch.object(runner, 'digest', side_effect=digest), \
             patch.object(runner.shutil, 'disk_usage', return_value=SimpleNamespace(free=3*1024**3)), \
             patch.object(sys, 'argv', ['run_development.py', '--suite', str(self.suite_path)]), \
             patch.object(runner.subprocess, 'run', side_effect=fake), \
             contextlib.redirect_stdout(io.StringIO()):
            runner.main()

    def manifest(self):
        return json.loads(next((self.root / 'results').glob('*/manifest.json')).read_text())

    def test_success_records_terminal_outcome_and_frozen_suite(self):
        def fake(command, **kwargs):
            self.assertEqual(kwargs['timeout'], 120)
            self.assertNotIn('shell', kwargs)
            kwargs['stdout'].write(b'{"runs":[{"response":"answer","outcome":"completed"}]}')
            return subprocess.CompletedProcess(command, 0)
        self.collect(fake)
        case = self.manifest()['cases'][0]
        self.assertTrue(case['valid_report'])
        self.assertEqual(case['outcome'], 'completed')
        self.assertEqual(len(case['report_sha256']), 64)
        self.assertTrue(list((self.root / 'results').glob('*/suite.json')))

    def test_timeout_does_not_hide_following_failure(self):
        self.suite['cases'].append(dict(self.suite['cases'][0], id='two'))
        calls = []
        def fake(command, **kwargs):
            calls.append(command)
            if len(calls) == 1:
                raise subprocess.TimeoutExpired(command, 120)
            kwargs['stdout'].write(b'broken report')
            return subprocess.CompletedProcess(command, 7)
        with self.assertRaises(SystemExit):
            self.collect(fake)
        cases = self.manifest()['cases']
        self.assertEqual([case['status'] for case in cases], ['timeout', 7])
        self.assertFalse(any(case['valid_report'] for case in cases))

    def test_output_limit_is_not_success(self):
        def fake(command, **kwargs):
            kwargs['stdout'].write(b'{"runs":[{"response":"partial","outcome":"output-limit"}]}')
            return subprocess.CompletedProcess(command, 0)
        with self.assertRaises(SystemExit):
            self.collect(fake)
        self.assertEqual(self.manifest()['cases'][0]['outcome'], 'output-limit')

    def test_unsafe_case_id_is_rejected_before_launch(self):
        self.suite['cases'][0]['id'] = '../escape'
        with self.assertRaises(ValueError):
            self.collect(lambda *args, **kwargs: self.fail('must not launch'))
        self.assertFalse((self.root / 'results').exists())

    def test_fixed_configuration_cannot_change_silently(self):
        self.suite['output_cap'] = 512
        with self.assertRaises(ValueError):
            self.collect(lambda *args, **kwargs: self.fail('must not launch'))


if __name__ == '__main__':
    unittest.main()

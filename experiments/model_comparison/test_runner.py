"""Collector tests use fake subprocesses, never model weights or inference."""

import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import run_baseline


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.here = self.root / "experiments/model_comparison"
        self.here.mkdir(parents=True)
        generation = self.root / "experiments/local_generation"
        binary = generation / ".build/release/local-generation-eval"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"never executed")
        source = generation / "Sources/EvaluationCLI/main.swift"
        source.parent.mkdir(parents=True)
        source.write_text('let system = "Test system"')
        self.suite = {"version": "test", "context": 2048, "output_cap": 128,
                      "text_system": "Test system", "cases": [
                          {"id": "one", "modality": "text", "prompt": "Fictional test"}]}
        self.write_suite()

    def write_suite(self):
        (self.here / "development-v1.json").write_text(json.dumps(self.suite))

    def collect(self, fake):
        with patch.object(run_baseline, "HERE", self.here), \
             patch.object(run_baseline, "ROOT", self.root), \
             patch.object(sys, "argv", ["run_baseline.py", "qwen"]), \
             patch.object(run_baseline.subprocess, "run", side_effect=fake), \
             contextlib.redirect_stdout(io.StringIO()):
            run_baseline.main()

    def manifest(self):
        return json.loads(next((self.here / "results").glob("*/manifest.json")).read_text())

    def test_records_success_without_grading(self):
        def fake(command, **kwargs):
            self.assertIsInstance(command, list)
            self.assertNotIn("shell", kwargs)
            self.assertEqual(kwargs["timeout"], 120)
            self.assertEqual(command[-4:], ["--context", "2048", "--output", "128"])
            kwargs["stdout"].write(b'{"runs": [{"outcome": "completed", "response": "hello"}]}')
            return subprocess.CompletedProcess(command, 0)
        self.collect(fake)
        manifest = self.manifest()
        self.assertEqual(manifest["grading"], "pending manual review")
        self.assertTrue(manifest["cases"][0]["valid_report_json"])
        self.assertEqual(len(manifest["suite_sha256"]), 64)

    def test_nonzero_and_malformed_report_are_retained(self):
        def fake(command, **kwargs):
            kwargs["stdout"].write(b"not JSON")
            return subprocess.CompletedProcess(command, 7)
        with self.assertRaises(SystemExit):
            self.collect(fake)
        case = self.manifest()["cases"][0]
        self.assertEqual(case["exit_code"], 7)
        self.assertFalse(case["valid_report_json"])

    def test_timeout_is_retained(self):
        def fake(command, **kwargs):
            raise subprocess.TimeoutExpired(command, 120)
        with self.assertRaises(SystemExit):
            self.collect(fake)
        case = self.manifest()["cases"][0]
        self.assertEqual(case["timeout_seconds"], 120)
        self.assertNotIn("exit_code", case)

    def test_changed_fixed_configuration_is_rejected(self):
        self.suite["output_cap"] = 512
        self.write_suite()
        with self.assertRaises(ValueError):
            self.collect(lambda *args, **kwargs: self.fail("must not launch"))
        self.assertFalse((self.here / "results").exists())


if __name__ == "__main__":
    unittest.main()

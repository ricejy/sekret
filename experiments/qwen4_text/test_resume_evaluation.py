import subprocess
import sys
import unittest
from unittest.mock import patch
from resume_evaluation import guarded_run


class GuardTests(unittest.TestCase):
    def test_low_disk_never_launches(self):
        with patch('resume_evaluation.subprocess.Popen') as launch:
            result = guarded_run(['unused'], None, None, free_bytes=lambda: 0)
        launch.assert_not_called()
        self.assertEqual(result['stop_reason'], 'disk_reserve_before_launch')

    def test_normal_exit(self):
        result = guarded_run([sys.executable, '-c', 'pass'], subprocess.DEVNULL,
                             subprocess.DEVNULL, free_bytes=lambda: 10**12)
        self.assertEqual(result['exit_code'], 0)
        self.assertNotIn('stop_reason', result)

    def test_timeout_stops_owned_child(self):
        result = guarded_run([sys.executable, '-c', 'import time; time.sleep(10)'],
                             subprocess.DEVNULL, subprocess.DEVNULL,
                             free_bytes=lambda: 10**12, timeout=0.1)
        self.assertEqual(result['stop_reason'], 'timeout')
        self.assertIsNotNone(result['exit_code'])

    def test_disk_drop_stops_owned_child(self):
        readings = iter([10**12, 0])
        result = guarded_run([sys.executable, '-c', 'import time; time.sleep(10)'],
                             subprocess.DEVNULL, subprocess.DEVNULL,
                             free_bytes=lambda: next(readings))
        self.assertEqual(result['stop_reason'], 'disk_reserve_during_run')
        self.assertIsNotNone(result['exit_code'])


if __name__ == '__main__':
    unittest.main()

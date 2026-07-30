#!/usr/bin/env python3
"""Regression tests for strict GDScript process-result classification."""

import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "run_gdscript_tests.py"
SPEC = importlib.util.spec_from_file_location("run_gdscript_tests", MODULE_PATH)
assert SPEC and SPEC.loader
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class ResultClassificationTests(unittest.TestCase):
    """Verify every documented process and diagnostic classification."""

    def test_zero_exit_with_clean_output_passes(self) -> None:
        self.assertFalse(RUNNER.classify_result(0, "Godot Engine\n").failed)

    def test_nonzero_exit_fails(self) -> None:
        self.assertTrue(RUNNER.classify_result(2, "failed\n").failed)

    def test_script_error_with_zero_exit_fails(self) -> None:
        self.assertTrue(RUNNER.classify_result(0, "SCRIPT ERROR: invalid call\n").failed)

    def test_engine_error_with_zero_exit_fails(self) -> None:
        self.assertTrue(RUNNER.classify_result(0, "ERROR: invalid state\n").failed)

    def test_timeout_reports_first_causal_error(self) -> None:
        outcome = RUNNER.classify_result(124, "SCRIPT ERROR: assertion stopped cleanup\n", True, 60)
        self.assertTrue(outcome.failed)
        self.assertIn("SCRIPT ERROR: assertion stopped cleanup", outcome.message)

    def test_ordinary_warning_only_passes(self) -> None:
        self.assertFalse(RUNNER.classify_result(0, "WARNING: fallback renderer active\n").failed)

    def test_leak_error_fails(self) -> None:
        self.assertTrue(RUNNER.classify_result(0, "ERROR: 3 RID allocations were leaked at exit.\n").failed)


if __name__ == "__main__":
    unittest.main()

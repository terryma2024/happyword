import subprocess
import sys
import unittest


class CliSmokeTest(unittest.TestCase):
    def test_module_help_prints_commands(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "tools.gap_detector", "--help"],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("plan", result.stdout)
        self.assertIn("run", result.stdout)
        self.assertIn("classify", result.stdout)


if __name__ == "__main__":
    unittest.main()

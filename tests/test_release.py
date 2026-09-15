#!/usr/bin/env python3
"""Release identity and installed-copy checks, using isolated data directories."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

from test_compat import ShimSandbox

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("SHIM_TEST_BASH", "/bin/bash")


class ReleaseTests(unittest.TestCase):
    def test_version_is_semantic(self):
        self.assertTrue((ROOT / "VERSION").is_file(), "release VERSION is missing")
        self.assertRegex((ROOT / "VERSION").read_text(), r"^\d+\.\d+\.\d+\n$")

    def test_installer_reports_project_version_without_writes(self):
        with tempfile.TemporaryDirectory(prefix="zct release ") as tmp:
            env = {**os.environ, "XDG_DATA_HOME": tmp}
            p = subprocess.run([BASH, str(ROOT / "install.sh"), "--version"], env=env,
                               text=True, capture_output=True, timeout=10)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertEqual(list(Path(tmp).iterdir()), [], "--version performed an installation")
            self.assertEqual(p.stdout, "zellij-claude-teams " + (ROOT / "VERSION").read_text())

    def test_installed_version_and_runtime_match(self):
        with tempfile.TemporaryDirectory(prefix="zct install ") as tmp:
            env = {**os.environ, "XDG_DATA_HOME": tmp}
            p = subprocess.run([BASH, str(ROOT / "install.sh")], env=env,
                               text=True, capture_output=True, timeout=10)
            self.assertEqual(p.returncode, 0, p.stderr)
            installed = Path(tmp) / "zellij-tmux-shim"
            for name in ["VERSION", "activate.sh", "deactivate.sh", "bin/tmux", "bin/zellij-pane-wrapper"]:
                self.assertTrue((installed / name).is_file(), name + " missing from installation")
                self.assertEqual((installed / name).read_bytes(), (ROOT / name).read_bytes(), name)
            for name in ["bin/tmux", "bin/zellij-pane-wrapper"]:
                self.assertTrue(os.access(installed / name, os.X_OK), name)
            self.assertFalse((installed / "tests").exists())

    def test_tmux_version_remains_protocol_identity(self):
        with tempfile.TemporaryDirectory(prefix="zct version ") as tmp:
            env = {**os.environ, "ZELLIJ_TMUX_SHIM_STATE": tmp, "ZELLIJ_TMUX_SHIM_DIR": str(ROOT)}
            p = subprocess.run([BASH, str(ROOT / "bin/tmux"), "-V"], env=env,
                               text=True, capture_output=True, timeout=10)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertEqual(p.stdout, "tmux 3.6a\n")

    def test_installed_shebang_runs_deferred_protocol(self):
        with mock.patch.dict(os.environ, {"SHIM_TEST_BASH": BASH}):
            sandbox = ShimSandbox()
        try:
            data = sandbox.root / "installed data"
            p = subprocess.run([BASH, str(ROOT / "install.sh")],
                               env={**sandbox.env, "XDG_DATA_HOME": str(data)},
                               text=True, capture_output=True, timeout=10)
            self.assertEqual(p.returncode, 0, p.stderr)
            installed = data / "zellij-tmux-shim"
            sandbox.env["ZELLIJ_TMUX_SHIM_DIR"] = str(installed)
            executable = str(installed / "bin/tmux")
            created = subprocess.run([executable, "split-window", "-P", "--", "cat"],
                                     env=sandbox.env, text=True, capture_output=True, timeout=10)
            self.assertEqual((created.returncode, created.stdout), (0, "%1\n"), created.stderr)
            self.assertTrue((sandbox.state / "1.fifo").is_fifo())
            command = 'printf installed > "$SHIM_TEST_ROOT/installed-result"; sleep 60'
            launched = subprocess.run([executable, "respawn-pane", "-t", "%1", "--", command],
                                      env=sandbox.env, text=True, capture_output=True, timeout=10)
            self.assertEqual(launched.returncode, 0, launched.stderr)
            self.assertEqual(sandbox.wait_text(sandbox.root / "installed-result"), "installed")
            creations = [a["argv"] for a in sandbox.actions(False) if a["argv"][:2] == ["action", "new-pane"]]
            self.assertEqual(len(creations), 1)
            self.assertIn(str(installed / "bin/zellij-pane-wrapper"), creations[0])
        finally:
            sandbox.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)

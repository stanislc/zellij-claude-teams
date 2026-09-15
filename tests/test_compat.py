#!/usr/bin/env python3
"""Maintained core compatibility regressions for the tmux shim."""

import argparse
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[1]
TMUX = REPO / "bin" / "tmux"
DEACTIVATE = REPO / "deactivate.sh"
FAKE_ZELLIJ = REPO / "tests" / "helpers" / "fake_zellij.py"


class ShimSandbox:
    def __init__(self):
        selected_bash = os.environ.get("SHIM_TEST_BASH", "")
        if not selected_bash or not os.path.isabs(selected_bash):
            raise RuntimeError("SHIM_TEST_BASH must name an absolute Bash binary")
        self.bash = selected_bash
        self.temp = tempfile.TemporaryDirectory(prefix="zellij-shim-core-")
        self.root = Path(self.temp.name)
        self.root.chmod(0o700)
        self.runtime = self.root / "runtime"
        self.runtime.mkdir(mode=0o700)
        self.state = self.runtime / f"zellij-tmux-shim-{os.getuid()}" / "core-session"
        self.state.mkdir(mode=0o700, parents=True)
        (self.state / "next_id").write_text("1\n", encoding="ascii")
        (self.state / "sessions").touch()
        self.fake_bin = self.root / "bin"
        self.fake_bin.mkdir()
        (self.fake_bin / "zellij").symlink_to(FAKE_ZELLIJ)
        python_dir = str(Path(sys.executable).resolve().parent)
        self.env = {
            "PATH": os.pathsep.join(
                [str(self.fake_bin), python_dir, "/opt/homebrew/bin", "/usr/bin", "/bin"]
            ),
            "SHIM_TEST_BASH": self.bash,
            "SHIM_TEST_ROOT": str(self.root),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "ZELLIJ_SESSION_NAME": "core-session",
            "ZELLIJ_TMUX_SHIM_STATE": str(self.state),
            "ZELLIJ_TMUX_SHIM_DIR": str(REPO),
            "ZELLIJ_PANE_ID": "10",
            "TMUX_PANE": "%0",
        }
        self.local_processes = []

    def call(self, *args, issuer=None, timeout=8, extra_env=None):
        env = self.env.copy()
        if issuer is not None:
            env["ZELLIJ_PANE_ID"] = str(issuer)
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [self.bash, str(TMUX), *args],
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )

    def actions(self, include_help=True):
        log = self.root / "zellij-actions.jsonl"
        if not log.exists():
            return []
        actions = [json.loads(line) for line in log.read_text().splitlines()]
        if include_help:
            return actions
        return [action for action in actions if "--help" not in action["argv"]]

    def wait_text(self, path, timeout=3):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if path.exists():
                return path.read_text(encoding="utf-8")
            time.sleep(0.02)
        self_test = self
        raise AssertionError(f"timed out waiting for {path}; actions={self_test.actions()}")

    def add_live_record(self, pane_key="1", zellij_id="101"):
        child = subprocess.Popen(
            [self.bash, "-c", "sleep 60"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        self.local_processes.append(child.pid)
        (self.state / f"{pane_key}.pid").write_text(f"{child.pid}\n", encoding="ascii")
        (self.state / f"{pane_key}.zellij_id").write_text(
            f"{zellij_id}\n", encoding="ascii"
        )
        return child.pid

    def close(self):
        owned = list(self.local_processes)
        owned_file = self.root / "owned-processes"
        if owned_file.exists():
            for raw_pid in owned_file.read_text(encoding="ascii").splitlines():
                if raw_pid.isdigit():
                    owned.append(int(raw_pid))
        for pid in set(owned):
            try:
                os.killpg(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for pid in set(owned):
            try:
                os.waitpid(pid, 0)
            except (ChildProcessError, ProcessLookupError):
                pass
        self.temp.cleanup()


class CoreCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.shim = ShimSandbox()

    def tearDown(self):
        self.shim.close()

    def test_baseline_cli(self):
        version = self.shim.call("-V")
        pane = self.shim.call("display-message", "-p", "#{pane_id}")
        self.assertEqual((version.returncode, version.stdout), (0, "tmux 3.6a\n"))
        self.assertEqual((pane.returncode, pane.stdout), (0, "%0\n"))

    def test_deferred_cat_title_and_respawn(self):
        created = self.shim.call(
            "split-window", "-d", "-t", "%0", "-P", "-F", "#{pane_id}", "--", "cat"
        )
        self.assertEqual((created.returncode, created.stdout), (0, "%1\n"))
        self.assertTrue((self.shim.state / "1.fifo").is_fifo())
        self.assertFalse((self.shim.state / "1.named").exists())
        title = self.shim.call("select-pane", "-t", "%1", "-T", "researcher")
        result = self.shim.root / "respawn-result"
        command = f"printf %s respawned > {shlex.quote(str(result))}; sleep 60"
        launched = self.shim.call("respawn-pane", "-k", "-t", "%1", "--", command)
        self.assertEqual((title.returncode, launched.returncode), (0, 0))
        self.assertEqual(self.shim.wait_text(result), "respawned")
        renames = [
            action["argv"]
            for action in self.shim.actions(include_help=False)
            if action["argv"][:2] == ["action", "rename-pane"]
        ]
        self.assertIn(["action", "rename-pane", "--pane-id", "101", "researcher"], renames)

    def test_inline_command_preserves_argv(self):
        result = self.shim.root / "inline-result"
        script = 'printf %s "$1" > "$2"; sleep 60'
        value = "two words & a 'quote'"
        created = self.shim.call(
            "split-window", "-P", "--", self.shim.bash, "-c", script, "driver", value, str(result)
        )
        self.assertEqual((created.returncode, created.stdout), (0, "%1\n"))
        self.assertEqual(self.shim.wait_text(result), value)

    def test_fifo_send_starts_legacy_command(self):
        created = self.shim.call("split-window", "-P")
        result = self.shim.root / "fifo-result"
        command = f"printf %s fifo > {shlex.quote(str(result))}; sleep 60"
        sent = self.shim.call("send-keys", "-t", "%1", command, "Enter")
        self.assertEqual((created.returncode, sent.returncode), (0, 0))
        self.assertEqual(self.shim.wait_text(result), "fifo")

    def test_leader_relative_and_sibling_placement(self):
        first = self.shim.call("split-window", "-P", "--", "cat")
        second = self.shim.call("split-window", "-P", "--", "cat")
        other = self.shim.call("split-window", "-P", "--", "cat", issuer=20)
        self.assertEqual([first.stdout, second.stdout, other.stdout], ["%1\n", "%2\n", "%3\n"])
        creations = [
            action
            for action in self.shim.actions(include_help=False)
            if action["argv"][:2] == ["action", "new-pane"]
        ]
        self.assertEqual([action["issuer"] for action in creations], ["10", "101", "20"])
        self.assertTrue(all("--no-focus" in action["argv"] for action in creations))
        self.assertIn("right", creations[0]["argv"])
        self.assertIn("down", creations[1]["argv"])
        self.assertIn("right", creations[2]["argv"])

    def test_legacy_new_window_preserves_creation_name(self):
        created = self.shim.call(
            "new-window",
            "-P",
            "-n",
            "named-agent",
            "--",
            "cat",
            extra_env={"SHIM_TEST_CAP_NEW_PANE": "0", "SHIM_TEST_CAP_RENAME_PANE": "0"},
        )
        self.assertEqual((created.returncode, created.stdout), (0, "%1\n"))
        creations = [
            action["argv"]
            for action in self.shim.actions(include_help=False)
            if action["argv"][:2] == ["action", "new-pane"]
        ]
        self.assertEqual(len(creations), 1)
        name_index = creations[0].index("-n")
        self.assertEqual(creations[0][name_index + 1], "named-agent")

    def test_write_capability_is_independent_and_targeted(self):
        result = self.shim.root / "running"
        command = f"printf %s running > {shlex.quote(str(result))}; sleep 60"
        created = self.shim.call(
            "split-window",
            "-P",
            "--",
            self.shim.bash,
            "-c",
            command,
            extra_env={"SHIM_TEST_CAP_NEW_PANE": "0", "SHIM_TEST_CAP_RENAME_PANE": "0"},
        )
        self.assertEqual(created.returncode, 0)
        self.assertEqual(self.shim.wait_text(result), "running")
        sent = self.shim.call(
            "send-keys",
            "-t",
            "%1",
            "late text",
            "Enter",
            extra_env={"SHIM_TEST_CAP_NEW_PANE": "0", "SHIM_TEST_CAP_RENAME_PANE": "0"},
        )
        self.assertEqual(sent.returncode, 0)
        effects = self.shim.actions(include_help=False)
        self.assertIn(
            ["action", "write-chars", "--pane-id", "101", "late text\n"],
            [action["argv"] for action in effects],
        )
        self.assertFalse(any(action["argv"][1:2] == ["focus-pane-id"] for action in effects))

    def test_long_successful_write_help_still_selects_targeted_path(self):
        self.shim.add_live_record()
        sent = self.shim.call(
            "send-keys",
            "-t",
            "%1",
            "late",
            "Enter",
            extra_env={"SHIM_TEST_WRITE_HELP_MODE": "long"},
        )
        self.assertEqual(sent.returncode, 0)
        effects = [action["argv"] for action in self.shim.actions(include_help=False)]
        self.assertEqual(
            effects,
            [["action", "write-chars", "--pane-id", "101", "late\n"]],
        )

    def test_failed_write_help_does_not_enable_targeted_path(self):
        self.shim.add_live_record()
        sent = self.shim.call(
            "send-keys",
            "-t",
            "%1",
            "late",
            "Enter",
            extra_env={"SHIM_TEST_WRITE_HELP_MODE": "failed-advertise"},
        )
        self.assertEqual(sent.returncode, 0)
        effects = [action["argv"] for action in self.shim.actions(include_help=False)]
        self.assertEqual(
            effects,
            [["action", "focus-pane-id", "101"], ["action", "write-chars", "late\n"]],
        )

    def test_targeted_write_failure_is_propagated_without_retry(self):
        self.shim.add_live_record()
        sent = self.shim.call(
            "send-keys", "-t", "%1", "late", "Enter", extra_env={"SHIM_TEST_FAIL_WRITE": "1"}
        )
        self.assertEqual(sent.returncode, 19)
        effects = self.shim.actions(include_help=False)
        writes = [action["argv"] for action in effects if action["argv"][1:2] == ["write-chars"]]
        self.assertEqual(writes, [["action", "write-chars", "--pane-id", "101", "late\n"]])
        self.assertFalse(any(action["argv"][1:2] == ["focus-pane-id"] for action in effects))

    def test_legacy_write_focuses_validated_target_first(self):
        self.shim.add_live_record()
        sent = self.shim.call(
            "send-keys", "-t", "%1", "legacy", "Enter", extra_env={"SHIM_TEST_CAP_WRITE_PANE": "0"}
        )
        self.assertEqual(sent.returncode, 0)
        effects = [action["argv"] for action in self.shim.actions(include_help=False)]
        self.assertEqual(
            effects,
            [["action", "focus-pane-id", "101"], ["action", "write-chars", "legacy\n"]],
        )

    def test_legacy_focus_failure_stops_before_write(self):
        self.shim.add_live_record()
        sent = self.shim.call(
            "send-keys",
            "-t",
            "%1",
            "legacy",
            "Enter",
            extra_env={"SHIM_TEST_CAP_WRITE_PANE": "0", "SHIM_TEST_FAIL_FOCUS": "1"},
        )
        self.assertEqual(sent.returncode, 23)
        effects = [action["argv"] for action in self.shim.actions(include_help=False)]
        self.assertEqual(effects, [["action", "focus-pane-id", "101"]])

    def test_legacy_write_failure_is_propagated(self):
        self.shim.add_live_record()
        sent = self.shim.call(
            "send-keys",
            "-t",
            "%1",
            "legacy",
            "Enter",
            extra_env={"SHIM_TEST_CAP_WRITE_PANE": "0", "SHIM_TEST_FAIL_WRITE": "1"},
        )
        self.assertEqual(sent.returncode, 19)
        effects = [action["argv"] for action in self.shim.actions(include_help=False)]
        self.assertEqual(
            effects,
            [["action", "focus-pane-id", "101"], ["action", "write-chars", "legacy\n"]],
        )

    def test_missing_and_stale_targets_have_no_pane_effects(self):
        missing = self.shim.call("send-keys", "-t", "%1", "late", "Enter")
        self.assertNotEqual(missing.returncode, 0)
        self.assertEqual(self.shim.actions(), [])
        (self.shim.state / "1.zellij_id").write_text("101\n", encoding="ascii")
        (self.shim.state / "1.pid").write_text("99999999\n", encoding="ascii")
        stale = self.shim.call("send-keys", "-t", "%1", "late", "Enter")
        self.assertNotEqual(stale.returncode, 0)
        self.assertEqual(self.shim.actions(), [])

    def test_malformed_and_plugin_targets_have_no_pane_effects(self):
        for zellij_id in ("", "unknown", "plugin_7", "terminal_7", "-1", "7 extra"):
            with self.subTest(zellij_id=zellij_id):
                self.shim.add_live_record(zellij_id=zellij_id)
                sent = self.shim.call("send-keys", "-t", "%1", "late", "Enter")
                self.assertNotEqual(sent.returncode, 0)
                self.assertEqual(self.shim.actions(), [])

    def test_noncanonical_pids_have_no_pane_effects(self):
        self.shim.add_live_record()
        for recorded_pid in ("", "0", "00", "01", "+1", "-1", "1x", "1 2"):
            with self.subTest(recorded_pid=recorded_pid):
                action_log = self.shim.root / "zellij-actions.jsonl"
                if action_log.exists():
                    action_log.unlink()
                (self.shim.state / "1.pid").write_text(
                    f"{recorded_pid}\n", encoding="ascii"
                )
                sent = self.shim.call("send-keys", "-t", "%1", "late", "Enter")
                self.assertNotEqual(sent.returncode, 0)
                self.assertEqual(self.shim.actions(), [])

    def test_deactivate_empty_state_in_actual_zsh(self):
        original_path = "/usr/bin:/bin"
        env = self.shim.env.copy()
        env.update(
            {
                "PATH": f"{REPO / 'bin'}:{original_path}",
                "ZELLIJ_TMUX_SHIM_ACTIVE": "1",
                "ZELLIJ_TMUX_SHIM_ORIG_PATH": original_path,
            }
        )
        script = (
            f"source {shlex.quote(str(DEACTIVATE))}; "
            "printf '%s|%s|%s' \"$?\" \"$PATH\" \"${ZELLIJ_TMUX_SHIM_ACTIVE-unset}\""
        )
        result = subprocess.run(
            ["/bin/zsh", "-f", "-c", script], env=env, capture_output=True, text=True
        )
        self.assertEqual((result.returncode, result.stdout), (0, f"0|{original_path}|unset"))
        self.assertFalse(self.shim.state.exists())

    def test_deactivate_populated_state_kills_owned_pid_and_restores_environment(self):
        pid = self.shim.add_live_record()
        original_path = "/usr/bin:/bin"
        env = self.shim.env.copy()
        env.update(
            {
                "PATH": f"{REPO / 'bin'}:{original_path}",
                "ZELLIJ_TMUX_SHIM_ACTIVE": "1",
                "ZELLIJ_TMUX_SHIM_ORIG_PATH": original_path,
                "ZELLIJ_TMUX_SHIM_REAL_TMUX": "/usr/bin/false",
                "ZELLIJ_TMUX_SHIM_DEBUG": "1",
            }
        )
        script = (
            f"source {shlex.quote(str(DEACTIVATE))}; "
            "printf '%s|%s|%s|%s' \"$?\" \"$PATH\" "
            "\"${ZELLIJ_TMUX_SHIM_ACTIVE-unset}\" \"${ZELLIJ_TMUX_SHIM_STATE-unset}\""
        )
        result = subprocess.run(
            ["/bin/zsh", "-f", "-c", script], env=env, capture_output=True, text=True
        )
        self.assertEqual(
            (result.returncode, result.stdout), (0, f"0|{original_path}|unset|unset")
        )
        self.assertFalse(self.shim.state.exists())
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if subprocess.run(["/bin/kill", "-0", str(pid)], capture_output=True).returncode != 0:
                break
            time.sleep(0.02)
        self.assertNotEqual(
            subprocess.run(["/bin/kill", "-0", str(pid)], capture_output=True).returncode,
            0,
        )


CASE_METHODS = {
    "baseline-cli": "test_baseline_cli",
    "deferred-respawn": "test_deferred_cat_title_and_respawn",
    "inline-argv": "test_inline_command_preserves_argv",
    "fifo-startup": "test_fifo_send_starts_legacy_command",
    "placement": "test_leader_relative_and_sibling_placement",
    "legacy-new-window-name": "test_legacy_new_window_preserves_creation_name",
    "targeted-write": "test_write_capability_is_independent_and_targeted",
    "targeted-long-help": "test_long_successful_write_help_still_selects_targeted_path",
    "targeted-failed-help": "test_failed_write_help_does_not_enable_targeted_path",
    "targeted-failure": "test_targeted_write_failure_is_propagated_without_retry",
    "legacy-write": "test_legacy_write_focuses_validated_target_first",
    "legacy-focus-failure": "test_legacy_focus_failure_stops_before_write",
    "legacy-write-failure": "test_legacy_write_failure_is_propagated",
    "stale-target": "test_missing_and_stale_targets_have_no_pane_effects",
    "invalid-zellij-id": "test_malformed_and_plugin_targets_have_no_pane_effects",
    "invalid-pid": "test_noncanonical_pids_have_no_pane_effects",
    "zsh-empty": "test_deactivate_empty_state_in_actual_zsh",
    "zsh-populated": "test_deactivate_populated_state_kills_owned_pid_and_restores_environment",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=("core",), default="core")
    parser.add_argument("--case", choices=tuple(CASE_METHODS))
    args = parser.parse_args()
    if args.case:
        suite = unittest.TestSuite([CoreCompatibilityTests(CASE_METHODS[args.case])])
    else:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(CoreCompatibilityTests)
    outcome = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if outcome.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Fish integration and shared activation-state regressions."""

import argparse
import json
import os
from pathlib import Path
import shlex
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
ACTIVATE_SH = ROOT / "activate.sh"
DEACTIVATE_SH = ROOT / "deactivate.sh"
ACTIVATE_FISH = ROOT / "activate.fish"
DEACTIVATE_FISH = ROOT / "deactivate.fish"
INSTALL_FISH = ROOT / "install.fish"
FUNCTION_FISH = ROOT / "functions" / "claude-zellij.fish"
FAKE_ZELLIJ = ROOT / "tests" / "helpers" / "fake_zellij.py"
FISH = os.environ.get("SHIM_TEST_FISH") or shutil.which("fish") or "/opt/homebrew/bin/fish"
BASH = os.environ.get("SHIM_TEST_BASH", "/bin/bash")


def parse_env(raw):
    values = {}
    for item in raw.split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            values[key.decode("utf-8")] = value.decode("utf-8")
    return values


class FishTests(unittest.TestCase):
    def setUp(self):
        if not Path(FISH).is_absolute() or not os.access(FISH, os.X_OK):
            self.skipTest("SHIM_TEST_FISH does not name an executable fish")
        self.temp = tempfile.TemporaryDirectory(prefix="zct fish integration ")
        self.root = Path(self.temp.name)
        self.home = self.root / "home with spaces"
        self.data = self.root / "data with spaces"
        self.config = self.root / "config with spaces"
        self.runtime = self.root / "runtime with spaces"
        for path in (self.home, self.data, self.config, self.runtime):
            path.mkdir(mode=0o700)
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "XDG_DATA_HOME": str(self.data),
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "ZELLIJ": "1",
            "ZELLIJ_SESSION_NAME": "shared-session",
        }
        self.processes = []

    def tearDown(self):
        owned = self.root / "owned-processes"
        if owned.exists():
            for raw_pid in owned.read_text(encoding="ascii").splitlines():
                if raw_pid.isdigit():
                    try:
                        os.killpg(int(raw_pid), signal.SIGTERM)
                    except ProcessLookupError:
                        pass
        for proc in self.processes:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for proc in self.processes:
            try:
                proc.wait(timeout=2)
            except (subprocess.TimeoutExpired, ProcessLookupError):
                pass
        self.temp.cleanup()

    def run_cmd(self, argv, env=None, timeout=15):
        return subprocess.run(
            argv,
            env=self.env if env is None else env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )

    def bash_env(self, body, env=None):
        script = body + "; _zct_status=$?; /usr/bin/printf 'ZCT_STATUS=%s\\0' \"$_zct_status\"; /usr/bin/env -0"
        result = self.run_cmd([BASH, "--noprofile", "--norc", "-c", script], env=env)
        return result, parse_env(result.stdout)

    def fish_env(self, body, env=None):
        script = body + "; set -l zct_status $status; /usr/bin/printf 'ZCT_STATUS=%s\\0' $zct_status; /usr/bin/env -0"
        result = self.run_cmd([FISH, "--no-config", "-c", script], env=env)
        return result, parse_env(result.stdout)

    def install(self):
        return self.run_cmd([FISH, str(INSTALL_FISH), "--quiet"])

    def make_claude_recorder(self):
        fake_bin = self.root / "fake commands"
        fake_bin.mkdir(exist_ok=True)
        recorder = fake_bin / "claude"
        recorder.write_text(
            "#!" + sys.executable + "\n"
            "import json, os, subprocess, sys\n"
            "record = {'argv': sys.argv[1:], 'teams': os.environ.get('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'), "
            "'tmux': os.environ.get('TMUX'), 'state': os.environ.get('ZELLIJ_TMUX_SHIM_STATE'), "
            "'path': os.environ.get('PATH'), 'saved_path': os.environ.get('ZELLIJ_TMUX_SHIM_SAVED_PATH_VALUE')}\n"
            "with open(os.environ['CLAUDE_RECORD'], 'a', encoding='utf-8') as out: out.write(json.dumps(record) + '\\n')\n"
            "if os.environ.get('CLAUDE_RUN_TMUX'):\n"
            "    command = 'printf started > \"$SHIM_TEST_ROOT/fish-started\"; sleep 60'\n"
            "    raise SystemExit(subprocess.run(['tmux', 'split-window', '-P', '--', os.environ['SHIM_TEST_BASH'], '-c', command]).returncode)\n"
            "raise SystemExit(int(os.environ.get('CLAUDE_EXIT', '0')))\n",
            encoding="utf-8",
        )
        recorder.chmod(0o755)
        return fake_bin

    def records(self):
        path = self.root / "claude-records.jsonl"
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]

    def test_fish_installer_install_update_uninstall_isolated(self):
        data_sentinel = self.data / "keep-data"
        config_sentinel = self.config / "keep-config"
        data_sentinel.write_text("keep", encoding="utf-8")
        config_sentinel.write_text("keep", encoding="utf-8")

        installed = self.install()
        self.assertEqual(installed.returncode, 0, installed.stderr.decode())
        runtime = self.data / "zellij-tmux-shim"
        function = self.config / "fish" / "functions" / "claude-zellij.fish"
        copied = [
            "VERSION", "activate.sh", "deactivate.sh", "activate.fish",
            "deactivate.fish", "functions/claude-zellij.fish", "bin/tmux",
            "bin/zellij-pane-wrapper",
        ]
        for relative in copied:
            self.assertEqual((runtime / relative).read_bytes(), (ROOT / relative).read_bytes(), relative)
        self.assertEqual(function.read_bytes(), FUNCTION_FISH.read_bytes())

        function.write_text("stale\n", encoding="utf-8")
        updated = self.install()
        self.assertEqual(updated.returncode, 0, updated.stderr.decode())
        self.assertEqual(function.read_bytes(), FUNCTION_FISH.read_bytes())

        removed = self.run_cmd([FISH, str(INSTALL_FISH), "--quiet", "--uninstall"])
        self.assertEqual(removed.returncode, 0, removed.stderr.decode())
        self.assertFalse(runtime.exists())
        self.assertFalse(function.exists())
        self.assertEqual(data_sentinel.read_text(), "keep")
        self.assertEqual(config_sentinel.read_text(), "keep")

    def test_installers_validate_options_and_read_only_actions_before_writes(self):
        cases = [
            ([BASH, str(ROOT / "install.sh"), "--quiet", "--version"], 0, b"zellij-claude-teams "),
            ([BASH, str(ROOT / "install.sh"), "--quiet", "--bogus"], 2, b"unknown option"),
            ([FISH, str(INSTALL_FISH), "--quiet", "--version"], 0, b"zellij-claude-teams "),
            ([FISH, str(INSTALL_FISH), "--quiet", "--bogus"], 2, b"unknown option"),
            ([FISH, str(INSTALL_FISH), "--help"], 0, b"Usage:"),
        ]
        for argv, status, message in cases:
            with self.subTest(argv=argv):
                result = self.run_cmd(argv)
                self.assertEqual(result.returncode, status, result.stderr.decode())
                self.assertIn(message, result.stdout + result.stderr)
                self.assertFalse((self.data / "zellij-tmux-shim").exists())
                self.assertFalse((self.config / "fish" / "functions" / "claude-zellij.fish").exists())

    def test_fish_installer_propagates_function_copy_and_remove_errors(self):
        function = self.config / "fish" / "functions" / "claude-zellij.fish"
        function.mkdir(parents=True)
        copied = self.install()
        self.assertNotEqual(copied.returncode, 0)
        removed = self.run_cmd([FISH, str(INSTALL_FISH), "--quiet", "--uninstall"])
        self.assertNotEqual(removed.returncode, 0)

    def test_bash_and_fish_reactivation_preserve_path_and_saved_environment(self):
        original = "::/alpha path:/usr/bin:/bin:"
        for shell in ("bash", "fish"):
            with self.subTest(shell=shell):
                env = {**self.env, "PATH": original, "TMUX": "", "TMUX_PANE": "pane before"}
                if shell == "bash":
                    expected_active = str(self.data / "zellij-tmux-shim" / "bin") + "::/alpha path:/usr/bin:/bin:"
                    expected_original = original
                    source = shlex.quote(str(ACTIVATE_SH))
                    body = (
                        ". " + source + "; "
                        "PATH=\"$ZELLIJ_TMUX_SHIM_DIR/bin::$ZELLIJ_TMUX_SHIM_DIR/bin:/alpha path:/usr/bin:/bin:\"; export PATH; "
                        ". " + source + "; . " + source
                    )
                    active_result, active = self.bash_env(body, env)
                    self.assertEqual(active_result.returncode, 0, active_result.stderr.decode())
                    self.assertEqual(active["PATH"], expected_active)
                    self.assertEqual(active["ZELLIJ_TMUX_SHIM_ORIG_PATH"], original)
                    final_result, final = self.bash_env(body + "; . " + shlex.quote(str(DEACTIVATE_SH)), env)
                else:
                    _, baseline = self.fish_env("true", env)
                    expected_original = baseline["PATH"]
                    expected_active = str(self.data / "zellij-tmux-shim" / "bin") + ":.:/alpha path:/usr/bin:/bin:."
                    source = shlex.quote(str(ACTIVATE_FISH))
                    body = (
                        "source " + source + "; "
                        "set -gx PATH $ZELLIJ_TMUX_SHIM_DIR/bin '' $ZELLIJ_TMUX_SHIM_DIR/bin '/alpha path' /usr/bin /bin ''; "
                        "source " + source + "; source " + source
                    )
                    active_result, active = self.fish_env(body, env)
                    self.assertEqual(active_result.returncode, 0, active_result.stderr.decode())
                    self.assertEqual(active["PATH"], expected_active)
                    self.assertEqual(active["ZELLIJ_TMUX_SHIM_ORIG_PATH"], expected_original)
                    final_result, final = self.fish_env(body + "; source " + shlex.quote(str(DEACTIVATE_FISH)), env)
                self.assertEqual(final_result.returncode, 0, final_result.stderr.decode())
                self.assertEqual(final.get("PATH"), expected_original)
                self.assertEqual(final.get("TMUX"), "")
                self.assertEqual(final.get("TMUX_PANE"), "pane before")
                self.assertNotIn("ZELLIJ_TMUX_SHIM_ACTIVE", final)

    def test_bash_and_fish_round_trip_empty_and_unset_environment(self):
        for shell in ("bash", "fish"):
            with self.subTest(shell=shell, variant="empty"):
                env = {**self.env, "PATH": "", "TMUX": "", "TMUX_PANE": ""}
                expected_path = ""
                if shell == "bash":
                    result, final = self.bash_env(
                        ". " + shlex.quote(str(ACTIVATE_SH)) + "; . " + shlex.quote(str(DEACTIVATE_SH)), env
                    )
                else:
                    _, baseline = self.fish_env("true", env)
                    expected_path = baseline["PATH"]
                    result, final = self.fish_env(
                        "source " + shlex.quote(str(ACTIVATE_FISH)) + "; source " + shlex.quote(str(DEACTIVATE_FISH)), env
                    )
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertEqual(final.get("PATH"), expected_path)
                self.assertEqual(final.get("TMUX"), "")
                self.assertEqual(final.get("TMUX_PANE"), "")

            with self.subTest(shell=shell, variant="unset"):
                env = {key: value for key, value in self.env.items() if key not in ("TMUX", "TMUX_PANE")}
                if shell == "bash":
                    result, final = self.bash_env(
                        ". " + shlex.quote(str(ACTIVATE_SH)) + "; . " + shlex.quote(str(DEACTIVATE_SH)), env
                    )
                else:
                    result, final = self.fish_env(
                        "source " + shlex.quote(str(ACTIVATE_FISH)) + "; source " + shlex.quote(str(DEACTIVATE_FISH)), env
                    )
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertNotIn("TMUX", final)
                self.assertNotIn("TMUX_PANE", final)

    def test_fish_round_trip_truly_unset_path_for_saved_and_legacy_state(self):
        primary_result, primary = self.fish_env(
            "set -e PATH; source " + shlex.quote(str(ACTIVATE_FISH)) + "; source " + shlex.quote(str(DEACTIVATE_FISH))
        )
        self.assertEqual(primary_result.returncode, 0, primary_result.stderr.decode())
        self.assertEqual(primary.get("ZCT_STATUS"), "0", primary_result.stderr.decode())
        self.assertNotIn("PATH", primary)

        runtime = self.root / "legacy unset path"
        state = runtime / ("zellij-tmux-shim-" + str(os.getuid())) / "shared-session"
        state.mkdir(parents=True)
        legacy_env = {
            **self.env,
            "XDG_RUNTIME_DIR": str(runtime),
            "ZELLIJ_TMUX_SHIM_ACTIVE": "1",
            "ZELLIJ_TMUX_SHIM_STATE": str(state),
            "ZELLIJ_TMUX_SHIM_ORIG_PATH_SET": "0",
        }
        legacy_result, legacy = self.fish_env("source " + shlex.quote(str(DEACTIVATE_FISH)), legacy_env)
        self.assertEqual(legacy_result.returncode, 0, legacy_result.stderr.decode())
        self.assertEqual(legacy.get("ZCT_STATUS"), "0", legacy_result.stderr.decode())
        self.assertNotIn("PATH", legacy)

    def test_fish_activation_preserves_callers_umask(self):
        script = (
            "umask 027; set -l before (umask); "
            "source " + shlex.quote(str(ACTIVATE_FISH)) + "; "
            "set -l activate_status $status; set -l after (umask); "
            "/usr/bin/printf '%s|%s|%s' $activate_status $before $after"
        )
        result = self.run_cmd([FISH, "--no-config", "-c", script])
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(result.stdout, b"0|0027|0027")

    def test_bash_and_fish_guards_and_init_failures_do_not_mutate_environment(self):
        for shell in ("bash", "fish"):
            for failure in ("root-symlink", "session-symlink", "invalid-dot", "invalid-parent", "invalid-slash", "init"):
                with self.subTest(shell=shell, failure=failure):
                    case_runtime = self.root / (shell + "-" + failure)
                    case_runtime.mkdir()
                    uid = os.getuid()
                    root = case_runtime / ("zellij-tmux-shim-" + str(uid))
                    env = {**self.env, "XDG_RUNTIME_DIR": str(case_runtime), "PATH": "/usr/bin:/bin", "TMUX": "before", "TMUX_PANE": "old"}
                    if failure == "root-symlink":
                        target = case_runtime / "target"
                        target.mkdir()
                        root.symlink_to(target, target_is_directory=True)
                    elif failure == "session-symlink":
                        root.mkdir()
                        target = case_runtime / "target"
                        target.mkdir()
                        (root / "shared-session").symlink_to(target, target_is_directory=True)
                    elif failure == "invalid-dot":
                        env["ZELLIJ_SESSION_NAME"] = "."
                    elif failure == "invalid-parent":
                        env["ZELLIJ_SESSION_NAME"] = ".."
                    elif failure == "invalid-slash":
                        env["ZELLIJ_SESSION_NAME"] = "nested/session"
                    else:
                        state = root / "shared-session"
                        state.mkdir(parents=True)
                        (state / "next_id").mkdir()
                    if shell == "bash":
                        result, after = self.bash_env(". " + shlex.quote(str(ACTIVATE_SH)), env)
                    else:
                        result, after = self.fish_env("source " + shlex.quote(str(ACTIVATE_FISH)), env)
                    self.assertEqual(after.get("ZCT_STATUS"), "1", result.stderr.decode())
                    self.assertEqual(after.get("PATH"), env["PATH"])
                    self.assertEqual(after.get("TMUX"), "before")
                    self.assertEqual(after.get("TMUX_PANE"), "old")
                    self.assertNotIn("ZELLIJ_TMUX_SHIM_ACTIVE", after)
                    self.assertNotIn("ZELLIJ_TMUX_SHIM_STATE", after)

    def test_bash_and_fish_share_sessions_and_isolate_distinct_sessions(self):
        bash_result, bash_env = self.bash_env(". " + shlex.quote(str(ACTIVATE_SH)))
        fish_result, fish_env = self.fish_env("source " + shlex.quote(str(ACTIVATE_FISH)))
        self.assertEqual((bash_result.returncode, fish_result.returncode), (0, 0))
        self.assertEqual(bash_env["ZELLIJ_TMUX_SHIM_STATE"], fish_env["ZELLIJ_TMUX_SHIM_STATE"])
        self.assertTrue((Path(bash_env["ZELLIJ_TMUX_SHIM_STATE"]) / "next_id").is_file())
        other = {**self.env, "ZELLIJ_SESSION_NAME": "other-session"}
        _, other_env = self.fish_env("source " + shlex.quote(str(ACTIVATE_FISH)), other)
        self.assertNotEqual(other_env["ZELLIJ_TMUX_SHIM_STATE"], bash_env["ZELLIJ_TMUX_SHIM_STATE"])

    def test_cross_shell_inherited_deactivation_restores_tmux_presence_and_values(self):
        variants = (
            ("unset", None, None),
            ("empty", "", ""),
            ("value", "prior tmux", "prior pane"),
        )
        directions = (("bash", "fish"), ("fish", "bash"))
        for activating, deactivating in directions:
            for variant, tmux, pane in variants:
                with self.subTest(activating=activating, deactivating=deactivating, variant=variant):
                    runtime = self.root / (activating + "-to-" + deactivating + "-" + variant)
                    runtime.mkdir()
                    env = {**self.env, "XDG_RUNTIME_DIR": str(runtime), "PATH": "/usr/bin:/bin"}
                    env.pop("TMUX", None)
                    env.pop("TMUX_PANE", None)
                    if tmux is not None:
                        env["TMUX"] = tmux
                        env["TMUX_PANE"] = pane
                    if activating == "bash":
                        activated_result, activated = self.bash_env(". " + shlex.quote(str(ACTIVATE_SH)), env)
                    else:
                        activated_result, activated = self.fish_env("source " + shlex.quote(str(ACTIVATE_FISH)), env)
                    self.assertEqual(activated.get("ZCT_STATUS"), "0", activated_result.stderr.decode())
                    if deactivating == "bash":
                        deactivated_result, deactivated = self.bash_env(". " + shlex.quote(str(DEACTIVATE_SH)), activated)
                    else:
                        deactivated_result, deactivated = self.fish_env("source " + shlex.quote(str(DEACTIVATE_FISH)), activated)
                    self.assertEqual(deactivated.get("ZCT_STATUS"), "0", deactivated_result.stderr.decode())
                    self.assertEqual(deactivated.get("PATH"), "/usr/bin:/bin")
                    if tmux is None:
                        self.assertNotIn("TMUX", deactivated)
                        self.assertNotIn("TMUX_PANE", deactivated)
                    else:
                        self.assertEqual(deactivated.get("TMUX"), tmux)
                        self.assertEqual(deactivated.get("TMUX_PANE"), pane)

    def test_shared_session_can_be_deactivated_by_both_activated_shells(self):
        for first, second in (("bash", "fish"), ("fish", "bash")):
            with self.subTest(first=first, second=second):
                runtime = self.root / ("shared removal " + first)
                runtime.mkdir()
                env = {**self.env, "XDG_RUNTIME_DIR": str(runtime), "PATH": "/usr/bin:/bin", "TMUX": "before", "TMUX_PANE": "pane"}
                activated = {}
                for shell in ("bash", "fish"):
                    if shell == "bash":
                        result, values = self.bash_env(". " + shlex.quote(str(ACTIVATE_SH)), env)
                    else:
                        result, values = self.fish_env("source " + shlex.quote(str(ACTIVATE_FISH)), env)
                    self.assertEqual(values.get("ZCT_STATUS"), "0", result.stderr.decode())
                    activated[shell] = values

                if first == "bash":
                    first_result, first_values = self.bash_env(". " + shlex.quote(str(DEACTIVATE_SH)), activated[first])
                else:
                    first_result, first_values = self.fish_env("source " + shlex.quote(str(DEACTIVATE_FISH)), activated[first])
                self.assertEqual(first_values.get("ZCT_STATUS"), "0", first_result.stderr.decode())

                if second == "bash":
                    second_result, second_values = self.bash_env(". " + shlex.quote(str(DEACTIVATE_SH)), activated[second])
                else:
                    second_result, second_values = self.fish_env("source " + shlex.quote(str(DEACTIVATE_FISH)), activated[second])
                self.assertEqual(second_values.get("ZCT_STATUS"), "0", second_result.stderr.decode())
                self.assertEqual(second_values.get("PATH"), "/usr/bin:/bin")
                self.assertEqual(second_values.get("TMUX"), "before")
                self.assertEqual(second_values.get("TMUX_PANE"), "pane")
                self.assertNotIn("ZELLIJ_TMUX_SHIM_ACTIVE", second_values)

    def test_deactivation_restores_environment_when_canonical_root_is_already_absent(self):
        for shell in ("bash", "fish"):
            with self.subTest(shell=shell):
                runtime = self.root / (shell + " absent root")
                state = runtime / ("zellij-tmux-shim-" + str(os.getuid())) / "shared-session"
                env = {
                    **self.env,
                    "XDG_RUNTIME_DIR": str(runtime),
                    "PATH": str(self.data / "zellij-tmux-shim" / "bin") + ":/usr/bin:/bin",
                    "TMUX": "fake",
                    "TMUX_PANE": "%0",
                    "ZELLIJ_TMUX_SHIM_ACTIVE": "1",
                    "ZELLIJ_TMUX_SHIM_STATE": str(state),
                    "ZELLIJ_TMUX_SHIM_SAVED_PATH_PRESENT": "1",
                    "ZELLIJ_TMUX_SHIM_SAVED_PATH_VALUE": "/usr/bin:/bin",
                    "ZELLIJ_TMUX_SHIM_SAVED_TMUX_PRESENT": "1",
                    "ZELLIJ_TMUX_SHIM_SAVED_TMUX_VALUE": "before",
                    "ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_PRESENT": "0",
                    "ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_VALUE": "",
                }
                if shell == "bash":
                    result, restored = self.bash_env(". " + shlex.quote(str(DEACTIVATE_SH)), env)
                else:
                    result, restored = self.fish_env("source " + shlex.quote(str(DEACTIVATE_FISH)), env)
                self.assertEqual(restored.get("ZCT_STATUS"), "0", result.stderr.decode())
                self.assertEqual(restored.get("PATH"), "/usr/bin:/bin")
                self.assertEqual(restored.get("TMUX"), "before")
                self.assertNotIn("TMUX_PANE", restored)
                self.assertNotIn("ZELLIJ_TMUX_SHIM_ACTIVE", restored)

    def test_zsh_repeated_activation_and_deactivation_restore_saved_environment(self):
        original_path = "/usr/bin:/bin"
        env = {**self.env, "PATH": original_path, "TMUX": "prior tmux", "TMUX_PANE": ""}
        activate = shlex.quote(str(ACTIVATE_SH))
        deactivate = shlex.quote(str(DEACTIVATE_SH))
        script = (
            "source " + activate + "; "
            "PATH=\"$ZELLIJ_TMUX_SHIM_DIR/bin::$ZELLIJ_TMUX_SHIM_DIR/bin:/usr/bin:/bin\"; export PATH; "
            "source " + activate + "; source " + activate + "; "
            "/usr/bin/printf 'active|%s|%s|%s\\n' \"$PATH\" \"$ZELLIJ_TMUX_SHIM_ORIG_PATH\" \"$TMUX_PANE\"; "
            "source " + deactivate + "; "
            "/usr/bin/printf 'final|%s|%s|%s|%s\\n' \"$PATH\" \"$TMUX\" \"$TMUX_PANE\" \"${ZELLIJ_TMUX_SHIM_ACTIVE-unset}\""
        )
        result = self.run_cmd(["/bin/zsh", "-f", "-c", script], env=env)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        lines = result.stdout.decode().splitlines()
        shim_bin = str(self.data / "zellij-tmux-shim" / "bin")
        self.assertEqual(lines[0], "active|" + shim_bin + "::/usr/bin:/bin|" + original_path + "|%0")
        self.assertEqual(lines[1], "final|" + original_path + "|prior tmux||unset")

    def test_bash_and_fish_cleanup_dead_records_but_preserve_live_session_files(self):
        for shell in ("bash", "fish"):
            with self.subTest(shell=shell):
                runtime = self.root / (shell + " cleanup")
                runtime.mkdir()
                state = runtime / ("zellij-tmux-shim-" + str(os.getuid())) / "shared-session"
                state.mkdir(parents=True)
                (state / "next_id").write_text("3\n", encoding="ascii")
                (state / "sessions").touch()
                live = subprocess.Popen([BASH, "-c", "sleep 60"], start_new_session=True)
                self.processes.append(live)
                extensions = ("pid", "zellij_id", "fifo", "ready", "cmd", "named", "group", "title")
                for key, pid in (("1", str(live.pid)), ("2", "99999999"), ("3", "00")):
                    for extension in extensions:
                        (state / (key + "." + extension)).write_text(pid + "\n", encoding="ascii")
                (state / "4.zellij_id").write_text("104\n", encoding="ascii")
                (state / "parent.env").write_text("live snapshot\n", encoding="utf-8")
                lock = state / "next_id.lock"
                lock.mkdir()
                (lock / "pid").write_text(str(live.pid) + "\n", encoding="ascii")
                env = {**self.env, "XDG_RUNTIME_DIR": str(runtime)}
                if shell == "bash":
                    result, _ = self.bash_env(". " + shlex.quote(str(ACTIVATE_SH)), env)
                else:
                    result, _ = self.fish_env("source " + shlex.quote(str(ACTIVATE_FISH)), env)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                for extension in extensions:
                    self.assertTrue((state / ("1." + extension)).exists(), extension)
                    self.assertFalse((state / ("2." + extension)).exists(), extension)
                    self.assertFalse((state / ("3." + extension)).exists(), extension)
                self.assertFalse((state / "4.zellij_id").exists())
                self.assertTrue((state / "parent.env").exists())
                self.assertTrue(lock.exists())

    def test_bash_and_fish_preserve_live_allocator_lock_before_wrapper_registration(self):
        for shell in ("bash", "fish"):
            with self.subTest(shell=shell):
                runtime = self.root / (shell + " live allocator")
                state = runtime / ("zellij-tmux-shim-" + str(os.getuid())) / "shared-session"
                state.mkdir(parents=True)
                (state / "next_id").write_text("1\n", encoding="ascii")
                (state / "sessions").touch()
                parent_env = state / "parent.env"
                parent_env.write_text("in-flight snapshot\n", encoding="utf-8")
                lock = state / "next_id.lock"
                lock.mkdir()
                owner = subprocess.Popen([BASH, "-c", "sleep 60"], start_new_session=True)
                self.processes.append(owner)
                (lock / "pid").write_text(str(owner.pid) + "\n", encoding="ascii")
                env = {**self.env, "XDG_RUNTIME_DIR": str(runtime)}
                if shell == "bash":
                    result, _ = self.bash_env(". " + shlex.quote(str(ACTIVATE_SH)), env)
                else:
                    result, _ = self.fish_env("source " + shlex.quote(str(ACTIVATE_FISH)), env)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertTrue(lock.is_dir())
                self.assertEqual((lock / "pid").read_text(), str(owner.pid) + "\n")
                self.assertEqual(parent_env.read_text(), "in-flight snapshot\n")

    def test_deactivation_rejects_unsafe_state_and_noncanonical_pids(self):
        for shell in ("bash", "fish"):
            with self.subTest(shell=shell, variant="unsafe-path"):
                unsafe = self.root / (shell + " unsafe")
                unsafe.mkdir()
                sentinel = unsafe / "sentinel"
                sentinel.write_text("keep", encoding="utf-8")
                env = {**self.env, "ZELLIJ_TMUX_SHIM_ACTIVE": "1", "ZELLIJ_TMUX_SHIM_STATE": str(unsafe)}
                if shell == "bash":
                    result, after = self.bash_env(". " + shlex.quote(str(DEACTIVATE_SH)), env)
                else:
                    result, after = self.fish_env("source " + shlex.quote(str(DEACTIVATE_FISH)), env)
                self.assertEqual(after.get("ZCT_STATUS"), "1", result.stderr.decode())
                self.assertTrue(sentinel.exists())
                self.assertEqual(after.get("ZELLIJ_TMUX_SHIM_ACTIVE"), "1")

            with self.subTest(shell=shell, variant="noncanonical-pids"):
                runtime = self.root / (shell + " pids")
                state = runtime / ("zellij-tmux-shim-" + str(os.getuid())) / "shared-session"
                state.mkdir(parents=True)
                for index, pid in enumerate(("0", "00", "01", "-1", "word"), 1):
                    (state / (str(index) + ".pid")).write_text(pid + "\n", encoding="ascii")
                log = self.root / (shell + " kill-log")
                env = {
                    **self.env,
                    "XDG_RUNTIME_DIR": str(runtime),
                    "ZELLIJ_TMUX_SHIM_ACTIVE": "1",
                    "ZELLIJ_TMUX_SHIM_STATE": str(state),
                    "ZCT_KILL_LOG": str(log),
                }
                if shell == "bash":
                    body = "kill() { /usr/bin/printf '%s\\n' \"$*\" >> \"$ZCT_KILL_LOG\"; }; . " + shlex.quote(str(DEACTIVATE_SH))
                    result, _ = self.bash_env(body, env)
                else:
                    body = "function kill; /usr/bin/printf '%s\\n' \"$argv\" >> $ZCT_KILL_LOG; end; source " + shlex.quote(str(DEACTIVATE_FISH))
                    result, _ = self.fish_env(body, env)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertFalse(log.exists(), log.read_text() if log.exists() else "")

    def test_launcher_passthrough_missing_install_and_missing_claude(self):
        fake_bin = self.make_claude_recorder()
        record = self.root / "claude-records.jsonl"
        base = {**self.env, "PATH": str(fake_bin) + ":/usr/bin:/bin", "CLAUDE_RECORD": str(record), "CLAUDE_EXIT": "7"}
        base.pop("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS", None)
        outside = {key: value for key, value in base.items() if key != "ZELLIJ"}
        result, after = self.fish_env(
            "source " + shlex.quote(str(FUNCTION_FISH)) + "; claude-zellij 'two words' -- flag", outside
        )
        self.assertEqual(after["ZCT_STATUS"], "7")
        self.assertEqual(self.records()[-1]["argv"], ["two words", "--", "flag"])
        self.assertIsNone(self.records()[-1]["teams"])

        missing = self.fish_env(
            "source " + shlex.quote(str(FUNCTION_FISH)) + "; claude-zellij raw", base
        )[0]
        self.assertIn(b"starting claude without the shim", missing.stderr)
        self.assertEqual(self.records()[-1]["argv"], ["raw"])

        no_claude = {**self.env, "PATH": "/usr/bin:/bin"}
        _, missing_env = self.fish_env(
            "source " + shlex.quote(str(FUNCTION_FISH)) + "; claude-zellij", no_claude
        )
        self.assertEqual(missing_env["ZCT_STATUS"], "127")

    def test_launcher_child_isolation_status_and_teammate_modes(self):
        installed = self.install()
        self.assertEqual(installed.returncode, 0, installed.stderr.decode())
        fake_bin = self.make_claude_recorder()
        record = self.root / "claude-records.jsonl"
        base = {
            **self.env,
            "PATH": str(fake_bin) + ":/usr/bin:/bin",
            "CLAUDE_RECORD": str(record),
            "CLAUDE_EXIT": "23",
        }
        base.pop("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS", None)
        cases = [
            (["plain", "two words"], ["--teammate-mode", "tmux", "plain", "two words"]),
            (["--teammate-mode", "in-process", "x"], ["--teammate-mode", "in-process", "x"]),
            (["--teammate-mode=auto", "x"], ["--teammate-mode=auto", "x"]),
            (["--", "--teammate-mode", "literal"], ["--teammate-mode", "tmux", "--", "--teammate-mode", "literal"]),
        ]
        for passed, expected in cases:
            with self.subTest(passed=passed):
                args = " ".join(shlex.quote(arg) for arg in passed)
                result, after = self.fish_env(
                    "source " + shlex.quote(str(FUNCTION_FISH)) + "; claude-zellij " + args,
                    base,
                )
                self.assertEqual(after["ZCT_STATUS"], "23", result.stderr.decode())
                self.assertEqual(self.records()[-1]["argv"], expected)
                self.assertEqual(self.records()[-1]["teams"], "1")
                self.assertIsNotNone(self.records()[-1]["tmux"])
                self.assertNotIn("ZELLIJ_TMUX_SHIM_ACTIVE", after)
                self.assertNotIn("TMUX", after)
                self.assertEqual(after["PATH"], base["PATH"])

    def test_launcher_failed_activation_never_launches_claude_and_already_active_works(self):
        installed = self.install()
        self.assertEqual(installed.returncode, 0, installed.stderr.decode())
        fake_bin = self.make_claude_recorder()
        record = self.root / "claude-records.jsonl"
        base = {**self.env, "PATH": str(fake_bin) + ":/usr/bin:/bin", "CLAUDE_RECORD": str(record)}
        base.pop("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS", None)
        failed = {**base, "ZELLIJ_SESSION_NAME": ".."}
        _, failed_env = self.fish_env(
            "source " + shlex.quote(str(FUNCTION_FISH)) + "; claude-zellij should-not-run", failed
        )
        self.assertNotEqual(failed_env["ZCT_STATUS"], "0")
        self.assertEqual(self.records(), [])

        shim_dir = str(self.data / "zellij-tmux-shim")
        active = {
            **base,
            "ZELLIJ_TMUX_SHIM_ACTIVE": "1",
            "ZELLIJ_TMUX_SHIM_DIR": shim_dir,
            "ZELLIJ_TMUX_SHIM_SAVED_PATH_VALUE": "original snapshot",
        }
        _, active_env = self.fish_env(
            "source " + shlex.quote(str(FUNCTION_FISH)) + "; claude-zellij --teammate-mode custom x", active
        )
        self.assertEqual(active_env["ZCT_STATUS"], "0")
        self.assertEqual(self.records()[-1]["argv"], ["--teammate-mode", "custom", "x"])
        self.assertEqual(self.records()[-1]["teams"], "1")
        self.assertEqual(self.records()[-1]["path"].split(":"), [shim_dir + "/bin"] + base["PATH"].split(":"))
        self.assertEqual(self.records()[-1]["saved_path"], "original snapshot")
        self.assertEqual(active_env["PATH"], base["PATH"])

    def test_installed_launcher_runs_actual_shared_wrapper_from_fish_environment(self):
        installed = self.install()
        self.assertEqual(installed.returncode, 0, installed.stderr.decode())
        fake_bin = self.make_claude_recorder()
        (fake_bin / "zellij").symlink_to(FAKE_ZELLIJ)
        record = self.root / "claude-records.jsonl"
        env = {
            **self.env,
            "PATH": str(fake_bin) + ":" + str(Path(sys.executable).resolve().parent) + ":/usr/bin:/bin",
            "CLAUDE_RECORD": str(record),
            "CLAUDE_RUN_TMUX": "1",
            "SHIM_TEST_BASH": BASH,
            "SHIM_TEST_ROOT": str(self.root),
            "ZELLIJ_PANE_ID": "10",
        }
        env.pop("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS", None)
        result = self.run_cmd(
            [FISH, "--no-config", "-c", "set -p fish_function_path $XDG_CONFIG_HOME/fish/functions; claude-zellij"],
            env=env,
            timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        deadline = time.monotonic() + 4
        started = self.root / "fish-started"
        while time.monotonic() < deadline and not started.exists():
            time.sleep(0.02)
        self.assertTrue(started.exists(), result.stderr.decode())
        self.assertTrue(self.records()[-1]["state"].endswith("/shared-session"))


CASE_METHODS = {
    "install": "test_fish_installer_install_update_uninstall_isolated",
    "options": "test_installers_validate_options_and_read_only_actions_before_writes",
    "install-errors": "test_fish_installer_propagates_function_copy_and_remove_errors",
    "path": "test_bash_and_fish_reactivation_preserve_path_and_saved_environment",
    "roundtrip": "test_bash_and_fish_round_trip_empty_and_unset_environment",
    "unset-path": "test_fish_round_trip_truly_unset_path_for_saved_and_legacy_state",
    "umask": "test_fish_activation_preserves_callers_umask",
    "guards": "test_bash_and_fish_guards_and_init_failures_do_not_mutate_environment",
    "sessions": "test_bash_and_fish_share_sessions_and_isolate_distinct_sessions",
    "cross-shell-env": "test_cross_shell_inherited_deactivation_restores_tmux_presence_and_values",
    "shared-deactivate": "test_shared_session_can_be_deactivated_by_both_activated_shells",
    "absent-root": "test_deactivation_restores_environment_when_canonical_root_is_already_absent",
    "zsh-lifecycle": "test_zsh_repeated_activation_and_deactivation_restore_saved_environment",
    "cleanup": "test_bash_and_fish_cleanup_dead_records_but_preserve_live_session_files",
    "live-lock": "test_bash_and_fish_preserve_live_allocator_lock_before_wrapper_registration",
    "deactivate": "test_deactivation_rejects_unsafe_state_and_noncanonical_pids",
    "launcher-fallback": "test_launcher_passthrough_missing_install_and_missing_claude",
    "launcher-modes": "test_launcher_child_isolation_status_and_teammate_modes",
    "launcher-failure": "test_launcher_failed_activation_never_launches_claude_and_already_active_works",
    "launcher-wrapper": "test_installed_launcher_runs_actual_shared_wrapper_from_fish_environment",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=("fish",), default="fish")
    parser.add_argument("--case", choices=tuple(CASE_METHODS))
    args = parser.parse_args()
    if args.case:
        suite = unittest.TestSuite([FishTests(CASE_METHODS[args.case])])
    else:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(FishTests)
    outcome = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if outcome.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())

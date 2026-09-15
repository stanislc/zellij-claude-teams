#!/usr/bin/env python3
"""Attached, isolated Zellij regression check; never uses an existing session."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import pty
import shlex
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
import threading
import time
import uuid


def eventually(predicate, description, seconds=5):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError("timed out: " + description)


def run(repo, bash, result):
    zellij = shutil.which("zellij")
    if not zellij:
        raise RuntimeError("live suite requires zellij")
    result["zellij"] = subprocess.check_output([zellij, "--version"], text=True).strip()
    result["bash"] = subprocess.check_output([bash, "-c", 'printf "%s" "$BASH_VERSION"'], text=True)
    result["commit"] = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    result["working_tree_changes"] = subprocess.check_output(
        ["git", "-C", str(repo), "status", "--porcelain"], text=True).splitlines()
    session = "shim-test-" + uuid.uuid4().hex[:10]
    # Short paths avoid the Unix-domain socket path limit on macOS.
    with tempfile.TemporaryDirectory(prefix="zct-", dir="/tmp") as tmp:
        root = Path(tmp).resolve()
        state = root / "state"
        state.mkdir(mode=0o700)
        (state / "next_id").write_text("1\n")
        (state / "sessions").touch()
        env = {
            "PATH": os.pathsep.join(dict.fromkeys([str(Path(bash).parent), str(Path(zellij).parent), "/usr/bin", "/bin"])),
            "HOME": str(root), "TMPDIR": str(root), "TERM": "xterm-256color",
            "ZELLIJ_SOCKET_DIR": str(root / "sockets"),
            "ZELLIJ_SESSION_NAME": session, "ZELLIJ": "1",
            "ZELLIJ_TMUX_SHIM_STATE": str(state), "ZELLIJ_TMUX_SHIM_DIR": str(repo),
            "TMUX_PANE": "%0", "ZELLIJ_PANE_ID": "0",
            "XDG_CACHE_HOME": str(root / "cache"), "XDG_DATA_HOME": str(root / "data"),
            "XDG_CONFIG_HOME": str(root / "config"),
        }
        startenv = {k: v for k, v in env.items() if k not in ("ZELLIJ", "ZELLIJ_SESSION_NAME", "ZELLIJ_PANE_ID")}
        config = root / "config.kdl"
        config.write_text('show_release_notes false\nshow_startup_tips false\non_force_close "quit"\n')

        def z(*args):
            p = subprocess.run([zellij, "-s", session, "action", *args], env=env,
                               capture_output=True, text=True, timeout=10)
            if p.returncode:
                raise RuntimeError(f"Zellij {args}: {p.stderr.strip()}")
            return p.stdout

        def shim(*args):
            p = subprocess.run([bash, str(repo / "bin/tmux"), *args], env=env,
                               capture_output=True, text=True, timeout=10)
            if p.returncode:
                raise AssertionError(f"shim {args}: exit {p.returncode}: {p.stderr.strip()}")
            return p.stdout

        def panes():
            value = [p for p in json.loads(z("list-panes", "--all", "--json")) if not p["is_plugin"]]
            result["last_panes"] = value
            return value

        def observer_active():
            tabs = json.loads(z("list-tabs", "--all", "--json"))
            result["last_tabs"] = tabs
            return any(t.get("name") == "observer" and t.get("active") for t in tabs)

        client = None
        master = slave = None
        started = False
        terminal_tail = bytearray()
        try:
            # The finalizer covers partial setup as well as assertion failures.
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 120, 0, 0))

            def session_setup():
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

            started = True
            client = subprocess.Popen([zellij, "--config", str(config), "--data-dir", str(root / "zellij-data"),
                                       "--session", session], env=startenv,
                                      cwd=root, stdin=slave, stdout=slave, stderr=slave, preexec_fn=session_setup)
            os.close(slave)
            slave = None

            def drain(fd):
                try:
                    while True:
                        chunk = os.read(fd, 65536)
                        if not chunk:
                            break
                        terminal_tail.extend(chunk)
                        del terminal_tail[:-8192]
                except OSError:
                    pass

            threading.Thread(target=drain, args=(master,), daemon=True).start()
            # Build the two tabs through acknowledged actions. This avoids
            # startup-layout/default-layout differences across Zellij versions.
            def session_ready():
                try:
                    return panes()
                except RuntimeError:
                    return False

            eventually(session_ready, "attached session ready", seconds=10)
            z("rename-tab", "observer")
            observer_id = next(p["id"] for p in panes() if p["tab_name"] == "observer")
            z("write-chars", "--pane-id", str(observer_id), "exec /bin/sleep 300\n")
            z("new-tab", "--name", "leader")
            initial = eventually(lambda: [p for p in panes() if p["tab_name"] == "leader"], "leader ready")
            leader_id = initial[0]["id"]
            z("write-chars", "--pane-id", str(leader_id), "exec /bin/sleep 300\n")
            env["ZELLIJ_PANE_ID"] = str(leader_id)
            z("go-to-tab-name", "observer")
            eventually(observer_active, "observer tab active")
            assert client.poll() is None, "attached client exited"
            agent_ids = []
            for n, title in [(1, "test-researcher"), (2, "test-tester")]:
                assert shim("split-window", "-d", "-t", "%0", "-h", "-P", "-F", "#{pane_id}", "--", "cat") == f"%{n}\n"
                assert (state / f"{n}.fifo").is_fifo(), "placeholder did not defer"
                shim("select-pane", "-t", f"%{n}", "-T", title)
                marker_file = root / f"command-{n}"
                command = f"printf %s {shlex.quote(title)} > {shlex.quote(str(marker_file))}; /bin/sleep 120"
                shim("respawn-pane", "-k", "-t", f"%{n}", "--", command)
                eventually(lambda: marker_file.exists(), "command execution")
                assert marker_file.read_text() == title
                agent_ids.append(int((state / f"{n}.zellij_id").read_text().strip()))
            after = panes()
            agents = [next(p for p in after if p["id"] == zid) for zid in agent_ids]
            leader = next(p for p in after if p["id"] == leader_id)
            assert [p["title"] for p in agents] == ["test-researcher", "test-tester"]
            assert all(p["tab_name"] == "leader" for p in agents)
            assert agents[0]["pane_x"] > leader["pane_x"]
            assert agents[1]["pane_x"] == agents[0]["pane_x"]
            assert agents[1]["pane_y"] > agents[0]["pane_y"]
            assert observer_active(), "creation moved client focus"
            result["placement"] = after
            result["startup_and_placement"] = "pass"
            print("ok live.attached-two-tabs", flush=True)

            marker = "LIVE_INPUT_" + uuid.uuid4().hex[:10]
            shim("send-keys", "-t", "%1", marker, "Enter")
            eventually(lambda: marker in z("dump-screen", "--pane-id", str(agent_ids[0])), "late input reaches target")
            assert marker not in z("dump-screen", "--pane-id", str(observer_id))
            assert marker not in z("dump-screen", "--pane-id", str(leader_id))
            assert marker not in z("dump-screen", "--pane-id", str(agent_ids[1]))
            assert observer_active(), "late input moved client focus"
            result["targeted_late_input"] = "pass"
            print("ok live.late-input-target-only", flush=True)

            shim("kill-pane", "-t", "%1")
            eventually(lambda: all(p["id"] != agent_ids[0] for p in panes()), "first agent closes")
            remaining = {p["id"] for p in panes()}
            assert {agent_ids[1], observer_id, leader_id}.issubset(remaining)
            eventually(lambda: not list(state.glob("1.*")), "first agent state cleanup")
            result["kill_leaves_sibling"] = "pass"
            print("ok live.kill-leaves-sibling", flush=True)
        finally:
            result["terminal_tail"] = bytes(terminal_tail).decode("utf-8", errors="replace")
            if started:
                try:
                    cleanup = subprocess.run([zellij, "-s", session, "kill-session", session], env=startenv,
                                             capture_output=True, text=True, timeout=10)
                    result["cleanup_exit"] = cleanup.returncode
                except subprocess.SubprocessError as error:
                    result["cleanup_error"] = str(error)
            if client is not None:
                try:
                    client.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(client.pid, signal.SIGTERM)
                    client.wait(timeout=5)
            if slave is not None:
                os.close(slave)
            if master is not None:
                os.close(master)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--bash", default=os.environ.get("SHIM_TEST_BASH", "/bin/bash"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = {}
    try:
        run(args.repo.resolve(), args.bash, result)
        if result.get("cleanup_exit") != 0 or result.get("cleanup_error"):
            raise RuntimeError("isolated Zellij session cleanup failed")
        result["status"] = "pass"
    except (AssertionError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        result["status"] = "fail"
        result["error"] = str(error)
        print("not ok live: " + str(error), flush=True)
    finally:
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(result, indent=2) + "\n")
    return 0 if result.get("status") == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

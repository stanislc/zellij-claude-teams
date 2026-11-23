#!/usr/bin/env python3
"""Deterministic fake Zellij used by the core compatibility tests."""

import json
import os
from pathlib import Path
import subprocess
import sys


def enabled(name: str) -> bool:
    return os.environ.get(name, "1") == "1"


args = sys.argv[1:]
test_root = Path(os.environ["SHIM_TEST_ROOT"])
with (test_root / "zellij-actions.jsonl").open("a", encoding="utf-8") as log:
    log.write(
        json.dumps(
            {"argv": args, "issuer": os.environ.get("ZELLIJ_PANE_ID")},
            ensure_ascii=False,
        )
        + "\n"
    )

if "--help" in args:
    action = args[1] if len(args) > 1 else ""
    if action == "new-pane" and enabled("SHIM_TEST_CAP_NEW_PANE"):
        print("--no-focus")
    elif action == "rename-pane" and enabled("SHIM_TEST_CAP_RENAME_PANE"):
        print("--pane-id")
    elif action == "write-chars" and enabled("SHIM_TEST_CAP_WRITE_PANE"):
        help_mode = os.environ.get("SHIM_TEST_WRITE_HELP_MODE", "normal")
        if help_mode == "long":
            print("--pane-id")
            print("x" * (2 * 1024 * 1024))
        elif help_mode == "failed-advertise":
            print("--pane-id")
            raise SystemExit(17)
        else:
            print("--pane-id")
    raise SystemExit(0)

action = args[1] if len(args) > 1 and args[0] == "action" else ""
failure = {
    "focus-pane-id": ("SHIM_TEST_FAIL_FOCUS", 23),
    "write-chars": ("SHIM_TEST_FAIL_WRITE", 19),
}.get(action)
if failure and os.environ.get(failure[0]) == "1":
    raise SystemExit(failure[1])

if action == "new-pane":
    command = args[args.index("--") + 1 :]
    pane_key = command[-1].lstrip("%")
    zellij_id = str(100 + int(pane_key))
    child_env = os.environ.copy()
    child_env["ZELLIJ_PANE_ID"] = zellij_id
    wrapper_log = (test_root / f"wrapper-{pane_key}.log").open(
        "w", encoding="utf-8"
    )
    child = subprocess.Popen(
        [os.environ["SHIM_TEST_BASH"], *command],
        env=child_env,
        stdin=subprocess.DEVNULL,
        stdout=wrapper_log,
        stderr=wrapper_log,
        start_new_session=True,
    )
    wrapper_log.close()
    with (test_root / "owned-processes").open("a", encoding="ascii") as owned:
        owned.write(f"{child.pid}\n")
    print(f"terminal_{zellij_id}")

# Stabilization acceptance matrix

**Scope update, 2026-09-15:** This is the catalogue for the earlier broad design. The [active selective maintenance plan](../plans/2026-09-15-selective-maintenance.md) selects current work and relevant checks. Its focused task does not require implementing all cases, the full v2 protocol, fish, or every #6 component. The complete suite/gate definitions below apply only if that broader scope is selected later.

This is the test specification for the [detailed design](2026-09-14-repository-cleanup-design.md), not a report of tests already implemented. Historical results are in the [audit](../reviews/2026-09-14-pr-audit.md).

## Harness contract

Create `tests/run.sh` with `--suite core|fish|capabilities|live` and `--case ID` selection. Default to core. Emit the selected absolute interpreter paths/versions, one `ok`/`not ok` line per case, and an aggregate count. An explicit suite missing an interpreter or required capability fails; a CI job must not pass by skipping its required suite.

Suite membership is explicit: core contains protocol/placement/input/argv/delivery/state/shell/install cases and `interrupt.no-text-fallthrough`; fish contains `fish.*`; capabilities contains `capture.*` and `layout.*`; live contains the three `live.*` cases plus `interrupt.terminal-semantics`. The interrupt live case is mandatory at M2c/M3, not a deferred optional test. Cases enter the maintained runner at their implementation milestone; the final core gate requires the complete core set.

Use `SHIM_TEST_BASH` to select the interpreter for both shim and wrapper. Fake Zellij launches the actual wrapper with that absolute interpreter, not whichever Bash its shebang happens to find. Installed-copy tests separately exercise normal executable/shebang invocation. Use real `zsh -f` and `fish --no-config` for shell lifecycle tests.

Each case owns a fresh private temporary directory, explicit minimal environment, controlled child processes, and cleanup. Preserve sentinel files outside the case's approved state/install subtree. Never enumerate or terminate the developer's existing teams. Log arguments as records preserving boundaries; joined `$*` logs cannot prove argv fidelity. Do not archive environment snapshots or command payloads from real user processes.

Default watchdog: 15 seconds per ordinary case, 25 for lock-timeout cases, 310 for the real 300-second idle timeout case, and 90 for live integration. The suite has a 15-minute job budget. Readiness/delivery timeout assertions allow at most one poll interval beyond their five-second deadline. A killed or timed-out harness must reap its own reader/writer/client children.

Fixture dimensions are independent: `new-pane --no-focus`, targeted rename, targeted text write, targeted byte write, targeted close, targeted dump, and legacy focus. Include a long help output and an advertised capability whose operation fails. Do not use one `modern=true` switch for every capability.

## Core cases

| ID | Setup and operation | Required observable result |
|---|---|---|
| `protocol.deferred-split` | Exact #8 sequence with split `-- cat`, title, respawn shell program | Exact `%1\n`; no execution before respawn; intended marker afterward |
| `protocol.deferred-window` | New-window with `-- cat`, then respawn | Same deferral/acceptance contract, correct creation name |
| `protocol.inline-argv` | Inline Bash command with a spaced argument and output path | Exact output bytes, no argument splitting |
| `protocol.fifo-send` | Split without payload, then legacy send-keys launch | Command executes once through the waiting FIFO |
| `protocol.synthetic-stdout` | Fake Zellij prints an actual ID and diagnostics | Only synthetic ID on shim success stdout; failure stdout empty |
| `protocol.recorded-title` | Baseline deferred startup with select-pane -T researcher | Real wrapper applies the recorded title to its own pane |
| `protocol.title-precedence` | Explicit title, argv agent name, window name, and rename failure profiles | Chosen precedence; correct target; rename warning does not deny launch acceptance |
| `protocol.placeholder-boundary` | `cat`, `cat file`, shell program containing cat, respawn cat | Only exactly one creation argument `cat` defers |
| `protocol.unknown-command` | Unknown command/option and missing global option value | Status 2 before state mutation; no real-tmux forwarding |
| `protocol.documented-noops` | Observed #8/#9 compatibility option/layout calls | Status 0 with no unintended pane operations |
| `placement.first-leader` | First split from leader 10 | Right/default direction anchored to 10, independent of focused pane on capable backend |
| `placement.next-live-sibling` | Several siblings including dead highest ID | Down from highest verified live sibling; ignore stale records |
| `placement.other-leader-anchor` | Baseline two-leader spawn fixture | Each group's first creation uses its own leader anchor |
| `placement.other-leader` | Two leader groups in one session | No cross-group predecessor, listing, or accidental shared `%0` mapping |
| `placement.concurrent-siblings` | Two overlapping spawns in one group | Unique IDs and first-right/second-down sequence; no duplicate first anchor |
| `placement.capability-gate` | Neither capability, no-focus only, both creation+rename | First two use legacy; both use targeted creation; legacy new-window name retained |
| `placement.teardown-during-create` | Pause after reservation, begin deactivation, resume wrapper | Registration rejected, command never executes, no leaked created pane after bounded cleanup |
| `input.targeted-late-write` | FIFO consumed, target `%7` maps to 107, focus elsewhere | Write explicitly targets 107; focus unchanged |
| `input.legacy-focus-failure` | Targeted write unavailable; injected focus failure | Nonzero; no text write follows |
| `input.write-failure` | Targeted or legacy write fails | Nonzero; no retry against focused pane |
| `input.invalid-target` | Missing, stale, malformed, plugin, leading-zero, foreign-group target | Correct syntax/runtime error; no Zellij side effect |
| `input.contextual-host` | `%0` from leader and from an agent | Both map to that group's leader; host kill/respawn rejected |
| `input.display-target` | `display-message -p '#{pane_id}' -t %7` | `%7\n`, including post-format option order; absent -t reports caller |
| `input.help-probe` | Long help text, failed help, independent write support | No false SIGPIPE downgrade; correct independent capability choice |
| `argv.single-shell-string` | Shell operators, quotes, embedded/trailing newlines | Shell program bytes preserved into frame and intended result produced |
| `argv.literal-boundaries` | Multiple argv with `&&`, `$`, quotes, spaces as data | Exact literal arguments, no unintended expansion/execution |
| `argv.empty-argument` | Empty non-command argv entry | Empty entry retained; empty launch rejected |
| `argv.spaced-executable` | Executable filename containing spaces | Intended executable invoked |
| `argv.command-word` | argv[0] resembles reserved syntax, assignment, or option | Treated as command name, never shell control/assignment/command-builtin option |
| `argv.payload-socket-options` | Payload `-S`, `-L`, `-t` after command start or -- | Payload unchanged; only initial global socket flags consumed |
| `argv.exec-supervision` | Raw program uses exec and changes its own traps/options | Registered supervisor identity remains routable; final cleanup still occurs |
| `delivery.absent-target` | Respawn lacks target or target has no reserved agent | Nonzero, no launch |
| `delivery.empty-command` | Respawn with no payload or empty shell string | Nonzero, no acceptance receipt |
| `delivery.consumed-fifo` | Second launch after acceptance | Nonzero, first command executes exactly once |
| `delivery.concurrent-claim` | Two senders race one waiting pane | Exactly one claim/accepted launch; loser fails even before FIFO unlink |
| `delivery.dead-reader-timeout` | FIFO exists but no reader | Writer open/write bounded, child reaped, no false success |
| `delivery.partial-frame` | Program begins with a marker command; writer stops mid-body without NUL | Marker never created; incomplete command never evaluated |
| `delivery.extra-frame-data` | Valid terminator followed by more bytes | Reject entire delivery before evaluation |
| `delivery.fast-exit-receipt` | Command exits before sender's next poll | Sender authenticates durable accepted receipt after wrapper exit |
| `delivery.unknown-outcome` | Delay receipt observation after complete write | Nonzero with unknown outcome; no automatic resend, kill, or live-file deletion |
| `delivery.idle-timeout` | Waiting wrapper receives nothing for 300 seconds | Exit and owned reader/state cleanup within deadline plus poll allowance |

## State, shells, and installation

| ID | Setup and operation | Required observable result |
|---|---|---|
| `state.namespace` | Same raw session, equivalent physical runtime aliases, unusual characters | Deterministic v2 path under physical root; schema and exact raw identity validated |
| `state.collision` | Existing basename with mismatching session.raw | Refuse joining rather than sharing state |
| `state.reject-without-export` | Missing helper, bad root, failed mkdir/chmod, wrong owner | Status nonzero; caller environment/options/umask identical before and after |
| `state.canonical-containment` | Root itself, `..`, symlink child, forged outside path, wrong object type | No sentinel outside permitted pane records removed or modified |
| `state.path-idempotence` | Shim absent, first, later, duplicated; PATH with empty elements | Exactly one first shim entry; remaining ordering/empty elements preserved |
| `state.concurrent-allocation` | Concurrent controlled creators | Unique monotonic IDs, matching tokens and reservations |
| `state.counter-corruption` | Missing/corrupt/populated or exhausted counter | Explicit failure, never ID reset/reuse |
| `state.live-lock-survives-activation` | Held lock, including paused before owner publication | Activation waits/fails boundedly; never removes the lock |
| `state.lock-owner-release` | Normal exit, TERM, mismatched token, SIGKILL orphan | Only matching owned mutex released; orphan fails closed; durable claim is not auto-released |
| `state.snapshot-isolation` | Two leaders with different exported values and multiline text | Each agent receives its own intact values; own Zellij ID retained; N.env removed after restore |
| `state.identity-reuse` | Corrupt birth stamp/token or stale mapping from restarted session | No write/close to an unrelated reused actual pane ID |
| `state.cleanup-owned-files` | Normal exit, registration failure, kill during FIFO read | Owned transient files/reader removed; unrelated pane and retained receipt unaffected |
| `state.receipt-retirement` | Fast-exited pane with unconsumed result, then acknowledgment/teardown | Receipt remains authenticatable; terminal reservation is not considered an in-flight spawn |
| `shell.zsh-empty-deactivate` | Fresh zsh, no PID files | Status 0, environment restored, no NOMATCH failure |
| `shell.populated-deactivate` | Several controlled groups/panes, then deactivate | Session-wide intended closure; no outside process/pane touched |
| `shell.original-environment-restore` | TMUX/TMUX_PANE unset, empty, and preexisting values | Set/unset distinction and initial PATH baseline restored |
| `shell.teardown-failure` | A verified pane/lock cannot safely finish cleanup | Caller environment restored, status 1, closing and relevant state retained |
| `shell.reactivate-after-close` | Completed teardown and preserved counter | Fresh activation succeeds without ID reuse; unfinished close remains blocked |
| `shell.legacy-state-refusal` | Legacy ACTIVE/state or mismatched current session | Clear failure without modifying old environment/FIFOs/state |
| `install.spaced-xdg-root` | Temporary data/config/runtime paths with spaces | Complete installed manifest and functional activation |
| `install.manifest-and-modes` | Compare source manifest with installed copy | Matching hashes; executables executable; helper present; tests not installed |
| `install.protocol-from-copy` | Checkout absent from PATH and unavailable as helper fallback | Deferred and legacy protocols work entirely from installed copy |
| `install.update` | Existing owned older installation, quiescent teams | Correct replacement; documented active-state restriction; unrelated files preserved |
| `install.uninstall-isolated` | Sibling sentinel directories and caller shell | Only install-owned files removed; no claim to restore parent shell from child installer |

## Fish, terminal controls, and optional capabilities

| ID | Setup and operation | Required observable result |
|---|---|---|
| `fish.shared-state` | Bash and fish prepare the same session | Same canonical path/schema, compatible records, no destruction of a live lock |
| `fish.activation-rollback` | Outside Zellij and each helper validation failure | Correct status; parent unchanged |
| `fish.path-and-restore` | Re-source, empty deactivation, saved PATH/TMUX variants | Same lifecycle semantics as bash/zsh |
| `fish.wrapper-argv-env-status` | Stub Claude; inside/outside/already active/missing install | Exact argv/environment/status; explicit teammate-mode choice honored without duplicate defaults |
| `fish.parent-unchanged` | On-demand claude-zellij child run | No parent fake TMUX/PATH/teams flag leakage |
| `fish.function-update-uninstall` | Temporary fish config root, both installers | Installed/autoload function paths agree and remain isolated from real config |
| `interrupt.terminal-semantics` | Attached PTY, foreground parent/child, raw receiver, unrelated process | Intended foreground SIGINT in canonical mode; byte 3 in raw mode; unrelated process alive |
| `interrupt.no-text-fallthrough` | C-c alone and pending pane | No newline/empty launch; pending control rejects; unsupported backend fails visibly |
| `capture.targeted-bytes` | Distinct pane contents, trailing blank lines, empty viewport | Target-only exact stdout, no focus change; correct caller default and contextual host |
| `capture.unsupported-flags` | Buffer/range requests beyond -p / -S - | Status 2; no misleading partial or empty success |
| `capture.failure` | Missing target/capability, dump operation failure | Nonzero; no focus-based retry |
| `layout.first-versus-sibling` | Environment unset/right/down/invalid, -h/-v, multiple groups | Defined first-agent precedence; later siblings down; invalid config fails before reservation |

## Attached live integration

`live.attached-two-tabs` creates a uniquely named disposable Zellij session under its own socket/cache/data directories and an attached PTY client. Create observer and leader tabs in the initial layout, use harmless controlled programs, and wait for real readiness. Park client focus in observer and create two agents from leader through the actual shim.

Required results: both commands execute; synthetic output is exact; titles and right-column vertical geometry are correct; observer remains visible/focused. `live.late-input-target-only` sends a unique marker to the first agent and uses targeted screen dumps to prove it appears only there. `live.kill-leaves-sibling` closes that agent and proves the second and observer remain, with first-agent transient state removed.

The finalizer closes only the test's session, reaps the client, and checks its process/state cleanup. A detached session is insufficient for the focus assertion. Record the tested Git commit and exact Zellij version. Re-run for the core and each later integrated capability that affects input, layout, or teardown.

## CI and evidence ledger

| Required job | Interpreter enforcement | Suites |
|---|---|---|
| Ubuntu core | Absolute current Bash plus actual zsh | core |
| macOS system Bash | `/bin/bash`, version must be 3.2; actual zsh | core |
| macOS current Bash | Resolved installed current Bash; same binary for wrapper | core |
| Ubuntu/macOS fish, after fish integration | Actual fish --no-config with version recorded | fish plus core regression |
| Capability integration jobs | Same supported Bash/platform matrix | capabilities plus core |
| Live merge gate | Declared Zellij version and attached PTY | live; automated if reliable, otherwise recorded manual gate |

Run syntax on every maintained script/helper individually. ShellCheck must include new shell files and use narrow justified exclusions. Compare whitespace against the actual PR merge base, with complete Git history available. Select and pin CI action revisions from their official repositories when implementing the workflow; record the chosen revisions in the workflow review.

Each milestone adds a row to `docs/verification/repository-stabilization.md`: milestone, commit, OS, interpreter versions, Zellij/fish versions where applicable, named case totals, command/result, live evidence location, and remaining limitations. Generated artifacts contain only controlled fixture data. Authenticated Claude testing is recorded separately as pass/fail/not-run with version and scenario; stand-in execution never counts as that pass.

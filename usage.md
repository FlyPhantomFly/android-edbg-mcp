# Usage

## Bringing the bridge up

After a reboot, a phone reconnect, or an adb restart:

```bash
./restore.sh
```

Reading the output:

- `[skip] no adb device attached` — the phone isn't plugged in (or shows as
  `unauthorized` in `adb devices`). Fix that and re-run.
- `[ok] eDBG binary on device matches` / `[ok] eDBG daemon ...` / `[ok] adb forward ...` —
  the three halves being put right, in order.
- `MCP endpoint reachable` — the final proof; a JSON-RPC initialize got a
  `200` through the whole chain.

If the daemon line fails, the script prints the on-device log
(`/data/local/tmp/edbg_mcp.log`), which is where the real error lives.

To check reachability without touching anything:

```bash
curl -s -m 5 -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"check","version":"0"}}}' \
  http://127.0.0.1:19810/mcp
```

Any JSON response means the endpoint is alive. `adb forward --list` shows the
current forwards.

## Talking to the debugger

The server starts in standby: it will not launch anything by itself and there
is no startup breakpoint. Which tools work depends on where you are. `status`
(always available) reports connectivity, attach state, run state, and the
suggested next step. Before `attach`, every other tool returns guidance
instead of executing.

Always available:

| Tool | What it does |
|---|---|
| `status` | Connectivity, attach state, run state, next-step suggestion |
| `attach` | Select the target `package` + `library`; does not launch the app. Re-attach to switch targets |
| `quit` | Clear the debug context and return to standby; does not stop the server |

After `attach`, in standby:

| Tool | What it does |
|---|---|
| `break` | Set a breakpoint — virtual offset, absolute address, or `lib.so+0xOFFSET`; mapped to `vbreak` internally |
| `info_break` | List breakpoints |
| `enable_breakpoint` / `disable_breakpoint` / `delete_breakpoint` | Manage breakpoints by id |
| `info_file` | Info about the target library file |
| `run` | Enter the waiting state (an implicit `continue`), launch the attached app via `am start`, then wait for the first hit. Refuses to run without at least one enabled breakpoint |
| `continue` | Resume and block until the next hit. Not available before the first `run` |
| `wait_stop` | Keep waiting on the current run without sending another `continue` — the way to take over after a `continue`/`run` timeout |
| `cancel_run` | Cancel the pending wait, stop the probes, stay attached with breakpoints intact |

Only while stopped at a breakpoint hit:

| Tool | What it does |
|---|---|
| `examine` | Read memory (length expression, or `ptr`/`str`/`int`) |
| `dump` | Dump memory to a file |
| `list` | Disassemble at the current or a given address |
| `backtrace` | Call stack (`unwind` or `fp` mode) |
| `info_register` / `info_thread` | Registers, threads |
| `set_symbol` | Name an address |
| `write_memory` | Write hex bytes into memory |
| `thread` | Thread filters (`list`/`add`/`name`/`del`/`all`) |

Every wait is capped at 90000 ms server-side (`timeout_ms` default and max),
so a call always returns before the MCP client's own timeout does. The server
also exposes an `edbg://guide/mcp` resource with the authoritative workflow
notes.

`--mcp` mode forces uprobe preference and virtual-address display
(`-prefer uprobe -show-vertual`, upstream's spelling). To use a different
port, start the daemon with `--mcp-port N` and change the forward and the
client URL to match.

## Client configuration

OpenCode (`~/.config/opencode/opencode.json`):

```json
"edbg": {
  "type": "remote",
  "url": "http://127.0.0.1:19810/mcp",
  "enabled": true
}
```

For everything else, the upstream installer handles it — it writes each
client's native format (JSON or TOML; Codex lands in `~/.codex/config.toml`):

```bash
./bin/edbg-mcp-install_linux_arm64 --list-clients
./bin/edbg-mcp-install_linux_arm64 --install --clients codex,cursor,claude
./bin/edbg-mcp-install_linux_arm64 --uninstall --clients codex,cursor
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ECONNREFUSED` in the client | `./restore.sh` — covers essentially every case |
| restore says `[skip] no adb device` | plug the phone in; check `adb devices` for `unauthorized` |
| daemon won't start | read the device log shown by the script; usually a kernel without eBPF/uprobes, or SELinux state changed after an update |
| port already in use | a stale eDBG on the device: `adb shell "su -c 'pkill eDBG'"`, then re-run restore |
| device binary is outdated | restore compares md5 against `bin/eDBG_v2.3.0` and re-pushes on mismatch — drop the new release build into `bin/` and re-run |

## Automation

`systemd/edbg-mcp-restore.service` runs `restore.sh` once at login. It waits
up to 10 s for the phone to enumerate, and exits 0 with a `[skip]` note when
the device is genuinely unplugged:

```bash
mkdir -p ~/.config/systemd/user
cp systemd/edbg-mcp-restore.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now edbg-mcp-restore.service
```

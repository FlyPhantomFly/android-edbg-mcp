# edbg-mcp

MCP server for [eDBG](https://github.com/ShinoLeah/eDBG), an eBPF-based
dynamic debugger for Android. It lets an AI agent attach to an app, set
breakpoints, and follow execution from any MCP client — OpenCode, Claude,
Codex, and others.

The setup is a two-machine bridge, and that's the part people get wrong:

```
MCP client (host)
  └─ http://127.0.0.1:19810/mcp    ← loopback, backed by adb
       └─ adb forward tcp:19810 tcp:19810
            └─ eDBG --mcp on the phone (root: /data/local/tmp/eDBG)
                 └─ eBPF uprobes on the target app
```

Nothing listens on the host's port 19810 by itself. If the phone reboots,
gets unplugged, or the adb server restarts, the bridge is gone and the client
reports `ECONNREFUSED`. The `restore.sh` script in this repo puts both halves
back in a few seconds, so most "it's broken" moments are one command:

```bash
./restore.sh
```

## What's in the repo

| Path | What it is |
|---|---|
| `restore.sh` | Idempotent bring-up: pushes the binary if the device lost it, starts the daemon, sets the forward, verifies the endpoint |
| `bin/eDBG_v2.3.0` | Device binary (aarch64), **rebuilt from the v2.3.0 tag** — the official release zip pairs its embedded `ebpf_module.o` with a stale `min_core_btf` and fails to load probes on kernels without `CONFIG_DEBUG_INFO_BTF` (see troubleshooting) |
| `bin/edbg-mcp-install_linux_arm64` | Host-side installer that writes MCP config into other clients (`--install`); not needed for OpenCode |
| `docs/README_mcp_en.md` | Upstream MCP documentation (runtime behavior, installer flags) |
| `systemd/edbg-mcp-restore.service` | Optional: re-runs `restore.sh` at login |

## Quick start

1. Phone attached over adb, rooted, kernel with eBPF and uprobes (details in
   eDBG's own README).
2. `./restore.sh` — expect `[ok]` lines ending with the endpoint check.
3. Point the client at `http://127.0.0.1:19810/mcp`. For OpenCode
   (`~/.config/opencode/opencode.json`):

```json
"edbg": {
  "type": "remote",
  "url": "http://127.0.0.1:19810/mcp",
  "enabled": true
}
```

4. Reload the client (`/reload` in OpenCode, or restart the session).

Day-to-day use, tool behavior, and troubleshooting are in [usage.md](usage.md).

## Upstream

eDBG is by ShinoLeah, MIT-licensed (`LICENSE`). The doc under `docs/` is
upstream's. The device binary in `bin/` is rebuilt from the v2.3.0 tag —
the upstream release zip ships a broken eBPF/BTF pairing for kernels
without `CONFIG_DEBUG_INFO_BTF` (details in the troubleshooting table of
`usage.md`). This repo adds the restore script, the systemd unit, the
rebuilt binary, and documentation.

#!/usr/bin/env bash
# edbg-bridge-check.sh — watchdog probe for the eDBG MCP bridge.
#
# Designed for a systemd user timer: exits 0 silently while the endpoint
# answers, and only calls restore.sh when it is actually down. All repair
# output goes to the journal of the calling unit.
#
# The probe is a JSON-RPC initialize POST — a plain GET opens a long-lived
# SSE stream that never completes.
set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${EDBG_PORT:-19810}"
URL="http://127.0.0.1:${PORT}/mcp"

if curl -sS -m 5 -o /dev/null -X POST \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"watchdog","version":"0"}}}' \
    "${URL}" 2>/dev/null; then
  exit 0
fi

echo "[..] ${URL} unreachable — running restore.sh"
exec "${REPO_DIR}/restore.sh"

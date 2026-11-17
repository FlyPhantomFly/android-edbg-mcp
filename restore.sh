#!/usr/bin/env bash
# restore.sh — bring the eDBG MCP bridge back up. Idempotent, safe to re-run.
#
# The MCP HTTP server runs ON the Android device (root); the host only sees it
# through an adb port-forward. This script fixes both halves:
#   1. push bin/eDBG_v2.3.0 to the device if /data/local/tmp/eDBG is missing or stale
#   2. start `eDBG --mcp` on the device if it is not already running
#   3. adb forward tcp:19810 -> tcp:19810
#   4. verify the endpoint with a JSON-RPC initialize (POST — a plain GET opens
#      a long-lived SSE stream that never completes)
#
# With no phone attached it exits 0 after a [skip] note, so a systemd oneshot
# stays green when the device is unplugged. Set EDBG_WAIT=<seconds> to have it
# wait for the phone to show up (the systemd unit sets EDBG_WAIT=10).
set -euo pipefail

PORT=19810
DEVICE_BIN=/data/local/tmp/eDBG
URL="http://127.0.0.1:${PORT}/mcp"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="${REPO_DIR}/bin/eDBG_v2.3.0"
EDBG_WAIT="${EDBG_WAIT:-0}"

ADB="$(command -v adb || true)"
[ -n "${ADB}" ] || ADB="${HOME}/Android/Sdk/platform-tools/adb"
[ -x "${ADB}" ] || { echo "[FAIL] adb not found (looked in PATH and ~/Android/Sdk/platform-tools)" >&2; exit 1; }
[ -f "${LOCAL_BIN}" ] || { echo "[FAIL] ${LOCAL_BIN} missing" >&2; exit 1; }

device_up() { "${ADB}" devices 2>/dev/null | awk 'NR>1 && $2=="device"{f=1} END{exit !f}'; }

# 0) wait a little for the phone, then bail out cleanly if there is none ------
waited=0
until device_up; do
  if [ "${EDBG_WAIT}" -le 0 ] || [ "${waited}" -ge "${EDBG_WAIT}" ]; then
    echo "[skip] no adb device attached — nothing to do"
    exit 0
  fi
  sleep 2
  waited=$((waited + 2))
done
SERIAL="$("${ADB}" get-serialno 2>/dev/null || echo '?')"

# 1) device-side binary -------------------------------------------------------
remote_md5="$("${ADB}" shell "su -c 'md5sum ${DEVICE_BIN}'" 2>/dev/null | awk '{print $1}' || true)"
local_md5="$(md5sum "${LOCAL_BIN}" | awk '{print $1}')"
if [ "${remote_md5}" != "${local_md5}" ]; then
  echo "[..] pushing eDBG binary to ${DEVICE_BIN} (missing or stale on device)"
  "${ADB}" push "${LOCAL_BIN}" "${DEVICE_BIN}" >/dev/null
  "${ADB}" shell "su -c 'chmod 755 ${DEVICE_BIN}'"
else
  echo "[ok] eDBG binary on device matches bin/eDBG_v2.3.0"
fi

# 2) device-side daemon -------------------------------------------------------
if "${ADB}" shell "su -c 'ps -A'" 2>/dev/null | grep -q "[e]DBG"; then
  echo "[ok] eDBG daemon already running on device (${SERIAL})"
else
  echo "[..] starting eDBG --mcp on device (root, detached)"
  "${ADB}" shell "su -c 'nohup ${DEVICE_BIN} --mcp </dev/null >/data/local/tmp/edbg_mcp.log 2>&1 &'"
  sleep 3
  if "${ADB}" shell "su -c 'ps -A'" 2>/dev/null | grep -q "[e]DBG"; then
    echo "[ok] eDBG daemon started on device"
  else
    echo "[FAIL] daemon did not start; device log:" >&2
    "${ADB}" shell "su -c 'cat /data/local/tmp/edbg_mcp.log'" >&2 || true
    exit 1
  fi
fi

# 3) host-side adb forward ----------------------------------------------------
"${ADB}" forward "tcp:${PORT}" "tcp:${PORT}"
echo "[ok] adb forward tcp:${PORT} -> tcp:${PORT} (${SERIAL})"

# 4) verify -------------------------------------------------------------------
code="$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"edbg-restore","version":"0"}}}' \
  "${URL}" || echo 000)"
if [ "${code}" = "200" ]; then
  echo "[ok] MCP endpoint reachable at ${URL}"
  echo "     reconnect the client: /mcps to check, /reload (or restart) to retry"
else
  echo "[FAIL] ${URL} not reachable from host (HTTP ${code})" >&2
  exit 1
fi

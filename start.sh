#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

# Start daemon if not already running
if ! curl -sf http://127.0.0.1:47821/health >/dev/null 2>&1; then
  nohup node "$DIR/daemon/server.mjs" >/tmp/dumpling-daemon.log 2>&1 &
  sleep 0.5
fi

# Build if binary missing, then launch HUD
BIN="$DIR/hud-app/.build/debug/Dumpling"
if [ ! -x "$BIN" ]; then
  (cd "$DIR/hud-app" && swift build)
fi

nohup "$BIN" >/tmp/dumpling-hud.log 2>&1 &
echo "Dumpling running (daemon: http://127.0.0.1:47821)"

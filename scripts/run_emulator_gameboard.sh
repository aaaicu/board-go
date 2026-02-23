#!/usr/bin/env bash
# run_emulator_gameboard.sh
#
# Runs GameBoard on the Android emulator using the Mac's actual LAN IP,
# so external devices (iPhone, real phone) can connect on the same Wi-Fi.
#
# Requires:
#   - adb (Android SDK, usually in ~/Library/Android/sdk/platform-tools)
#   - socat  →  brew install socat
#
# Usage:
#   bash scripts/run_emulator_gameboard.sh [emulator-ID]
#   e.g. bash scripts/run_emulator_gameboard.sh emulator-5554

set -euo pipefail

FLUTTER="bash /Users/masbot/fvm/versions/stable/bin/flutter"
DEVICE="${1:-emulator-5554}"
PORT=8080

# ── 1. Mac LAN IP ──────────────────────────────────────────────────────────
HOST_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
if [[ -z "$HOST_IP" ]]; then
  echo "❌  Mac LAN IP를 찾을 수 없습니다. Wi-Fi가 연결되어 있는지 확인하세요."
  exit 1
fi
echo "✅  Mac LAN IP: $HOST_IP"

# ── 2. adb forward: Mac localhost:PORT → emulator:PORT ────────────────────
if command -v adb &>/dev/null; then
  adb -s "$DEVICE" forward tcp:$PORT tcp:$PORT
  echo "✅  adb forward tcp:$PORT tcp:$PORT"
else
  echo "⚠️   adb not found — skipping adb forward"
fi

# ── 3. socat: LAN_IP:PORT → localhost:PORT (iPhone → Mac → emulator) ──────
if command -v socat &>/dev/null; then
  # Kill any existing socat on this port
  pkill -f "socat.*$PORT" 2>/dev/null || true
  socat TCP-LISTEN:$PORT,fork,reuseaddr,bind="$HOST_IP" TCP:127.0.0.1:$PORT &
  SOCAT_PID=$!
  echo "✅  socat relay started (PID $SOCAT_PID): $HOST_IP:$PORT → localhost:$PORT"
  trap "kill $SOCAT_PID 2>/dev/null || true; echo 'socat 종료'" EXIT
else
  echo "⚠️   socat not found — 외부 기기가 연결되지 않을 수 있습니다."
  echo "     brew install socat 후 다시 실행하세요."
fi

# ── 4. Flutter run with HOST_IP injected ──────────────────────────────────
echo ""
echo "🚀  Flutter 실행 중 (HOST_IP=$HOST_IP)..."
$FLUTTER run -d "$DEVICE" --dart-define="HOST_IP=$HOST_IP"

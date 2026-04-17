#!/usr/bin/env bash
# Build the Flutter Web GameNode and copy the output into assets/web_node/
# so the iPad shelf server can bundle and serve it.
#
# Usage: bash scripts/build_web_node.sh
# Run this before `flutter build` or `flutter run` for the iPad target whenever
# the GameNode web UI changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

echo "▶ Building Flutter Web GameNode..."
cd "$ROOT"
flutter build web --release \
  --web-renderer canvaskit \
  --dart-define=BOARD_GO_ROLE=gamenode

echo "▶ Copying to assets/web_node/..."
rm -rf assets/web_node
mkdir -p assets/web_node
cp -R build/web/. assets/web_node/

echo "✓ Done — assets/web_node/ is ready."
echo "  Now run 'flutter run -d <ipad-device-id>' to bundle and deploy."

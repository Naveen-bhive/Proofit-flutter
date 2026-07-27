#!/usr/bin/env bash
# Run ProofIt on a physical device against the dev API on this machine.
# Auto-detects LAN IP so you don't need to update URLs when Wi‑Fi changes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Prefer Wi‑Fi / Ethernet; skip docker0 and loopback
LAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')"
if [[ -z "${LAN_IP:-}" ]]; then
  LAN_IP="$(hostname -I | awk '{print $1}')"
fi

API_BASE="http://${LAN_IP}:3000/api"
SOCKET_URL="http://${LAN_IP}:3000"

echo "Dev API:  ${API_BASE}"
echo "Health:   http://${LAN_IP}:3000/health  (open on phone browser to verify)"
if command -v keytool >/dev/null 2>&1 && [[ -f "${HOME}/.android/debug.keystore" ]]; then
  SHA1="$(keytool -list -v -keystore "${HOME}/.android/debug.keystore" -alias androiddebugkey -storepass android -keypass android 2>/dev/null | awk -F': ' '/SHA1:/{print $2; exit}')"
  if [[ -n "${SHA1:-}" ]]; then
    echo "Debug SHA-1: ${SHA1}  (Firebase → Project settings → com.bhive.proofit → Add fingerprint if Google Sign-In fails)"
  fi
fi
echo ""

DEVICE="${1:-}"
FLUTTER_ARGS=()
if [[ -n "$DEVICE" ]]; then
  FLUTTER_ARGS+=(-d "$DEVICE")
fi

export PATH="${HOME}/flutter/bin:${HOME}/Android/Sdk/platform-tools:${PATH}"

exec flutter run "${FLUTTER_ARGS[@]}" \
  --dart-define=API_BASE_URL="${API_BASE}" \
  --dart-define=SOCKET_URL="${SOCKET_URL}" \
  --dart-define=GOOGLE_SERVER_CLIENT_ID="${GOOGLE_SERVER_CLIENT_ID:-971087084860-53cgc2l6lhk7ogn1rnq7lkmqu0jmaqak.apps.googleusercontent.com}" \
  --dart-define=GOOGLE_MAPS_API_KEY="${GOOGLE_MAPS_API_KEY:-AIzaSyCMWX4y7t-DGwyH6R3hDMDNNh4Ed0ZVmeI}"

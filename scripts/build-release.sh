#!/usr/bin/env bash
# Build Release PaneKit to a stable path and sign with a stable local identity
# so Accessibility (TCC) survives rebuilds. Ad-hoc signing uses a CDHash that
# changes every build → macOS asks for permission again.
#
# Usage: ./scripts/build-release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/Release"
APP_SRC="$OUT/PaneKit.app"
DEST_DIR="${HOME}/Applications"
DEST="$DEST_DIR/PaneKit.app"

mkdir -p "$OUT" "$DEST_DIR"

IDENTITY="$("$ROOT/scripts/ensure-local-signing-identity.sh" | tail -1)"
echo "→ Signing identity: $IDENTITY"

echo "→ Building PaneKit (Release) → $OUT"
# Leftover codesign temps from interrupted builds break the next CodeSign step.
find "$OUT" "$ROOT/build/DerivedData" -name '*.cstemp' -delete 2>/dev/null || true
xcodebuild \
  -project "$ROOT/PaneKit.xcodeproj" \
  -scheme PaneKit \
  -configuration Release \
  -derivedDataPath "$ROOT/build/DerivedData" \
  CONFIGURATION_BUILD_DIR="$OUT" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  build

if [[ ! -d "$APP_SRC" ]]; then
  APP_SRC="$(find "$ROOT/build/DerivedData/Build/Products/Release" -maxdepth 1 -name 'PaneKit.app' -print -quit || true)"
fi

if [[ ! -d "$APP_SRC" ]]; then
  echo "error: PaneKit.app not found after build" >&2
  exit 1
fi

# Quit ALL PaneKit copies (stable path + Debug/Release build dirs).
if pgrep -x PaneKit >/dev/null 2>&1; then
  echo "→ Quitting running PaneKit…"
  osascript -e 'tell application "PaneKit" to quit' >/dev/null 2>&1 || true
  sleep 0.5
  killall PaneKit >/dev/null 2>&1 || true
  sleep 0.4
fi

echo "→ Installing to $DEST"
rm -rf "$DEST"
cp -R "$APP_SRC" "$DEST"

# Prefer stable local/Apple identity. Hardened runtime is fine for local TCC.
echo "→ codesign --force --deep --sign \"$IDENTITY\""
if ! codesign --force --deep --options runtime --sign "$IDENTITY" "$DEST" 2>/tmp/panekit-codesign.err; then
  echo "warning: codesign with '$IDENTITY' failed; retrying without hardened runtime…" >&2
  cat /tmp/panekit-codesign.err >&2 || true
  if ! codesign --force --deep --sign "$IDENTITY" "$DEST"; then
    echo "error: could not sign with '$IDENTITY'. Click Allow on Keychain prompt, then re-run." >&2
    exit 1
  fi
fi

echo ""
echo "Kurulum tamam / Installed:"
echo "  $DEST"
codesign -dv --verbose=2 "$DEST" 2>&1 | head -25 || true
echo ""
echo "Designated requirement (TCC uses this — should stay stable across rebuilds):"
codesign -d -r- "$DEST" 2>&1 || true
echo ""
echo "Accessibility: Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik"
echo "  → Yalnızca şu yolu açın / Enable ONLY this path:"
echo "     $DEST"
echo "  Eski PaneKit satırlarını (−) ile silin; uygulamayı kapatıp yeniden açın."
echo "Açmak için: open \"$DEST\""

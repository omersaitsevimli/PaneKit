#!/usr/bin/env bash
# Ensure a stable local code-signing identity for PaneKit.
# Ad-hoc (`codesign -s -`) binds TCC to the binary CDHash → every rebuild
# looks like a new app and Accessibility must be re-granted. A self-signed
# certificate keeps the same leaf across rebuilds so permission sticks.
#
# Usage: ./scripts/ensure-local-signing-identity.sh
# Prints a codesign -s argument on stdout (prefer SHA-1 hash when unambiguous).
set -euo pipefail

IDENTITY_NAME="${PANEKIT_SIGN_IDENTITY:-PaneKit Local Signing}"
# Migration: keep using the pre-rename cert if PaneKit Local Signing is missing/untrusted.
FALLBACK_IDENTITY_NAME="FreeMagnet Local Signing"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/panekit-sign.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# Prefer Apple system LibreSSL — Homebrew OpenSSL 3/4 PKCS#12 often imports as NOT_TRUSTED.
OPENSSL="${PANEKIT_OPENSSL:-/usr/bin/openssl}"
if [[ ! -x "$OPENSSL" ]]; then
  OPENSSL="$(command -v openssl)"
fi

print_best_identity() {
  # Prefer a *valid* identity whose name matches; print SHA-1 hash for unambiguous -s.
  local wanted="$1"
  local line hash
  line="$(security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$wanted\"" | head -1 || true)"
  if [[ -n "$line" ]]; then
    hash="$(echo "$line" | awk '{print $2}')"
    if [[ "$hash" =~ ^[0-9A-Fa-f]{40}$ ]]; then
      printf '%s\n' "$hash"
      return 0
    fi
    printf '%s\n' "$wanted"
    return 0
  fi
  return 1
}

if print_best_identity "$IDENTITY_NAME"; then
  echo "→ Using existing identity: $IDENTITY_NAME" >&2
  exit 0
fi
if [[ -z "${PANEKIT_SIGN_IDENTITY:-}" ]] && print_best_identity "$FALLBACK_IDENTITY_NAME"; then
  echo "→ Using migration identity: $FALLBACK_IDENTITY_NAME (create “PaneKit Local Signing” later if desired)" >&2
  exit 0
fi

echo "→ Creating local code-signing certificate: $IDENTITY_NAME (via $OPENSSL)" >&2

cat >"$WORKDIR/codesign.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
EOF

"$OPENSSL" genrsa -out "$WORKDIR/key.pem" 2048 2>/dev/null
"$OPENSSL" req -new -key "$WORKDIR/key.pem" -out "$WORKDIR/req.csr" \
  -subj "/CN=${IDENTITY_NAME}/O=PaneKit/OU=Local/"
"$OPENSSL" x509 -req -days 3650 \
  -in "$WORKDIR/req.csr" \
  -signkey "$WORKDIR/key.pem" \
  -out "$WORKDIR/cert.pem" \
  -extfile "$WORKDIR/codesign.ext" 2>/dev/null

P12_PASS="panekit-local"
PK_ARGS=(-export -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" -out "$WORKDIR/PaneKit.p12" -name "$IDENTITY_NAME" -passout "pass:${P12_PASS}")
# Homebrew OpenSSL needs -legacy (or old PBEs) for Keychain to accept the P12.
if "$OPENSSL" pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
  PK_ARGS+=(-legacy)
fi
"$OPENSSL" pkcs12 "${PK_ARGS[@]}" 2>/dev/null

KC_ARGS=()
if [[ -f "$KEYCHAIN" ]]; then
  KC_ARGS=(-k "$KEYCHAIN")
fi

security import "$WORKDIR/PaneKit.p12" \
  "${KC_ARGS[@]}" \
  -P "$P12_PASS" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  >/dev/null

if [[ -f "$KEYCHAIN" ]]; then
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "" "$KEYCHAIN" >/dev/null 2>&1 || true
fi

# Optional: mark trusted for codeSign (may fail without UI / admin — valid identity often works anyway with LibreSSL).
security add-trusted-cert -d -r trustAsRoot -p codeSign "${KC_ARGS[@]}" "$WORKDIR/cert.pem" >/dev/null 2>&1 || true

if ! print_best_identity "$IDENTITY_NAME"; then
  echo "error: failed to install a *valid* codesigning identity named '$IDENTITY_NAME'" >&2
  echo "  Tip: use /usr/bin/openssl (LibreSSL), not Homebrew OpenSSL 4." >&2
  echo "  Or create a Code Signing cert in Keychain Access named '$IDENTITY_NAME'." >&2
  security find-identity -p codesigning 2>&1 | head -20 >&2 || true
  exit 1
fi

echo "→ Installed identity: $IDENTITY_NAME" >&2

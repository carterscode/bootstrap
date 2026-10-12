#!/bin/bash
# carterscode bootstrap — PUBLIC entry point (mirror to github.com/carterscode/bootstrap).
# Signed-helper path: reads a GitHub token from the iCloud-SYNCED Keychain via a
# code-signed helper, clones the private dotfiles repo, hands off to the installer.
#
# On a freshly-wiped Mac (signed into iCloud). Use <(...), NOT a pipe:
#   bash <(curl -fsSL https://raw.githubusercontent.com/carterscode/bootstrap/main/bootstrap.sh)
set -euo pipefail
umask 077

# ── Fill after publishing a signed icloud-secret release ──────────────
# The signed helper is its own project: github.com/carterscode/icloud-secret
HELPER_VERSION="v1.0.0"
RELEASE_URL="https://github.com/carterscode/icloud-secret/releases/download/${HELPER_VERSION}/icloud-secret-macos-universal.zip"
EXPECTED_SHA256="1f46695354d77419e2ce65d9bebe66354881e3fa21f3d619ee9836a721c08fc2"
EXPECTED_TEAM_ID="GA9R7U8CJG"
GH_USERNAME="carterscode"          # PAT owner; GitHub HTTPS wants a non-empty username
SECRET_NAME="github-dotfiles"
# ──────────────────────────────────────────────────────────────────────

DOTFILES_REPO="https://github.com/carterscode/dotfiles.git"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Documents/git/carterscode/dotfiles}"
APP_DIR="$HOME/.local/share/carters-bootstrap"
APP_PATH="$APP_DIR/iCloudSecret.app"
KEYCHAIN_CLI="$APP_PATH/Contents/MacOS/icloud-secret"

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only." >&2; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# 1. Xcode Command Line Tools (git). The one unavoidable GUI gate.
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  echo "==> Installing Xcode Command Line Tools — accept the dialog…"
  /usr/bin/xcode-select --install || true
  until /usr/bin/xcode-select -p >/dev/null 2>&1; do sleep 10; done
fi

# 2. Fetch + verify the signed keychain helper (once).
if [ ! -x "$KEYCHAIN_CLI" ]; then
  echo "==> Fetching signed keychain helper…"
  mkdir -p "$APP_DIR"
  curl -fsSL --retry 3 "$RELEASE_URL" -o "$WORK/h.zip"
  echo "$EXPECTED_SHA256  $WORK/h.zip" | shasum -a 256 -c -
  ditto -xk "$WORK/h.zip" "$WORK"
  codesign --verify --strict --verbose=2 "$WORK/iCloudSecret.app"
  got_team="$(codesign -dv --verbose=4 "$WORK/iCloudSecret.app" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  [ "$got_team" = "$EXPECTED_TEAM_ID" ] || { echo "unexpected signing team: '$got_team'" >&2; exit 1; }
  ditto "$WORK/iCloudSecret.app" "$APP_PATH"
  # Strip any quarantine so running it never triggers a Gatekeeper prompt
  # (curl-fetched files normally aren't quarantined; this makes it certain).
  xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
fi

# 3. Read the iCloud-synced credential. Sync is eventually-consistent, so retry.
echo "==> Reading GitHub token from iCloud Keychain (waiting for sync if needed)…"
ok=0
for _ in $(seq 1 60); do
  if "$KEYCHAIN_CLI" get "$SECRET_NAME" >/dev/null 2>"$WORK/kc.err"; then ok=1; break; fi
  sleep 10
done
if [ "$ok" != 1 ]; then
  echo "ERROR: token not available from iCloud Keychain. Last error:" >&2
  cat "$WORK/kc.err" >&2
  echo "  -25300 = not found/not synced yet; -34018 = signing/entitlement/profile problem." >&2
  exit 1
fi

# 4. Clone the private repo via GIT_ASKPASS — token never touches argv, URL, or config.
ASK="$WORK/askpass"
cat > "$ASK" <<ASKEOF
#!/bin/bash
case "\$1" in
  *Username*) printf '%s\n' "$GH_USERNAME" ;;
  *Password*) exec "$KEYCHAIN_CLI" get "$SECRET_NAME" ;;
  *) exit 1 ;;
esac
ASKEOF
chmod 700 "$ASK"

if [ ! -d "$DOTFILES_DIR/.git" ]; then
  echo "==> Cloning private dotfiles…"
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  GIT_ASKPASS="$ASK" GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

# 5. Hand off to the full installer (Homebrew + packages + symlinks).
[ -x "$DOTFILES_DIR/brew-install-script.sh" ] || { echo "installer missing in clone." >&2; exit 1; }
echo "==> Handoff -> brew-install-script.sh"
exec "$DOTFILES_DIR/brew-install-script.sh"

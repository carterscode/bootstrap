# carterscode bootstrap (public)

Zero-touch macOS rebuild: a freshly-wiped Mac runs one command, reads a GitHub
token from the **iCloud-synced Keychain** (via the signed `icloud-secret`
helper), clones the private `carterscode/dotfiles` repo, and runs its installer.

**Mirror this directory to the PUBLIC repo `github.com/carterscode/bootstrap`.**
It's staged here in the (private) dotfiles repo as the source of truth.

## The two pieces

- **`bootstrap.sh`** — the curl entry point (this repo).
- **`icloud-secret`** — the signed Keychain helper, its own project at
  **github.com/carterscode/icloud-secret**. `bootstrap.sh` downloads the
  notarized binary from that repo's Releases. All build/sign/notarize details
  (and why signing is required — `errSecMissingEntitlement -34018`) live there.

## One-time setup

1. Build + publish a signed `icloud-secret` release (see that repo's README).
   Note the release **version**, the zip's **SHA-256**, and your **Team ID**.
2. Fill `bootstrap.sh`: `HELPER_VERSION`, `EXPECTED_SHA256`, `EXPECTED_TEAM_ID`,
   `GH_USERNAME`.
3. Store the token once on an existing Mac — fine-grained PAT, read-only,
   `carterscode/dotfiles` only, Contents:read:
   ```sh
   printf '%s' "$TOKEN" | icloud-secret set github-dotfiles
   ```
4. Push `bootstrap.sh` to `github.com/carterscode/bootstrap`.

## The new-Mac command

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/carterscode/bootstrap/main/bootstrap.sh)
```

Accept the Xcode CLT dialog and a sudo password when a cask asks. No GitHub
login, no token entry. `bootstrap.sh` waits (up to ~10 min) for the Keychain
item to sync, then clones and hands off to `brew-install-script.sh`.

## Prove it before trusting it

Wipe a second Mac → sign into iCloud → run the command → it reads the token with
no prompt. iCloud Keychain sync is eventually-consistent (and a freshly
signed-in Mac may need a trusted device/passcode first), so this is
*unattended-after-sync*, not instantaneously guaranteed.

## No Apple Developer account?

The signed helper needs one. Without it, use the simpler fallback at the repo
root (`../bootstrap.sh`): `gh` device-login or an iCloud-Drive token — no
signing, but not Keychain-backed.

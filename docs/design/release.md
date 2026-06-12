# Release & distribution

## Channels

- **GitHub Releases** — `Photonz.dmg` (arm64). The website's download button points at
  `https://github.com/dzearing/photonz/releases/latest/download/Photonz.dmg`, which always
  resolves to the newest release — no site edit needed for links to stay correct.
- **Website** — `site/` deployed to GitHub Pages by `.github/workflows/site.yml` on every
  push to `main` that touches `site/`. The page shows the current version by fetching
  `site/version.json` (kept in lockstep by the release skill).

## Versioning

Single source of truth: the `VERSION` file (semver). `Scripts/build-app.sh` stamps it into
Info.plist; the release skill copies it into `site/version.json` and the git tag (`v<version>`).

## Pipelines

| Workflow | Trigger | Does |
| --- | --- | --- |
| `ci.yml` | push/PR to `main` | `swift build` + `swift test` on macOS arm64 runner |
| `release.yml` | tag `v*` | test → `build-app.sh --dmg` → create GitHub Release with the DMG |
| `site.yml` | push to `main` (site/ changes) + manual | deploy `site/` to GitHub Pages |

## Release procedure

Always via the `release` skill (`.claude/skills/release/SKILL.md`). Summary: verify clean
main + green tests → bump `VERSION`, `CHANGELOG.md`, `site/version.json` → commit, tag
`vX.Y.Z`, push → watch `release.yml` → verify the DMG asset and the live site.

## Signing & notarization

`release.yml` signs and notarizes automatically **when the Apple Developer secrets are
configured**, and falls back to ad-hoc signing when they are not (users then right-click →
Open on first launch; the website says so).

To enable Developer ID releases, add these repo secrets (Settings → Secrets → Actions):

| Secret | Value |
| --- | --- |
| `APPLE_SIGNING_IDENTITY` | `Developer ID Application: Name (TEAMID)` — gates everything: empty means ad-hoc |
| `APPLE_CERTIFICATE_P12` | base64 of the exported .p12 (`base64 -i cert.p12 \| pbcopy`) |
| `APPLE_CERTIFICATE_PASSWORD` | the .p12 password |
| `APPLE_ID` | Apple ID email used with notarytool |
| `APPLE_TEAM_ID` | 10-character team id |
| `APPLE_APP_PASSWORD` | app-specific password (appleid.apple.com → App-Specific Passwords) |

Flow: import cert into a throwaway keychain → `build-app.sh --dmg` with
`CODESIGN_IDENTITY` (hardened runtime + timestamp) → `notarytool submit --wait` on the
DMG → `stapler staple`. Locally, `CODESIGN_IDENTITY="Developer ID Application: …"
Scripts/build-app.sh` signs the same way if the identity is in your keychain.

## Future: Windows

amd64 Windows is explicitly out of scope until the Mac app is mature. The core-model/render
split keeps the door open but no code should branch on platform today.

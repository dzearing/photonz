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

## Signing status

Ad-hoc codesigned for now (no Developer ID). Users must right-click → Open on first launch;
the website says so. Developer ID signing + notarization is a Phase 7 task (requires an
Apple Developer account secret in the repo).

## Future: Windows

amd64 Windows is explicitly out of scope until the Mac app is mature. The core-model/render
split keeps the door open but no code should branch on platform today.

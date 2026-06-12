---
name: release
description: Cut a Photonz release — bumps VERSION/CHANGELOG/site version, tags, publishes the GitHub release with the DMG, and verifies the website download path. Use when asked to "release", "ship", "publish", or "cut a version".
---

# Release Photonz

Keeps VERSION, CHANGELOG.md, site/version.json, the git tag, and the GitHub release in lockstep. Never hand-roll a release.

## Inputs

Determine the new semver version first:
- If the user named a version, use it.
- Otherwise infer from changes since the last tag (`git log $(git describe --tags --abbrev=0)..HEAD --oneline`): breaking → major, features → minor, fixes only → patch. Pre-1.0, prefer minor bumps for features.

## Steps

1. **Preflight** — all must pass before touching anything:
   - `git status --porcelain` is empty and on `main`; `git pull` is up to date with origin.
   - `Scripts/test.sh` is green.
   - `Scripts/build-app.sh --dmg` succeeds locally (catches packaging breaks before CI).
2. **Stamp the version** (let `NEW` be the new version, `DATE` today's date):
   - `VERSION` ← `NEW`.
   - `CHANGELOG.md`: add a `## NEW — DATE` section at the top summarizing user-visible changes since the last tag. Write for users, not committers.
   - `site/version.json`: update `version` and `released`. (Do not touch the download URL anywhere — the site links to `releases/latest/download/Photonz.dmg`, which updates itself.)
3. **Commit & tag**:
   - `git add VERSION CHANGELOG.md site/version.json && git commit -m "release: vNEW"`
   - `git tag vNEW && git push origin main vNEW`
4. **Watch the pipelines** (`gh run watch` or poll `gh run list`):
   - `Release` workflow (tag-triggered): must end green with `Photonz.dmg` attached.
   - `Deploy site` workflow (main push): must end green so the site shows the new version.
5. **Verify end-to-end** — the release is not done until all three pass:
   - `gh release view vNEW` shows the DMG asset.
   - `curl -sIL https://github.com/dzearing/photonz/releases/latest/download/Photonz.dmg | grep -i '^HTTP'` ends in `200`.
   - `curl -s https://dzearing.github.io/photonz/version.json` reports `NEW`.
6. **Record it**: append a release entry to `docs/progress/log.md`; if a plan phase completed, update `docs/plan/`.

## Failure handling

- If the Release workflow fails after tagging: fix on `main`, delete the tag (`git tag -d vNEW && git push origin :refs/tags/vNEW`) and any draft release (`gh release delete vNEW`), then restart from step 1. Never leave a tag pointing at a broken build.
- If only the site deploy failed, re-run it: `gh workflow run site.yml`.

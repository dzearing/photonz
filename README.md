# Photonz ⌬

Lightning-fast photo & screenshot editing, built natively for the Mac.

**[Download for Apple silicon →](https://github.com/dzearing/photonz/releases/latest/download/Photonz.dmg)** · [Website](https://dzearing.github.io/photonz/)

Photonz is a macOS 26+ editor designed for the screenshot-to-share loop: crop, resize, skew, annotate with arrows/shapes/text, create magnified zoom callouts with leader lines, and work non-destructively with Photoshop-style layers (blur, fade, borders, rounded corners, shadows). Swift 6 + SwiftUI + Metal-accelerated Core Image; Liquid Glass UI throughout.

> Beta (0.2.x): every editing tool is wired up and usable, but it's still pre-1.0 while it gets real-world testing. See the [changelog](CHANGELOG.md) for what's in it and [the plan](docs/plan/overview.json) for how it was built.

## Building from source

Requires macOS 26+ on Apple silicon. Full Xcode is *not* required — Command Line Tools are enough.

```sh
swift build              # debug build
Scripts/test.sh          # run the test suite
Scripts/build-app.sh     # assemble dist/Photonz.app (add --dmg for a disk image)
open dist/Photonz.app
```

## Running the sites

Two separate things in this repo are called "the site". Neither starts on its
own, and both are plain static files, so nothing needs installing first.

**The marketing site** (`site/`), which is what ships to GitHub Pages:

```sh
python3 -m http.server 8000 --directory site
# then open http://localhost:8000/
```

Pushing to `main` with any change under `site/` deploys it automatically via
`.github/workflows/site.yml`. Don't hand-edit `site/version.json`; the release
skill keeps it in step with VERSION, CHANGELOG and the git tag.

**The design mock study** (`docs/design/mocks/`), a 64-page clickable prototype
of where the app is going. It needs its own tiny server because the pages load
the shared design system by absolute path (`/shared/photonz-ds.css`), so opening
the HTML files directly from disk gives you unstyled pages:

```sh
cd docs/design/mocks
node dev-server.mjs
# then open http://localhost:8791/
```

It serves on port 8791 and live-reloads every open page whenever a file
changes. To leave it running across a session, start it detached instead:

```sh
cd docs/design/mocks
nohup node dev-server.mjs >/tmp/photonz-mock-server.log 2>&1 &
```

Start there at `index.html`, which indexes every page. `creation-vision.html`
is the narrative walkthrough of the direction, and its written spec is
[docs/design/creation-vision.md](docs/design/creation-vision.md).

## Repository layout

| Path | What |
| --- | --- |
| `Sources/PhotonzCore` | Pure-Swift document model: layers, geometry, history. Fully unit-tested. |
| `Sources/PhotonzRender` | Core Image/Metal compositor + image store. Pixel-tested. |
| `Sources/Photonz` | SwiftUI app shell. |
| `docs/design` | Architecture & feature design docs. |
| `docs/design/mocks` | Clickable 64-page design study for the next chapter. Run it with `node dev-server.mjs` (see above). |
| `docs/plan` | Machine-readable build plan (overview + per-phase files). |
| `docs/progress` | Session-by-session progress journal. |
| `site/` | Marketing site (deployed to GitHub Pages). |
| `Scripts/` | Test wrapper, app/DMG packaging, icon generator. |

## Contributing / development rules

See [CLAUDE.md](CLAUDE.md): test-driven development for core modules, strict module boundaries, and the plan-maintenance protocol. CI must be green (`.github/workflows/ci.yml`); releases go through the release skill so version metadata stays consistent.

## License

MIT — see [LICENSE](LICENSE).

# Photonz ⌬

Lightning-fast photo & screenshot editing, built natively for the Mac.

**[Download for Apple silicon →](https://github.com/dzearing/photonz/releases/latest/download/Photonz.dmg)** · [Website](https://dzearing.github.io/photonz/)

Photonz is a macOS 26+ editor designed for the screenshot-to-share loop: crop, resize, skew, annotate with arrows/shapes/text, create magnified zoom callouts with leader lines, and work non-destructively with Photoshop-style layers (blur, fade, borders, rounded corners, shadows). Swift 6 + SwiftUI + Metal-accelerated Core Image; Liquid Glass UI throughout.

> 1.0: every editing tool is shipping. See the [changelog](CHANGELOG.md) for what's in it and [the plan](docs/plan/overview.json) for how it was built.

## Building from source

Requires macOS 26+ on Apple silicon. Full Xcode is *not* required — Command Line Tools are enough.

```sh
swift build              # debug build
Scripts/test.sh          # run the test suite
Scripts/build-app.sh     # assemble dist/Photonz.app (add --dmg for a disk image)
open dist/Photonz.app
```

## Repository layout

| Path | What |
| --- | --- |
| `Sources/PhotonzCore` | Pure-Swift document model: layers, geometry, history. Fully unit-tested. |
| `Sources/PhotonzRender` | Core Image/Metal compositor + image store. Pixel-tested. |
| `Sources/Photonz` | SwiftUI app shell. |
| `docs/design` | Architecture & feature design docs. |
| `docs/plan` | Machine-readable build plan (overview + per-phase files). |
| `docs/progress` | Session-by-session progress journal. |
| `site/` | Marketing site (deployed to GitHub Pages). |
| `Scripts/` | Test wrapper, app/DMG packaging, icon generator. |

## Contributing / development rules

See [CLAUDE.md](CLAUDE.md): test-driven development for core modules, strict module boundaries, and the plan-maintenance protocol. CI must be green (`.github/workflows/ci.yml`); releases go through the release skill so version metadata stays consistent.

## License

MIT — see [LICENSE](LICENSE).

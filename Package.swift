// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Photonz",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        // The one third-party dependency in the whole project: libwebp's
        // encoder, vendored as source so a clean checkout builds with nothing
        // installed on the machine. macOS can READ a WebP through ImageIO and
        // cannot write one, so only the encoder is here. See
        // Vendor/libwebp/VERSION for the pinned release and
        // Scripts/vendor-libwebp.sh for how it is updated.
        .target(
            name: "CWebP",
            path: "Vendor/libwebp",
            exclude: ["COPYING", "PATENTS", "AUTHORS", "VERSION"],
            publicHeadersPath: "src/webp",
            cSettings: [
                // libwebp includes its own headers from the library root
                // ("src/dsp/dsp.h"), the way its own build system does.
                .headerSearchPath("."),
                // Encoding a 12 megapixel picture on one core is not a time
                // worth waiting for; libwebp splits the work when this is on.
                .define("WEBP_USE_THREAD"),
            ]
        ),
        // Pure-Swift document model: layers, geometry, commands, undo.
        // No UI imports allowed here — keep it fully unit-testable.
        .target(
            name: "PhotonzCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Core Image / Metal compositing of a PhotonzCore document.
        .target(
            name: "PhotonzRender",
            dependencies: ["PhotonzCore", "CWebP"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // AVFoundation / ImageIO media IO for recordings: poster frames, MP4
        // re-encode, animated GIF/HEIC, and committing a save into the stored
        // asset. No UI imports — it lives outside the app target so the
        // "a saved recording IS the trimmed file" promise is unit-testable.
        .target(
            name: "PhotonzMedia",
            dependencies: ["PhotonzCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // SwiftUI app shell. Assembled into Photonz.app by Scripts/build-app.sh.
        .executableTarget(
            name: "Photonz",
            dependencies: ["PhotonzCore", "PhotonzRender", "PhotonzMedia"],
            // Docs that live next to the code they describe, not resources.
            exclude: [
                "Releases/README.md",
                "Releases/Legacy/README.md",
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Dev tool: composites a showcase document through the real engine and
        // writes the marketing-site hero image. Run with `swift run SiteAssets`.
        // Not part of the shipping app; safe to ignore in CI/release.
        .executableTarget(
            name: "SiteAssets",
            dependencies: ["PhotonzCore", "PhotonzRender"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PhotonzCoreTests",
            dependencies: ["PhotonzCore"]
        ),
        .testTarget(
            name: "PhotonzRenderTests",
            dependencies: ["PhotonzRender"],
            // A real 2x screenshot of a settings pane whose CSS geometry is
            // known, so element detection is pinned against measured truth
            // rather than against a synthetic drawing of what we expect.
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "PhotonzMediaTests",
            // ...and the renderer, because the one claim a video export has to
            // make is that the frame on disk is the frame the canvas draws, and
            // the only way to check it is to draw one and then write it.
            dependencies: ["PhotonzMedia", "PhotonzRender"]
        ),
    ]
)

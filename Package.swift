// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Photonz",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        // Pure-Swift document model: layers, geometry, commands, undo.
        // No UI imports allowed here — keep it fully unit-testable.
        .target(
            name: "PhotonzCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Core Image / Metal compositing of a PhotonzCore document.
        .target(
            name: "PhotonzRender",
            dependencies: ["PhotonzCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // SwiftUI app shell. Assembled into Photonz.app by Scripts/build-app.sh.
        .executableTarget(
            name: "Photonz",
            dependencies: ["PhotonzCore", "PhotonzRender"],
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
            dependencies: ["PhotonzRender"]
        ),
    ]
)

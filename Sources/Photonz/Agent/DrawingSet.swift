import Foundation
import PhotonzCore

/// The built-in drawings Ask and add_drawing draw a thing from
/// (`DrawingLibrary`, `Resources/Drawings`), read once on first use. Nil when
/// the file is missing, which leaves an agent drawing with its own SVG.
enum DrawingSet {
    static let shared: DrawingLibrary? = {
        guard let url = location, let data = try? Data(contentsOf: url) else { return nil }
        return DrawingLibrary.decode(data)
    }()

    /// In the app bundle; for a binary run from the build folder, the repo's
    /// own copy found by walking up from it.
    private static var location: URL? {
        if let bundled = Bundle.main.url(forResource: "drawings", withExtension: "json", subdirectory: "Drawings") {
            return bundled
        }
        var folder = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<8 {
            guard let here = folder else { return nil }
            let candidate = here.appendingPathComponent("Resources/Drawings/drawings.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            folder = here.deletingLastPathComponent()
        }
        return nil
    }
}

import Foundation

/// Whether an SVG says every place in whole units, read back out of the file.
///
/// The icon epic promises whole-unit coordinates in what leaves the app, by
/// Export or by Copy. A walk that copies an icon holds the clipboard to it
/// (`readClipboard` with `svg`), so the check reads only the attributes that
/// are places on the grid: positions, sizes, radii, the view box, path data
/// and moves. A stroke's weight or a fade is not a place, and is left alone.
public enum SVGWholeUnits {

    /// The attributes whose numbers are places on the grid.
    static let placeAttributes: Set<String> = [
        "x", "y", "width", "height", "cx", "cy", "r", "rx", "ry",
        "x1", "y1", "x2", "y2", "viewBox", "points", "d", "transform"
    ]

    /// Every number off the grid, as `attribute=value`, in the order the file
    /// says them. Empty when the file is whole units throughout.
    public static func fractionalCoordinates(in svg: String) -> [String] {
        var found: [String] = []
        let attribute = /([A-Za-z][A-Za-z0-9:-]*)="([^"]*)"/
        let number = /-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/
        for match in svg.matches(of: attribute) {
            let name = String(match.output.1)
            guard placeAttributes.contains(name) else { continue }
            for value in match.output.2.matches(of: number) {
                guard let parsed = Double(value.output), parsed.rounded() != parsed else { continue }
                found.append("\(name)=\(value.output)")
            }
        }
        return found
    }
}

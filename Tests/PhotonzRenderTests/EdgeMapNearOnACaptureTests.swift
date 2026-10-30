import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// The edges near a line, found without reading the whole row, are exactly the
/// whole-row query's edges in that band on a real screenshot too: dense text,
/// borders, toggles. `EdgeMapNearTests` holds the same on synthetic maps.
@Suite("Edges near a line on a real capture")
struct EdgeMapNearOnACaptureTests {

    private static let edges: EdgeMap = {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = ImageCodec.decode(data) else { return .empty }
        return EdgeMapAnalyzer.analyzeFully(image).edges
    }()

    @Test func aGuidesQueriesMatchTheWholeRowOnASettingsPane() {
        let map = Self.edges
        #expect(!map.isEmpty)
        for along in stride(from: 4.0, through: 956, by: 8) {
            let window = (along - 4)...(along + 4)
            let rows = map.verticalEdges(inYRange: window)
            for x in stride(from: 0.0, through: 1440, by: 6) {
                let band = (x - 12)...(x + 12)
                #expect(map.verticalEdges(inYRange: window, near: band)
                        == rows.filter { band.contains($0.position) }, "y \(along), x \(x)")
            }
        }
        for along in stride(from: 4.0, through: 1436, by: 8) {
            let window = (along - 4)...(along + 4)
            let columns = map.horizontalEdges(inXRange: window)
            for y in stride(from: 0.0, through: 960, by: 6) {
                let band = (y - 12)...(y + 12)
                #expect(map.horizontalEdges(inXRange: window, near: band)
                        == columns.filter { band.contains($0.position) }, "x \(along), y \(y)")
            }
        }
    }
}

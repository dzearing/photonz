import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// `find_elements` on a real screenshot: an agent asked to "annotate the UX
/// with measurements around the major UI elements" starts from this list, so
/// the controls a redliner measures have to be in it, each once.
@Suite("Agent find_elements on a real settings screenshot")
struct AgentElementScanFixtureTests {

    private func image(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }

    /// The controls on `settings-pane-2x.png`, in its own pixels, exactly as
    /// the Measure tool's Size click reads each one in the app (measured on
    /// 2026-10-19): the two cards, the four switches, the two fields and the
    /// two buttons. find_elements hands back what that click would measure.
    static let controls: [(String, CGRect)] = [
        ("first card", CGRect(x: 64, y: 148, width: 1312, height: 264)),
        ("second card", CGRect(x: 64, y: 452, width: 1312, height: 264)),
        ("Launch at login switch", CGRect(x: 1260, y: 167, width: 84, height: 48)),
        ("Show in menu bar switch", CGRect(x: 1260, y: 255, width: 84, height: 48)),
        ("Play sound switch", CGRect(x: 1260, y: 344, width: 84, height: 48)),
        ("Copy to clipboard switch", CGRect(x: 1260, y: 648, width: 84, height: 48)),
        ("Save captures field", CGRect(x: 904, y: 469, width: 440, height: 52)),
        ("File name field", CGRect(x: 904, y: 557, width: 440, height: 52)),
        ("Reset button", CGRect(x: 64, y: 756, width: 145, height: 60)),
        ("Save Changes button", CGRect(x: 233, y: 756, width: 248, height: 60)),
    ]

    static func near(_ a: CGRect, _ b: CGRect, slack: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) <= slack && abs(a.minY - b.minY) <= slack
            && abs(a.maxX - b.maxX) <= slack && abs(a.maxY - b.maxY) <= slack
    }

    @Test("Every control a redliner measures is listed once, within the default limit")
    func listsTheControls() throws {
        let picture = try #require(image("settings-pane-2x"))
        let read = EdgeMapAnalyzer.analyzeFully(picture)
        let document = PhotonzDocument(canvasSize: CGSize(width: picture.width, height: picture.height), layers: [])
        let found = AgentElementScan.elements(in: document, edges: read.edges, luma: read.luma)
        #expect(found.count <= AgentElementScan.defaultLimit)
        for (name, box) in Self.controls {
            let hits = found.filter { Self.near($0, box) }
            #expect(hits.count == 1, "\(name) at \(box) is listed \(hits.count) times")
        }
    }
}

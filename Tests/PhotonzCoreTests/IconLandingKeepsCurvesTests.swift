import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Landing an icon on whole units moves a curve's ends, and its handles go
/// with them, stretched, so the curve keeps the shape it was drawn with
/// (2026-11-08). Pinned to their ends unstretched, a balloon's string whose end
/// rounded half a unit down came out longer and straighter than drawn, and the
/// judges read the icon as popping in three looks of eighteen against eleven
/// with the curve kept. Nothing here knows what is drawn.
@Suite("Landing on units keeps a curve's shape")
struct IconLandingKeepsCurvesTests {

    static let drawing = """
        <svg viewBox="0 0 24 24"><path id="body" d="M4 4 L20 4 L20 14 L4 14 Z" fill="none" stroke="#000000" stroke-width="2"/>\
        <path id="tail" d="M12 14 C12 16 11 17 12 18.5" fill="none" stroke="#000000" stroke-width="2"/></svg>
        """

    /// The tail's two anchors as landed, in the picture's points.
    static func tail(_ svg: String) throws -> (from: PathAnchor, to: PathAnchor) {
        let art = try SVGArtwork.parse(svg).get()
        let frame = art.iconFrame(named: "Icon", side: 512, origin: .zero)
        let layer = try #require(frame.children.first { $0.name.lowercased() == "tail" })
        let anchors = try #require(layer.path?.anchors)
        #expect(anchors.count == 2)
        return (anchors[0], anchors[1])
    }

    @Test("A curve whose end rounds keeps each handle the same share of the way along it")
    func handlesStretch() throws {
        let (from, to) = try Self.tail(Self.drawing)
        let down = to.point.y - from.point.y
        // Drawn 4.5 down, the curve's first handle went 2 of it and its last
        // came back 1.5: shares of 0.444 and 0.333, whatever it lands at.
        #expect(abs(down / IconAskUnit.unit - 4.5) > 0.4, "the end did not round, so this proves nothing: \(down)")
        let out = try #require(from.handleOut), back = try #require(to.handleIn)
        #expect(abs(out.y / down - 2 / 4.5) < 0.01, "\(out.y / down)")
        #expect(abs(back.y / down + 1.5 / 4.5) < 0.01, "\(back.y / down)")
        // Straight down, there is nothing across to stretch: the sideways
        // pull stays as drawn, brought to the picture's size.
        #expect(abs(back.x / IconAskUnit.unit + 1) < 0.15, "\(back.x / IconAskUnit.unit)")
    }

    @Test("A curve whose ends land where they were drawn keeps its handles exactly")
    func wholeCurveUntouched() throws {
        let whole = Self.drawing.replacingOccurrences(of: "18.5", with: "18")
        let (from, to) = try Self.tail(whole)
        let down = to.point.y - from.point.y
        let out = try #require(from.handleOut)
        #expect(abs(out.y / down - 2 / 4) < 1e-6, "\(out.y / down)")
    }
}

private enum IconAskUnit {
    static let unit: CGFloat = 512.0 / 24
}

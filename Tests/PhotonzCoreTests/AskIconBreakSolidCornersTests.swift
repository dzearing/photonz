import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A solid part of a torn line icon has the round corners its lines have.
///
/// The model's balloon of 2026-11-09 drew its knot as a filled wedge with no
/// line: landed on whole units it came out one unit tall and four across, its
/// two bottom corners poking out like spikes under the round ends of every
/// line around it, and nine looks in three named the knot's "stray little
/// spikes". Given the line's round edge, pulled in so it covers what it
/// covered, the same picture read 85 in five judgings of nine where the spiky
/// one read 69 to 84. It reads only what a part is made of (a flat fill with
/// straight sides, in a drawing of round-joined lines), never what it is.
@Suite("A torn icon's solid parts have its lines' round corners")
struct AskIconBreakSolidCornersTests {

    static let balloon = AskIconBreakUnitsTests.drawing("hangs below the live area")

    static func tag(_ id: String, in svg: String) -> String? {
        guard let range = svg.range(of: #"<[a-z]+[^>]*id="\#(id)"[^>]*>"#, options: .regularExpression) else { return nil }
        return String(svg[range])
    }

    @Test func aStraightSidedSolidPartTakesTheLinesRoundEdge() throws {
        let torn = try #require(AskIconBreak.applied(to: Self.balloon))
        let knot = try #require(Self.tag("knot", in: torn))
        #expect(knot.contains(##"stroke="#1D1D1F""##))
        #expect(knot.contains(#"stroke-linejoin="round""#))
        #expect(knot.contains(##"fill="#1D1D1F""##))
        #expect(!knot.contains(#"stroke="none""#))
    }

    @Test func itCoversAboutWhatItCoveredOnTheGrid() throws {
        // Drawn 4 across and 1.5 tall; pulled in by half a line each side, its
        // round edge reaches about as far as the sharp wedge did.
        let landed = try AskIconBreakUnitsTests.landed(Self.balloon)
        let knot = try #require(landed.frame.children.first { $0.name.lowercased().contains("knot") })
        let unit = 512.0 / 24
        let line = try #require(knot.path?.strokeWidth) / unit
        let across = knot.frame.width / unit + line, tall = knot.frame.height / unit + line
        #expect(line > 0)
        #expect((3...5).contains(across), "the knot reaches \(across) units across")
        #expect((1...2.5).contains(tall), "the knot reaches \(tall) units tall")
    }

    @Test func aRoundSolidPartIsLeftAsItIs() throws {
        let torn = try #require(AskIconBreak.applied(to: AskIconBreakUnitsTests.drawing("a circle with a part below it")))
        let drop = try #require(Self.tag("droplet", in: torn))
        #expect(drop.contains(#"stroke="none""#))
    }

    @Test func aDrawingWithSquareJoinsKeepsItsSharpSolids() throws {
        let square = Self.balloon.replacingOccurrences(of: #" stroke-linejoin="round""#, with: "")
        let torn = try #require(AskIconBreak.applied(to: square))
        let knot = try #require(Self.tag("knot", in: torn))
        #expect(knot.contains(#"stroke="none""#))
    }
}

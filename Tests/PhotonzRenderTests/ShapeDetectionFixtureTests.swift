import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Size mode on the kind of screen it used to fail on (the user, 2026-10-11:
/// "i hover over the avatar and it won't size it. or the stacked set of
/// avatars. it does good on text but not components so much").
///
/// The fixture is `Fixtures/people-panel-2x.png`, drawn by
/// `Scripts/make-shapes-fixture.swift` at 2x with known geometry, so every
/// expectation is the number a spec would quote, in logical points:
///
/// | specimen | logical size | read before this reader |
/// | --- | --- | --- |
/// | photo avatar | 32 x 32 | 32 x 21, a piece of the photo |
/// | pale photo avatar | 40 x 40 | 22 x 47 |
/// | initials avatar | 32 x 32 | right |
/// | presence dot | 10 x 10 | |
/// | stacked avatar | 24 x 24 | 23 x 24 |
/// | the stack, one `]` out | 104 x 24 | |
/// | "+3" pill in the stack | 40 x 24 | the whole card |
/// | icon tile | 40 x 40 | right |
/// | "New" pill | 40 x 20 | right |
/// | count badge | 18 x 18 | right |
/// | photo in a card | 152 x 88 | right |
@Suite("Shape detection on a real capture")
struct ShapeDetectionFixtureTests {

    private static let analysis: EdgeMapAnalyzer.Analysis = {
        guard let url = Bundle.module.url(forResource: "Fixtures/people-panel-2x", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = ImageCodec.decode(data) else { return .empty }
        return EdgeMapAnalyzer.analyzeFully(image)
    }()

    /// What the two calipers would say, in logical points.
    private static func reading(_ rect: CGRect?) -> String? {
        guard let rect else { return nil }
        func label(_ span: CGFloat, _ mode: MeasureMode) -> String {
            MeasureContent(start: .zero,
                           end: CGPoint(x: mode == .horizontal ? span : 0, y: mode == .vertical ? span : 0),
                           mode: mode, unit: .points).label(pixelScale: 2)
        }
        return "\(label(rect.width, .horizontal)) by \(label(rect.height, .vertical))"
    }

    /// The Size mode pick at a point given in logical points, as the app asks
    /// for it on a 2x capture.
    private func ladder(_ x: Double, _ y: Double) -> [CGRect] {
        ElementBounds.candidates(at: CGPoint(x: 2 * x, y: 2 * y), in: Self.analysis.edges,
                                 luma: Self.analysis.luma, minElement: 20, textGap: 16,
                                 readsShapes: true)
    }

    private func reads(_ x: Double, _ y: Double, level: Int = 0) -> String? {
        let l = ladder(x, y)
        return level < l.count ? Self.reading(l[level]) : nil
    }

    /// Edges in image px, to within the 2 px a 2x capture is allowed.
    private func expectEdges(_ rect: CGRect?, _ logical: CGRect,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        let expected = CGRect(x: 2 * logical.minX, y: 2 * logical.minY,
                              width: 2 * logical.width, height: 2 * logical.height)
        guard let rect else {
            Issue.record("expected \(expected), got nothing", sourceLocation: sourceLocation)
            return
        }
        let ok = abs(rect.minX - expected.minX) <= 2 && abs(rect.minY - expected.minY) <= 2
            && abs(rect.maxX - expected.maxX) <= 2 && abs(rect.maxY - expected.maxY) <= 2
        if !ok { Issue.record("expected \(expected), got \(rect)", sourceLocation: sourceLocation) }
    }

    @Test func theCaptureIsTheOneTheseNumbersAreFor() {
        #expect(Self.analysis.luma.width == 960)
        #expect(Self.analysis.luma.height == 720)
    }

    // MARK: Hover

    @Test func aPhotoAvatarReadsItsSizeFromAnywhereOnIt() {
        for (x, y) in [(40.0, 40.0), (39.0, 35.0), (30.0, 45.0)] {
            #expect(reads(x, y) == "32 px by 32 px")
            expectEdges(ladder(x, y).first, CGRect(x: 24, y: 24, width: 32, height: 32))
        }
    }

    @Test func aPalePhotoAvatarReads() {
        #expect(reads(44, 136) == "40 px by 40 px")
        expectEdges(ladder(44, 136).first, CGRect(x: 24, y: 116, width: 40, height: 40))
    }

    @Test func anInitialsAvatarReadsFromItsFillAndFromItsLetters() {
        #expect(reads(30, 88) == "32 px by 32 px")
        #expect(reads(35, 88) == "32 px by 32 px")
        #expect(reads(40, 88) == "32 px by 32 px")
    }

    @Test func aPresenceDotReadsOnItsOwn() {
        #expect(reads(51, 51) == "10 px by 10 px")
    }

    @Test func aStackedAvatarReadsAsOneAvatarAndRightBracketReadsTheStack() {
        // The first three are cut by the ring of the one after; a spec quotes
        // the avatar, so each reads whole.
        for x in [36.0, 52.0, 68.0, 84.0] {
            #expect(reads(x, 188) == "24 px by 24 px", "avatar at \(x)")
            #expect(reads(x, 188, level: 1) == "104 px by 24 px", "stack from \(x)")
        }
        expectEdges(ladder(52, 188).first, CGRect(x: 48, y: 176, width: 24, height: 24))
        expectEdges(ladder(52, 188).dropFirst().first, CGRect(x: 32, y: 176, width: 104, height: 24))
    }

    @Test func theCountPillAtTheEndOfTheStackReadsItself() {
        #expect(reads(125, 188) == "40 px by 24 px")
        #expect(reads(116, 188) == "40 px by 24 px", "from over its +3")
        #expect(reads(125, 188, level: 1) == "104 px by 24 px")
    }

    @Test func iconTilesReadTheTileFromTheTileOrItsGlyph() {
        #expect(reads(28, 244) == "40 px by 40 px")
        #expect(reads(44, 244) == "40 px by 40 px", "from the white glyph")
        #expect(reads(150, 244) == "40 px by 40 px")
    }

    @Test func badgesRead() {
        #expect(reads(28, 298) == "40 px by 20 px")
        #expect(reads(79, 298) == "18 px by 18 px")
    }

    @Test func aPhotoInACardReadsThePhoto() {
        #expect(reads(364, 100) == "152 px by 88 px")
    }

    // MARK: Nothing that read right before moves

    @Test func textAndTheButtonReadAsTheyDidBefore() {
        // The name beside an avatar is a line of text.
        #expect(reads(100, 33)?.hasSuffix("by 12 px") == true || reads(100, 33)?.hasSuffix("by 13 px") == true)
        // The bordered button reads to the outer edge of its border: the pair
        // reader's 78 x 26 is the inside of it, and when two readings of one
        // thing tie the outer one wins (2026-10-13).
        #expect(reads(300, 234) == reads(320, 234))
        #expect(reads(300, 234) == "80 px by 28 px")
        expectEdges(ladder(300, 234).first, CGRect(x: 280, y: 220, width: 80, height: 28))
    }

    // MARK: A box

    private func snap(_ logical: CGRect) -> CGRect? {
        // As the app asks: the object reader and the group reader together.
        ObjectBounds.snap(CGRect(x: 2 * logical.minX, y: 2 * logical.minY,
                                 width: 2 * logical.width, height: 2 * logical.height),
                          field: Self.analysis.luma, slack: 8, link: 8, minElement: 8)
    }

    @Test func aRoughBoxAroundTheStackSnapsToTheStack() {
        expectEdges(snap(CGRect(x: 24, y: 168, width: 124, height: 42)),
                    CGRect(x: 32, y: 176, width: 104, height: 24))
    }

    @Test func aRoughBoxAroundOneStackedAvatarSnapsToThatAvatar() {
        expectEdges(snap(CGRect(x: 46, y: 170, width: 30, height: 36)),
                    CGRect(x: 48, y: 176, width: 24, height: 24))
    }

    @Test func aRoughBoxAroundAnAvatarSnapsToTheAvatar() {
        expectEdges(snap(CGRect(x: 18, y: 18, width: 44, height: 44)),
                    CGRect(x: 24, y: 24, width: 32, height: 32))
    }

    @Test func aBoxDrawnALittleTightStillReachesTheIconsEdge() {
        expectEdges(snap(CGRect(x: 26, y: 226, width: 36, height: 36)),
                    CGRect(x: 24, y: 224, width: 40, height: 40))
    }

    @Test func aBoxAroundEmptyCardKeepsNothing() {
        #expect(snap(CGRect(x: 160, y: 270, width: 80, height: 60)) == nil)
    }
}

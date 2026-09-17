import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// The WEIGHT a page comes back in, measured on a real capture of this app's
/// own Effects panel.
///
/// `Fixtures/effects-panel-2x.png` is a 2x crop of `app-window-2x.png`, and it
/// holds the case two audits named: "Corner Radius", "Border 1" and "Border 2"
/// are section labels of one style, and read one at a time they come back
/// Semibold, Medium and Medium. The rows under them — "Style", "Color",
/// "Position", "Width", "Offset" — are one style too, and they come back four
/// Regular, three Medium and two Semibold.
///
/// Both of those are wobble, and the picture says so: the three section labels
/// are white and the rows under them are grey, so a person can see at a glance
/// which labels are meant to match. That is also what the reader goes on
/// (`TextReading.WeightBallot`), which is why the fix settles each group
/// without flattening one into the other.
///
/// Serialized, like the suite next door and for the same reason: every test
/// here waits on ONE lazily read capture.
@Suite("The weight a page of labels comes back in, on a real capture", .serialized)
struct ReadPageWeightFixtureTests {

    private static let capture: CGImage? = {
        guard let url = Bundle.module.url(forResource: "Fixtures/effects-panel-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }()

    private static let runImages: [CGImage] = {
        guard let capture else { return [] }
        return LayerSeparator.separateText(capture,
                                           luma: EdgeMapAnalyzer.analyzeFully(capture).luma)?
            .runs.compactMap { $0.image } ?? []
    }()

    /// Every run, read the way the app reads them when somebody presses Read
    /// the Words.
    private static let reads: [TextReader.Read] = TextReader.readPage(
        runImages, captureScale: 2, spreadingOverTheCores: true)

    private static let readings: [TextReading.Reading] = reads.compactMap(\.outcome.reading)

    private func weight(of words: String) throws -> TextWeight {
        try #require(Self.readings.first { $0.string == words },
                     "\(words) did not come back at all").face.weight
    }

    private func weights(of words: [String]) throws -> [TextWeight] {
        try words.map { try weight(of: $0) }
    }

    // MARK: - One kind of label, one weight

    @Test func theSectionLabelsOfOnePanelComeBackAtOneWeight() throws {
        // The bug this exists for. Read one at a time these are Semibold,
        // Medium and Medium, and they are the same on screen.
        let found = try weights(of: ["Corner Radius", "Border 1", "Border 2"])
        #expect(Set(found).count == 1)
    }

    @Test func theRowsUnderThemComeBackAtOneWeightToo() throws {
        let found = try weights(of: ["Style", "Color", "Position", "Width", "Offset"])
        #expect(Set(found).count == 1)
    }

    @Test func aSectionLabelIsNotFlattenedIntoTheRowsUnderIt() throws {
        // What a page-wide vote would have broken, and the reason the vote is
        // per kind of label rather than per page. The section labels are white
        // and their rows are grey: a person can see they are not the same kind
        // of label, and so can the reader.
        let sections = try weights(of: ["Corner Radius", "Border 1", "Border 2"])
        let rows = try weights(of: ["Style", "Color", "Position", "Width", "Offset"])
        let order = TextWeight.allCases
        let heaviestRow = try #require(rows.compactMap { order.firstIndex(of: $0) }.max())
        let lightestSection = try #require(sections.compactMap {
            order.firstIndex(of: $0)
        }.min())
        #expect(lightestSection > heaviestRow)
    }

    @Test func theValuesBesideTheRowsAgreeWithTheRows() throws {
        // "4 px" and "16 px" sit on the Width and Offset rows in the same grey
        // at the same size, and read alone they come back Semibold while the
        // labels beside them come back Regular. Nothing in the picture makes
        // them a different kind of label, so nothing in the reading should.
        let found = try weights(of: ["Style", "4 px", "16 px"])
        #expect(Set(found).count == 1)
    }

    // MARK: - What settling the weight must not cost

    @Test func settlingTheWeightNeverCostsAReading() throws {
        // A weight a shade off is a smaller harm than a label that does not
        // come back at all, so the weight the page settled is never the reason
        // a run stays a picture. Held to the family alone, exactly as many
        // labels come back.
        let held = Self.runImages.map {
            TextReader.read($0, captureScale: 2, preferring: "SF Pro")
        }
        #expect(Self.readings.count == held.compactMap(\.outcome.reading).count)
        #expect(Self.readings.count >= 12)
    }

    @Test func thePageStillComesBackInOneFamily() throws {
        #expect(Set(Self.readings.map(\.face.fontName)) == ["SF Pro"])
    }

    @Test func readingItAcrossTheCoresAnswersExactlyAsOneAtATime() throws {
        // Settling the weight compares the runs with each other, so it is the
        // one part of this that could depend on the order they finished in.
        let serial = TextReader.readPage(Self.runImages, captureScale: 2)
        #expect(serial.count == Self.reads.count)
        for index in serial.indices {
            #expect(serial[index].outcome.reading?.face
                == Self.reads[index].outcome.reading?.face, "run \(index)")
            #expect(serial[index].outcome.reading?.fontSize
                == Self.reads[index].outcome.reading?.fontSize, "run \(index)")
        }
    }

    @Test func aPageReadTwiceSettlesTheSameWayTwice() throws {
        let again = TextReader.readPage(Self.runImages, captureScale: 2,
                                        spreadingOverTheCores: true)
        #expect(again.map(\.outcome.reading?.face) == Self.reads.map(\.outcome.reading?.face))
    }
}

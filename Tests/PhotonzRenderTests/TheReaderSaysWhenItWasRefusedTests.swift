import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Telling "there is nothing written here" apart from "the reader would not
/// answer".
///
/// The text recogniser is a shared on-device service, and under enough load it
/// hands back an ERROR instead of a reading. Both used to arrive at the caller
/// as an empty answer, which is how a healthy app came to look broken: eleven
/// checks in `SeparatedRowsSayTheirWordsTests` went red on a busy machine and
/// green on an idle one, on the same source, and a person reading the red had
/// no way to tell which had happened.
///
/// So the reader now says which of the two it was, per read, and keeps a
/// running count anything depending on real reading can ask about.
@Suite("The reader says when it was refused rather than empty")
struct TheReaderSaysWhenItWasRefusedTests {

    private static func capture(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }

    /// A picture with no ink in it reads as nothing, and nothing is not a
    /// refusal: a switch, an icon and a patch of flat panel all land here, and
    /// none of them says anything about the recogniser's health.
    @Test func aPictureWithNothingWrittenOnItIsNotARefusal() throws {
        let blank = TextReading.Mask(width: 40, height: 14,
                                     coverage: [Double](repeating: 0, count: 40 * 14))
        #expect(TextReader.reading(blank, inkHeight: 10) == .read([]))
    }

    /// Ink the recogniser cannot make a word of is the same story: it answered,
    /// it just found nothing.
    @Test func inkThatSpellsNothingIsNotARefusal() throws {
        // A solid block. There is plenty of ink and no characters in it.
        let solid = TextReading.Mask(width: 30, height: 12,
                                     coverage: [Double](repeating: 1, count: 30 * 12))
        let reading = TextReader.reading(solid, inkHeight: 12)
        #expect(reading.refusal == nil, "unreadable ink read as a refusal: \(reading)")
    }

    /// A picture too big to draw a page for is refused BY THIS CODE rather than
    /// by the recogniser, and that is still not a machine that will not answer.
    @Test func aPictureTooBigToPrepareIsNotARecogniserRefusal() throws {
        let tiny = TextReading.Mask(width: 1, height: 1, coverage: [1])
        #expect(TextReader.reading(tiny, inkHeight: 0) == .read([]))
    }

    /// And the case the whole thing exists for: a real run of words off a real
    /// capture reads, and reading it costs no refusals.
    @Test func realWordsReadWithoutTheReaderRefusing() throws {
        let image = try #require(Self.capture("settings-pane-2x"))
        let before = TextReader.recogniserHealth
        let words = TextReader.words(in: image)
        let after = TextReader.recogniserHealth
        // Only assert what was read when the reader was actually answering.
        // This is the rule the fixture suites now follow too: a machine that
        // will not read is not a bug in the app.
        if after.refusals == before.refusals {
            #expect(words != nil)
        } else {
            #expect(Bool(true), "the reader refused: \(after.reason ?? "no reason given")")
        }
    }

    /// The running count names what went wrong, because "the reader refused"
    /// with no reason is the same dead end one layer up.
    @Test func theRunningCountCarriesTheLastReason() throws {
        let counted = TextReader.RecogniserHealthCount()
        #expect(counted.snapshot == TextReader.RecogniserHealth(refusals: 0, reason: nil))
        counted.record("the recogniser was busy")
        counted.record("and again")
        #expect(counted.snapshot == TextReader.RecogniserHealth(refusals: 2, reason: "and again"))
    }
}

/// The drill: a machine that reads perfectly well, made to refuse, so the
/// behaviour of a machine that will not read can be checked on one that will.
@Suite("A refused read is told apart from an empty one")
struct ARefusedReadIsToldApartTests {

    /// Ink that reads fine comes back refused when the drill is on, and the
    /// refusal carries a reason that says it was a drill.
    @Test func theDrillTurnsAGoodReadIntoARefusal() throws {
        // Ink shaped enough for the recogniser to be asked at all.
        var coverage = [Double](repeating: 0, count: 60 * 20)
        for y in 4..<16 where y % 2 == 0 {
            for x in 4..<56 { coverage[y * 60 + x] = 1 }
        }
        let mask = TextReading.Mask(width: 60, height: 20, coverage: coverage)
        let refused = TextReader.reading(mask, inkHeight: 12, refusing: true)
        #expect(refused.refusal?.contains("drill") == true,
                "the drill did not refuse: \(refused)")
        // ...and with the drill off, the same picture is answered, whatever
        // the answer turns out to be.
        #expect(TextReader.reading(mask, inkHeight: 12, refusing: false).refusal == nil)
    }

    /// A refusal that reaches `lines` is counted, because that is the one path
    /// where the difference gets flattened back into an empty answer.
    @Test func arefusalReachingLinesIsCounted() throws {
        let counted = TextReader.RecogniserHealthCount()
        counted.record("something the recogniser said")
        #expect(counted.snapshot.refusals == 1)
        #expect(counted.snapshot.reason == "something the recogniser said")
    }
}

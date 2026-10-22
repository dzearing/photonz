import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Ask with nothing open: the New window's Describe field, and Ask in an
/// empty window. A request to make a picture makes one and draws it; a request
/// for a video says Ask cannot make one yet; a request about something that
/// would have to be open already says nothing is.
@Suite("Ask with nothing open")
struct AskFromNothingTests {

    let picked = BlankCanvas.defaultPreset.size

    @Test("A request to make a picture makes one at the size picked")
    func pictures() {
        for words in ["a sunset over the sea", "draw a picture of a dog.", "create a smiley face icon",
                      "a cat that is sleeping on a red rug", "paint a lighthouse at night",
                      "add a title that says hello", "a dog chasing its tail"] {
            #expect(AskFromNothing.start(words, picked: picked) == .picture(picked), "\(words)")
        }
    }

    @Test("A size the request names wins over the size picked")
    func namedSize() {
        #expect(AskFromNothing.start("a 1920x1080 sunset", picked: picked) == .picture(CGSize(width: 1920, height: 1080)))
        #expect(AskFromNothing.start("a sunset, 800 × 600", picked: picked) == .picture(CGSize(width: 800, height: 600)))
        #expect(AskFromNothing.start("a sunset 640 by 480 pixels", picked: picked) == .picture(CGSize(width: 640, height: 480)))
        #expect(AskFromNothing.start("a sunset 1200 X 630px", picked: picked) == .picture(CGSize(width: 1200, height: 630)))
    }

    @Test("A named size is kept inside what a canvas may be")
    func namedSizeClamped() {
        #expect(AskFromNothing.namedSize(in: "a 20000x100 banner") == CGSize(width: BlankCanvas.maximumSide, height: 100))
        #expect(AskFromNothing.namedSize(in: "a sunset") == nil)
        #expect(AskFromNothing.namedSize(in: "3 by 4 cats") == nil, "a size has at least two digits a side")
    }

    @Test("A shape or format the request names gives the canvas that shape")
    func formats() {
        let tall = AskFromNothing.start("a poster for a jazz night", picked: picked)
        let wide = AskFromNothing.start("a banner for my blog", picked: picked)
        let square = AskFromNothing.start("a lighthouse in a square image", picked: picked)
        let portrait = AskFromNothing.start("a tree, portrait orientation", picked: picked)
        guard case .picture(let t) = tall, case .picture(let w) = wide,
              case .picture(let s) = square, case .picture(let p) = portrait else {
            Issue.record("each makes a picture"); return
        }
        #expect(t.height > t.width)
        #expect(w.width >= w.height * 2)
        #expect(s.width == s.height)
        #expect(p.height > p.width)
        // A shape word that is the subject is not a format.
        #expect(AskFromNothing.start("a red square", picked: picked) == .picture(picked))
        #expect(AskFromNothing.start("a portrait of a cat", picked: picked) == .picture(picked))
    }

    @Test("A request for a video is one Ask cannot make yet")
    func videos() {
        for words in ["a video of waves", "make an animated logo", "an animation of a bouncing ball",
                      "a short movie about a fox", "a gif of a spinning star"] {
            #expect(AskFromNothing.start(words, picked: picked) == .video, "\(words)")
        }
    }

    @Test("A request about something already open says nothing is")
    func needsSomethingOpen() {
        for words in ["measure this", "find the misalignments", "Measure the gaps between the buttons",
                      "crop the screenshot to the dialog", "make this bigger", "redline these cards",
                      "trim the video to ten seconds", "add a title to the video",
                      "align the selected layers", "make it blue", "blur the faces in the picture"] {
            #expect(AskFromNothing.start(words, picked: picked) == .needsSomethingOpen, "\(words)")
        }
    }

    @Test("Nothing typed is nothing to do")
    func empty() {
        #expect(AskFromNothing.start("   \n", picked: picked) == nil)
    }

    @Test("The sentences fit the chrome")
    func sentences() {
        for line in [AskFromNothing.videoSentence, AskFromNothing.nothingOpenSentence] {
            #expect(line.count <= 30, "\(line)")
            #expect(!line.contains("\u{2014}"))
        }
    }
}

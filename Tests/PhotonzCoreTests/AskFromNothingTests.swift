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
        for words in ["a sunset over the sea", "draw a picture of a dog.",
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
        guard case .picture(let t, _) = tall, case .picture(let w, _) = wide,
              case .picture(let s, _) = square, case .picture(let p, _) = portrait else {
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
        for words in ["a video of waves", "a short movie about a fox", "a clip of my dog running",
                      "a screen recording of the login", "a montage of my recordings", "some footage of the sea",
                      "a slideshow of my trip", "a trailer for my game",
                      // Mixed: something animated FOR a video is still video work.
                      "an animated title for my video", "make an animation for a video intro"] {
            #expect(AskFromNothing.start(words, picked: picked) == .video, "\(words)")
        }
    }

    @Test("A request for something animated makes a picture Ask animates, at the icon size")
    func animated() {
        let icon = BlankCanvas.iconPresets[0].size
        for words in ["make an animated trash can icon where it opens, some trash is thrown in",
                      "an animated loading spinner", "make an animated svg of a heart beating",
                      "a gif of a bouncing ball", "make an animated logo", "an animation of a bouncing ball",
                      "animate a star twinkling", "a looping wave"] {
            guard case .picture(let size, let madeAsIcon)? = AskFromNothing.start(words, picked: picked) else {
                Issue.record("\(words) makes a picture"); continue
            }
            #expect(size == icon, "\(words)")
            // Made as an icon, so Ask draws it as a moving icon whatever the
            // words call it (`AskMotion.drawsMotion(_:blankIcon:)`).
            #expect(madeAsIcon, "\(words)")
            #expect(AskFromNothing.asksForAnimation(words), "\(words)")
        }
        // Its own size or shape still wins.
        #expect(AskFromNothing.start("an animated banner for my blog", picked: picked) == .picture(CGSize(width: 1500, height: 500)))
        #expect(AskFromNothing.start("a 640x480 gif of a bouncing ball", picked: picked) == .picture(CGSize(width: 640, height: 480)))
        for words in ["a sunset over the sea", "a motion sensor", "a moving van"] {
            #expect(!AskFromNothing.asksForAnimation(words), "\(words)")
        }
    }

    @Test("A request for an icon makes an icon at the icon task's sizes")
    func icons() {
        let icon = BlankCanvas.iconPresets[0].size
        let appIcon = BlankCanvas.iconPresets[1].size
        #expect(AskFromNothing.start("create a smiley face icon", picked: picked) == .picture(icon, icon: true))
        #expect(AskFromNothing.start("make an animated trash can icon where it opens", picked: picked) == .picture(icon, icon: true))
        #expect(AskFromNothing.start("an app icon for a weather app", picked: picked) == .picture(appIcon, icon: true))
        // An icon is a picture, whatever it is of.
        #expect(AskFromNothing.start("a video camera icon", picked: picked) == .picture(icon, icon: true))
        #expect(AskFromNothing.start("a movie ticket icon", picked: picked) == .picture(icon, icon: true))
        // An icon size picked below is kept.
        #expect(AskFromNothing.start("a bell icon", picked: appIcon, pickedIsIcon: true) == .picture(appIcon, icon: true))
        #expect(AskFromNothing.start("a bell", picked: icon, pickedIsIcon: true) == .picture(icon, icon: true))
        #expect(AskFromNothing.start("a gif of a bell", picked: appIcon, pickedIsIcon: true) == .picture(appIcon, icon: true))
        // Clip art and a paper clip are pictures.
        #expect(AskFromNothing.start("clip art of a cat", picked: picked) == .picture(picked))
        #expect(AskFromNothing.start("a paper clip on a desk", picked: picked) == .picture(picked))
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

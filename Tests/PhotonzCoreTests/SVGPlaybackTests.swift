import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// When an exported icon plays and what colour it takes on the page it is
/// placed in (`SVGPlayback`), and the page Preview as Web Page writes around
/// it (`SVGPreviewPage`).
@Suite("An exported icon chooses when it plays and whether it follows the page's colour")
struct SVGPlaybackTests {

    /// A spinner the way Export writes one: a loop, one ink, a clip with an id.
    static let spinner = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
      <defs>
        <clipPath id="clip-1">
          <rect x="0" y="0" width="24" height="24"/>
        </clipPath>
      </defs>
      <g clip-path="url(#clip-1)">
        <g transform="rotate(0 12 12)">
          <animateTransform attributeName="transform" type="rotate" dur="1200ms" repeatCount="indefinite" calcMode="linear" keyTimes="0;1" values="0 12 12;360 12 12"/>
          <path d="M9 0 C13 0 18 4 18 9" fill="none" stroke="#1D1D1F" stroke-width="2"/>
        </g>
        <circle cx="12" cy="12" r="2" fill="#1d1d1f"/>
        <circle cx="4" cy="4" r="1" fill="#FF3B30">
          <animate attributeName="fill" dur="1200ms" repeatCount="indefinite" calcMode="linear" keyTimes="0;1" values="#FF3B30;#1D1D1F"/>
        </circle>
        <g>
          <animate attributeName="opacity" begin="300ms" dur="600ms" repeatCount="3" fill="freeze" calcMode="linear" keyTimes="0;1" values="0;1"/>
        </g>
      </g>
    </svg>
    """

    static let still = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
      <path d="M0 0 L24 24" fill="none" stroke="#1D1D1F" stroke-width="2"/>
    </svg>
    """

    static func tags(_ svg: String) -> [String] {
        svg.split(separator: "\n").map(String.init)
            .filter { $0.contains("<animate") || $0.contains("<set ") }
    }

    // MARK: - Plays

    @Test("Always writes exactly the file Export always wrote")
    func alwaysIsUntouched() {
        #expect(SVGPlayback().apply(to: Self.spinner) == Self.spinner)
        #expect(SVGPlayback.standard.isStandard)
    }

    @Test("On hover starts when the pointer enters the icon and stops, back on its first frame, when it leaves")
    func onHover() {
        let svg = SVGPlayback(plays: .onHover).apply(to: Self.spinner, id: "bell")
        #expect(svg.contains("<svg id=\"bell\" xmlns="))
        let tags = Self.tags(svg)
        #expect(tags.count == 3)
        for tag in tags {
            #expect(tag.contains("end=\"bell.mouseleave\""))
            #expect(tag.contains("restart=\"whenNotActive\""))
            // A freeze would hold wherever the pointer left it.
            #expect(!tag.contains("fill=\"freeze\""))
        }
        #expect(tags[0].contains("begin=\"bell.mouseenter\""))
        // A part that waits its turn still waits it, counted from the hover.
        #expect(tags[2].contains("begin=\"bell.mouseenter+300ms\""))
        #expect(!tags[2].contains("begin=\"300ms\""))
    }

    @Test("On hover keeps an id the file already gives itself")
    func onHoverKeepsAnExistingID() {
        let named = Self.spinner.replacingOccurrences(of: "<svg xmlns", with: "<svg id=\"trash\" xmlns")
        let svg = SVGPlayback(plays: .onHover).apply(to: named)
        #expect(svg.components(separatedBy: " id=\"trash\"").count == 2)
        #expect(svg.contains("begin=\"trash.mouseenter\""))
    }

    /// SMIL reads a minus in `trash-can.mouseenter` as an offset, so the
    /// browser never starts it: found by `Scripts/svg-preview-check.mjs` in
    /// WebKit and Chromium on 2026-11-09.
    @Test("An id a browser would misread in an event is swapped for one it reads")
    func onHoverNeedsAPlainID() {
        #expect(!SVGPlayback.defaultID.contains("-"))
        let named = Self.spinner.replacingOccurrences(of: "<svg xmlns", with: "<svg id=\"trash-can\" xmlns")
        let svg = SVGPlayback(plays: .onHover).apply(to: named, id: "bell")
        #expect(!svg.contains("trash-can"))
        #expect(svg.contains("<svg id=\"bell\" xmlns"))
        #expect(svg.contains("begin=\"bell.mouseenter\""))
        let made = SVGPlayback(plays: .onHover).apply(to: Self.spinner, id: "my-icon")
        #expect(made.contains("begin=\"my_icon.mouseenter\""))
    }

    @Test("Once plays one lap and holds its last frame")
    func once() {
        let svg = SVGPlayback(plays: .once).apply(to: Self.spinner)
        let tags = Self.tags(svg)
        #expect(tags.count == 3)
        for tag in tags {
            #expect(tag.contains("repeatCount=\"1\""))
            #expect(tag.components(separatedBy: "fill=\"freeze\"").count == 2)
            #expect(!tag.contains("indefinite"))
        }
        #expect(tags[2].contains("begin=\"300ms\""))
    }

    @Test("A still file has nothing to play, so the choice of when changes nothing")
    func stillIgnoresPlays() {
        #expect(SVGPlayback(plays: .onHover).apply(to: Self.still) == Self.still)
        #expect(SVGPlayback(plays: .once).apply(to: Self.still) == Self.still)
    }

    // MARK: - Colour

    @Test("The main ink is the colour most of the drawing is drawn in, whatever its case")
    func mainInk() {
        #expect(SVGPlayback.mainInk(in: Self.spinner) == "#1D1D1F")
        #expect(SVGPlayback.mainInk(in: "<svg><path fill=\"none\"/></svg>") == nil)
    }

    @Test("On a tie the ink is the plainest colour, not the accent drawn first")
    func mainInkTie() {
        let badgeFirst = """
        <svg><ellipse fill="#FF3B30"/><rect fill="#1D1D1F"/></svg>
        """
        #expect(SVGPlayback.mainInk(in: badgeFirst) == "#1D1D1F")
        let greys = "<svg><rect fill=\"#8E8E93\"/><rect fill=\"#1C1C1E\"/></svg>"
        #expect(SVGPlayback.mainInk(in: greys) == "#1C1C1E", "two plain greys: the darker, which is the one that vanishes on dark")
        let accentOutnumbers = "<svg><rect fill=\"#0A84FF\"/><rect fill=\"#0a84ff\"/><rect fill=\"#1D1D1F\"/></svg>"
        #expect(SVGPlayback.mainInk(in: accentOutnumbers) == "#0A84FF")
    }

    @Test("Follow the page turns the main ink into the page's text colour and leaves the accents alone")
    func followsThePage() {
        let svg = SVGPlayback(ink: .followsPage).apply(to: Self.spinner)
        #expect(!svg.uppercased().contains("STROKE=\"#1D1D1F\""))
        #expect(!svg.uppercased().contains("FILL=\"#1D1D1F\""))
        #expect(svg.contains("stroke=\"currentColor\""))
        #expect(svg.contains("<circle cx=\"12\" cy=\"12\" r=\"2\" fill=\"currentColor\"/>"))
        // An accent keeps its colour, and a colour change into the ink ends
        // on the page's colour too.
        #expect(svg.contains("fill=\"#FF3B30\">"))
        #expect(svg.contains("values=\"#FF3B30;currentColor\""))
        // Nothing else about the file moves.
        #expect(svg.contains("repeatCount=\"indefinite\""))
        #expect(svg.contains("fill=\"none\""))
    }

    @Test("The two choices together")
    func both() {
        let svg = SVGPlayback(plays: .once, ink: .followsPage).apply(to: Self.spinner)
        #expect(svg.contains("stroke=\"currentColor\""))
        #expect(Self.tags(svg).allSatisfy { $0.contains("repeatCount=\"1\"") })
    }

    @Test("The choice travels with the document, and an old document reads as Always, as drawn")
    func remembered() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 24, height: 24), layers: [])
        #expect(document.svgPlayback == .standard)
        let plain = try JSONEncoder().encode(document)
        #expect(!(String(data: plain, encoding: .utf8) ?? "").contains("svgPlayback"))
        document.svgPlayback = SVGPlayback(plays: .onHover, ink: .followsPage)
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.svgPlayback == SVGPlayback(plays: .onHover, ink: .followsPage))
    }

    @Test("Every choice has a short name for the Export sheet")
    func titles() {
        #expect(SVGPlayback.Plays.allCases.map(\.title) == ["Always", "On hover", "Once"])
        #expect(SVGPlayback.Ink.allCases.map(\.title) == ["As drawn", "Follow the page"])
        for title in SVGPlayback.Plays.allCases.map(\.title) + SVGPlayback.Ink.allCases.map(\.title) {
            #expect(title.count <= 30)
        }
    }

    // MARK: - Two copies on one page

    @Test("Every id in a copy is made its own, and everything that points at one follows")
    func uniquingIDs() {
        let hover = SVGPlayback(plays: .onHover).apply(to: Self.spinner, id: "icon")
        let copy = SVGPlayback.uniquingIDs(in: hover, suffix: "_2")
        #expect(copy.contains("id=\"clip-1_2\""))
        #expect(copy.contains("url(#clip-1_2)"))
        #expect(copy.contains("<svg id=\"icon_2\""))
        #expect(copy.contains("begin=\"icon_2.mouseenter\""))
        #expect(copy.contains("end=\"icon_2.mouseleave\""))
        #expect(!copy.contains("\"icon.mouse"))
    }

    // MARK: - The preview page

    @Test("The preview page carries the icon in a hover button, at five sizes on light and dark, and loops a copy")
    func previewPage() {
        let page = SVGPreviewPage.html(svg: Self.spinner, name: "Spinner",
                                       playback: SVGPlayback(plays: .onHover, ink: .followsPage))
        #expect(page.hasPrefix("<!doctype html>"))
        #expect(page.contains("<title>Spinner</title>"))
        // No network: nothing is fetched from anywhere.
        #expect(!page.contains("http://") || !page.contains("src=\"http"))
        #expect(!page.contains("https://"))
        #expect(!page.contains("<link"))
        // The button, with its icon taking only the hover the button hands it.
        #expect(page.contains("class=\"try-button\""))
        #expect(page.contains("pointer-events: none"))
        for size in SVGPreviewPage.sizes {
            #expect(page.contains("data-size=\"\(size)\""))
        }
        #expect(SVGPreviewPage.sizes == [16, 24, 32, 48, 96])
        #expect(page.contains("class=\"strip light\""))
        #expect(page.contains("class=\"strip dark\""))
        #expect(page.contains("data-plays=\"always\""))
        // The copy buttons and the refresh.
        #expect(page.contains(">Copy SVG<"))
        #expect(page.contains(">Copy HTML<"))
        #expect(page.contains(">Refresh<"))
        // No two copies share an id, so each hover reaches its own icon.
        let ids = page.matches(of: /<svg id="([^"]+)"/).map { String($0.1) }
        // Every id an event names is one SMIL can read.
        #expect(ids.allSatisfy { !$0.contains("-") })
        #expect(ids.count >= 1 + 2 * SVGPreviewPage.sizes.count + 1)
        #expect(Set(ids).count == ids.count)
    }

    @Test("The preview shows the chosen way of playing, and the SVG it copies is the one Export writes")
    func previewShowsTheChoice() {
        let once = SVGPreviewPage.html(svg: Self.spinner, name: "Spinner", playback: SVGPlayback(plays: .once))
        #expect(once.contains("data-plays=\"once\""))
        #expect(once.contains(">Once<"))
        let exported = SVGPlayback(plays: .once).apply(to: Self.spinner, id: SVGPreviewPage.iconID)
        #expect(once.contains(SVGPreviewPage.escaped(exported)))
    }

    @Test("A name with markup in it is written as text")
    func escapesTheName() {
        let page = SVGPreviewPage.html(svg: Self.still, name: "<b>&", playback: .standard)
        #expect(page.contains("<title>&lt;b&gt;&amp;</title>"))
    }

    @Test("Copy HTML hands over a button that works pasted anywhere")
    func snippet() {
        let snippet = SVGPreviewPage.snippet(svg: Self.spinner, name: "Spinner",
                                             playback: SVGPlayback(plays: .onHover))
        #expect(snippet.contains("<button"))
        #expect(snippet.contains("Spinner"))
        // On hover needs the button to pass its hover on to the icon.
        #expect(snippet.contains("<script>"))
        #expect(snippet.contains("mouseenter"))
        let looping = SVGPreviewPage.snippet(svg: Self.spinner, name: "Spinner", playback: .standard)
        #expect(!looping.contains("<script>"))
    }
}

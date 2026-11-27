import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Every line of a title's words shows, whatever words it is given and however
/// it is restyled (task `a-main-title-headline-keeps-its-second-line-afte`).
///
/// Written before the fix. A Main Title over a 1280 by 800 recording turned
/// to Sunset, Editorial and Punchy drew only "The Long Way": the bolder face
/// wrapped "Home" onto a second line, and the box was measured again as if
/// the words sat on one line, so the second line fell outside it. A Condensed
/// Poster given "Every window. One glance." either cut "glance." off the same
/// way or ran off the right edge of the picture.
///
/// So every style on the shelf, every page and every card, is given a one,
/// a five and a ten word headline on a 1920 by 1080 and a 1280 by 800 frame,
/// before and after that restyle, and every piece of words in it must hold
/// all of its lines at the width it has, inside the picture.
@Suite("Every line of a title's words shows")
struct TitleEveryLineShowsTests {

    static let headlines = [
        "Launch",
        "Every window. One glance. Today.",
        "The long way home is the one we take together every time",
    ]

    static let frames = [CGSize(width: 1920, height: 1080), CGSize(width: 1280, height: 800)]

    static func document(_ canvas: CGSize) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        return doc
    }

    /// The headline's words changed the way the editor changes them: a box
    /// wider than its words (a centred line) keeps its width and wraps in it,
    /// one hugging its words grows to hug the new ones on one line.
    static func reword(_ doc: inout PhotonzDocument, title: UUID, to words: String) throws {
        let group = try #require(doc.layer(id: title))
        let recipe = try #require(doc.titleRecipe(layerID: title))
        let part = try #require(recipe.design.parts.first { $0.role == .headline })
        let headline = try #require(TitleDesign.find(part.path, in: group))
        var text = try #require(headline.text)
        let frame = try #require(doc.canvasFrame(of: headline.id))
        let hugged = abs(frame.width - TextMeasurement.size(of: text).width.rounded(.up)) <= 1
        text.string = words
        let size = hugged ? TextMeasurement.size(of: text)
            : CGSize(width: frame.width, height: TextMeasurement.size(of: text, wrappingAt: frame.width).height)
        doc.commitTextEdit(id: headline.id, content: text,
                           canvasFrame: CGRect(origin: frame.origin, size: CGSize(width: size.width.rounded(.up),
                                                                                  height: size.height.rounded(.up))))
        let laid = doc.relayOutTitle(layerID: title)
        #expect(laid)
    }

    /// What is wrong with the title's words as they stand: a piece whose
    /// lines do not all fit its box, or a box that leaves the picture.
    static func faults(_ doc: PhotonzDocument, title: UUID) -> [String] {
        guard let group = doc.layer(id: title) else { return ["the title is gone"] }
        let picture = CGRect(origin: .zero, size: doc.canvasSize).insetBy(dx: -0.5, dy: -0.5)
        var found: [String] = []
        for piece in group.selfAndDescendants where piece.isVisible {
            guard let text = piece.text, !text.string.isEmpty,
                  let frame = doc.canvasFrame(of: piece.id) else { continue }
            let needs = TextMeasurement.size(of: text, wrappingAt: frame.width)
            if needs.height > frame.height + 0.5 {
                found.append("\(piece.name) \"\(text.string)\" needs \(Int(needs.height)) down and has \(Int(frame.height))")
            }
            if TextMeasurement.widestWord(in: text) > frame.width + 0.5 {
                found.append("\(piece.name) \"\(text.string)\" has a word wider than its box \(Int(frame.width))")
            }
            if !picture.contains(frame) {
                found.append("\(piece.name) \"\(text.string)\" at \(frame.integral) leaves the picture")
            }
        }
        return found
    }

    /// How far each line of words under the headline sits below it, by
    /// name: what the design set, and what a longer headline must keep.
    static func gapsUnder(_ doc: PhotonzDocument, title: UUID) -> [String: CGFloat] {
        guard let group = doc.layer(id: title),
              let part = doc.titleRecipe(layerID: title)?.design.parts.first(where: { $0.role == .headline }),
              let headline = TitleDesign.find(part.path, in: group),
              let top = doc.canvasFrame(of: headline.id) else { return [:] }
        var gaps: [String: CGFloat] = [:]
        for piece in group.selfAndDescendants where piece.text != nil && piece.id != headline.id {
            guard let frame = doc.canvasFrame(of: piece.id), frame.minY > top.midY else { continue }
            gaps[piece.name] = frame.minY - top.maxY
        }
        return gaps
    }

    /// Lines of words under the headline that came closer to it than the
    /// design set them: drawn over its new lines.
    static func crowded(_ doc: PhotonzDocument, title: UUID, designed: [String: CGFloat]) -> [String] {
        Self.gapsUnder(doc, title: title).compactMap { name, gap in
            guard let set = designed[name], gap < set - 1 else { return nil }
            return "\(name) sits \(Int(gap)) under the headline where the design set \(Int(set))"
        }
    }

    @Test("Every style shows every line of a one, five and ten word headline, before and after a restyle",
          arguments: BuiltInTitle.shelved)
    func everyLineShows(_ preset: BuiltInTitle) throws {
        let sunset = try #require(TitleTheme.curated.first { $0.id == "sunset" })
        let editorial = try #require(TitleFontPair.curated.first { $0.id == "editorial" })
        for canvas in Self.frames {
            for words in Self.headlines {
                var doc = Self.document(canvas)
                let landed = doc.insertTitle(preset, atTimeMS: 1_000)
                let id = try #require(landed).layerID
                let designed = Self.gapsUnder(doc, title: id)
                try Self.reword(&doc, title: id, to: words)
                let typed = Self.faults(doc, title: id) + Self.crowded(doc, title: id, designed: designed)
                #expect(typed.isEmpty, "\(preset.name) \(Int(canvas.width))x\(Int(canvas.height)): \(typed)")
                _ = doc.restyleTitle(layerID: id) { $0.theme = sunset }
                _ = doc.restyleTitle(layerID: id) { $0.fonts = editorial }
                _ = doc.restyleTitle(layerID: id) { $0.energy = .punchy }
                let restyled = Self.faults(doc, title: id) + Self.crowded(doc, title: id, designed: designed)
                #expect(restyled.isEmpty,
                        "\(preset.name) \(Int(canvas.width))x\(Int(canvas.height)) restyled: \(restyled)")
            }
        }
    }

    @Test("A Main Title on a 1280 by 800 frame keeps Home after Sunset, Editorial and Punchy")
    func theLongWayHome() throws {
        var doc = Self.document(CGSize(width: 1280, height: 800))
        let landed = doc.insertTitle(.keynote, atTimeMS: 1_000)
        let id = try #require(landed).layerID
        let sunset = try #require(TitleTheme.curated.first { $0.id == "sunset" })
        let editorial = try #require(TitleFontPair.curated.first { $0.id == "editorial" })
        _ = doc.restyleTitle(layerID: id) { $0.theme = sunset }
        _ = doc.restyleTitle(layerID: id) { $0.fonts = editorial }
        _ = doc.restyleTitle(layerID: id) { $0.energy = .punchy }
        #expect(Self.faults(doc, title: id).isEmpty, "\(Self.faults(doc, title: id))")
    }
}

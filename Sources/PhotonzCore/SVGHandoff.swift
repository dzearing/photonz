import CoreGraphics
import Foundation

/// Where an icon is going, and what the trip costs it.
///
/// Getting an animated icon out of the app is not a format picker. The same
/// animated SVG plays perfectly on a web page, is thrown away the moment a
/// design tool imports it, and is stripped out of a README before anybody sees
/// it. A list of formats cannot tell you any of that, so Export asks where the
/// file is going FIRST — the question most people can answer — and says in
/// plain words what survives.
///
/// The destination picks the format rather than merely warning about it,
/// because a format that cannot carry what you just made is not a choice
/// anybody wants to be left holding. The picker underneath stays exactly where
/// it was, so nothing is taken away from somebody who does know.
public enum SVGHandoff {

    // MARK: - Where it is going

    public enum Destination: String, CaseIterable, Hashable, Codable, Sendable {
        /// An image tag on a page, which is the good case.
        case webPage
        /// A README or an issue on a code host, which cleans what it is given.
        case readme
        /// Another drawing tool, which wants the shapes and not the timing.
        case designTool
        /// An app, which draws the shapes itself.
        case appBundle

        public var title: String {
            switch self {
            case .webPage: "A web page"
            case .readme: "A README on a code host"
            case .designTool: "A design tool"
            case .appBundle: "An app bundle"
            }
        }

        /// Whether a file sent here plays its own animation.
        public var carriesMotion: Bool { self == .webPage }

        public func remember() {
            UserDefaults.standard.set(rawValue, forKey: SVGHandoff.rememberedKey)
        }

        /// Why the motion does not make it, in one plain sentence. Nil for the
        /// destination that carries it.
        public var motionNote: String? {
            switch self {
            case .webPage:
                nil
            case .readme:
                "A code host cleans the files people upload, so the animation is taken out"
                    + " and often the drawing with it. To show the motion there, record a short"
                    + " video and link to it."
            case .designTool:
                "A design tool reads the shapes and leaves the timing behind."
            case .appBundle:
                "An app draws the shapes itself and runs its own animation, so the timing in"
                    + " the file is ignored."
            }
        }
    }

    /// What is actually written for a destination.
    public enum Format: Hashable, Sendable {
        /// Shapes, with the motion in the file.
        case animatedSVG
        /// Shapes, standing still.
        case stillSVG
        /// Pixels: one size, one moment.
        case picture

        public var title: String {
            switch self {
            case .animatedSVG: "Animated SVG"
            case .stillSVG: "SVG"
            case .picture: "PNG"
            }
        }

        public var isVector: Bool { self != .picture }
    }

    /// Where Export last sent something, or a web page.
    public static var remembered: Destination {
        let stored = UserDefaults.standard.string(forKey: rememberedKey) ?? ""
        return Destination(rawValue: stored) ?? .webPage
    }

    /// What a destination gets. A drawing with nothing moving in it is the
    /// same file everywhere: the question only starts to matter once something
    /// moves.
    public static func format(for destination: Destination,
                              in document: PhotonzDocument) -> Format {
        switch destination {
        case .webPage:
            return document.hasMotion ? .animatedSVG : .stillSVG
        case .readme:
            return document.hasMotion ? .picture : .stillSVG
        case .designTool, .appBundle:
            return .stillSVG
        }
    }

    // MARK: - What survives

    /// One thing about the hand-off, and whether it makes the trip.
    public struct Line: Hashable, Sendable, Identifiable {
        public var text: String
        /// Why it does not survive, in plain words. Always there on a line
        /// that does not survive, so nothing is crossed out without a reason.
        public var detail: String?
        public var survives: Bool

        public var id: String { text }

        public init(text: String, detail: String? = nil, survives: Bool) {
            self.text = text
            self.detail = detail
            self.survives = survives
        }
    }

    /// What this document, sent to this destination, keeps and loses.
    public static func lines(for destination: Destination,
                             in document: PhotonzDocument) -> [Line] {
        let format = format(for: destination, in: document)
        let moves = document.hasMotion && destination.carriesMotion
        var lines: [Line] = []

        lines.append(Line(text: "The motion runs in the file",
                          detail: moves ? nil : destination.motionNote,
                          survives: moves))
        lines.append(Line(text: repeatText(in: document),
                          detail: moves ? nil : destination.motionNote,
                          survives: moves))

        // Sharpness is the SVG's whole argument, so it is only claimed where
        // it is true: a picture has one size, and a drawing carrying a
        // photograph has one part of it that does.
        let photographs = embedded(in: document)
        if format == .picture {
            lines.append(Line(text: "Sharp at every size",
                              detail: "A picture has one size. Send it at the size it will be"
                                  + " used at, or twice that for a sharp screen.",
                              survives: false))
        } else if let first = photographs.first {
            let rest = photographs.count > 1 ? " and \(photographs.count - 1) more" : ""
            lines.append(Line(text: "Sharp at every size",
                              detail: "\(first)\(rest) rides along as a picture, so that part of"
                                  + " the drawing has a size of its own.",
                              survives: false))
        } else {
            lines.append(Line(text: "Sharp at every size", survives: true))
        }

        lines.append(Line(text: "The colours you painted", survives: true))

        // The line that earns the screen. Saying it at export time, beside
        // things that DO survive, is worth more than any amount of format
        // detail: an icon in a page is a picture, and a picture is not a
        // button.
        lines.append(Line(text: "Reacting to a tap",
                          detail: "A drawing in a page receives no clicks. Whatever the icon"
                              + " reacts to is the page's job rather than the file's.",
                          survives: false))
        return lines
    }

    /// How the loop is described, in the drawing's own terms.
    static func repeatText(in document: PhotonzDocument) -> String {
        let repeats = document.allLayers
            .flatMap { ($0.motions ?? []).filter(\.isOn) }
            .map(\.repeats)
        if repeats.contains(where: { $0.cycles == nil }) {
            return "It repeats on its own, for ever"
        }
        return "It plays and then stops where it landed"
    }

    /// The layers that go out as pixels inside the file.
    static func embedded(in document: PhotonzDocument) -> [String] {
        SVGExport.embeddedPictures(in: document).map(\.layerName)
    }

    // MARK: - The one it opens on

    /// Where Export last sent something. Handing a set of icons over is
    /// answering this once, not once per icon.
    static let rememberedKey = "export.destination"

    // MARK: - What the file is called

    /// The name Export opens on, so the destination and the file agree.
    public static func fileName(_ base: String, format: Format) -> String {
        let trimmed = base.isEmpty ? "icon" : base
        switch format {
        case .animatedSVG, .stillSVG: return trimmed + ".svg"
        case .picture: return trimmed + ".png"
        }
    }
}

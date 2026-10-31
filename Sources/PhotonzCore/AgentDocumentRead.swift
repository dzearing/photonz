import CoreGraphics
import Foundation

/// A document as an agent reads it: plain structured data, small enough to
/// read in one go (`docs/design/agent-mcp.md`, `read_document`).
///
/// It is a summary, not the file. Defaults are left out (a visible, unlocked,
/// fully opaque layer says none of that), numbers are rounded to what a person
/// would type, long text is cut, and past `mostLayersListed` the rest are
/// counted rather than listed. Ids are the layers' own, so a later tool can
/// name the layer it means. Times are in seconds, the unit people ask in.
public struct AgentDocumentRead: Codable, Hashable, Sendable {

    public static let mostLayersListed = 400
    /// Caption lines past this are counted, not listed.
    public static let mostCaptionLinesListed = 300
    public static let longestText = 200

    /// What the app knows about the window that the document does not.
    public struct Context: Hashable, Sendable {
        public var id: String
        public var title: String
        public var file: String?
        public var playheadMS: Int
        public var canUndo: Bool
        public var canRedo: Bool

        public init(id: String, title: String, file: String?, playheadMS: Int, canUndo: Bool, canRedo: Bool) {
            self.id = id
            self.title = title
            self.file = file
            self.playheadMS = playheadMS
            self.canUndo = canUndo
            self.canRedo = canRedo
        }
    }

    public struct Size: Codable, Hashable, Sendable {
        public var width: Double
        public var height: Double
        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public struct Rect: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public struct Text: Codable, Hashable, Sendable {
        public var string: String
        public var font: String
        public var size: Double
        public var color: String
        public var weight: String
    }

    public struct Shape: Codable, Hashable, Sendable {
        public var shape: String
        public var stroke: String
        public var strokeWidth: Double
        public var fill: String?
        public var caption: String?
    }

    public struct Path: Codable, Hashable, Sendable {
        public var anchors: Int
        public var closed: Bool
        public var stroke: String
        public var strokeWidth: Double
        public var fill: String?
        /// The medium the line is painted with, when it is brushed.
        public var brush: String?
    }

    /// A paint layer: how many strokes it holds and the media they were
    /// painted in, in the order each was first used.
    public struct Painted: Codable, Hashable, Sendable {
        public var strokes: Int
        public var media: [String]
        /// What its strokes paint, by the names they were planned with, in
        /// the order each was first painted: what change_part takes.
        public var parts: [String]?

        public init(strokes: Int, media: [String], parts: [String]? = nil) {
            self.strokes = strokes
            self.media = media
            self.parts = parts
        }
    }

    public struct Time: Codable, Hashable, Sendable {
        public var inSeconds: Double
        public var outSeconds: Double
        public init(inSeconds: Double, outSeconds: Double) {
            self.inSeconds = inSeconds
            self.outSeconds = outSeconds
        }
    }

    public struct Layer: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        /// image, clip, text, shape, path, group, frame, component, zoom-callout,
        /// lens, measurement, collage or sound.
        public var kind: String
        public var frame: Rect
        public var hidden: Bool?
        public var locked: Bool?
        public var opacity: Double?
        /// Degrees, clockwise.
        public var rotation: Double?
        /// horizontal and or vertical, where it wears a flip (Edit ▸
        /// Transform ▸ Flip, or set_layer's flip). A path, a line or a box is
        /// mirrored in its own points instead, and reads unflipped.
        public var flipped: [String]?
        public var cornerRadius: Double?
        public var effects: [String]?
        public var pixels: Size?
        public var text: Text?
        public var shape: Shape?
        public var path: Path?
        public var paint: Painted?
        public var time: Time?
        /// How a group arranges its contents, when it does.
        public var layout: Layout?
        public var children: [Layer]?
    }

    /// A group's Layout section: how it arranges what is inside and the room
    /// it keeps. Only what differs from a group that arranges nothing.
    public struct Layout: Codable, Hashable, Sendable {
        /// stack, grid or free.
        public var arrange: String
        /// row or column, on a stack.
        public var direction: String?
        public var gap: Double?
        public var rowGap: Double?
        public var columns: Int?
        /// The same room on all four sides.
        public var padding: Double?
        /// Top, right, bottom, left, when the sides differ.
        public var paddingSides: [Double]?
        public var width: Double?
        public var height: Double?
        public var spread: Bool?
        public var wraps: Bool?

        static func make(_ layout: GroupLayout) -> Layout {
            let pad = layout.padding
            let sides = [pad.top, pad.right, pad.bottom, pad.left].map(tidy)
            let uniform = Set(sides).count == 1
            let arranges = layout.kind != nil
            return Layout(
                arrange: layout.kind?.rawValue ?? "free",
                direction: layout.kind == .stack ? layout.direction.rawValue : nil,
                gap: arranges ? tidy(layout.gap) : nil,
                rowGap: layout.kind == .grid || layout.wraps ? tidy(layout.rowGap) : nil,
                columns: layout.kind == .grid ? layout.columns : nil,
                padding: uniform ? (sides[0] == 0 ? nil : sides[0]) : nil,
                paddingSides: uniform ? nil : sides,
                width: layout.width.map(tidy), height: layout.height.map(tidy),
                spread: layout.spreadsGap ? true : nil, wraps: layout.wraps ? true : nil)
        }
    }

    public struct Clip: Codable, Hashable, Sendable {
        /// The clip's layer id.
        public var layer: String
        public var name: String
        public var kind: String
        public var inSeconds: Double
        public var outSeconds: Double
        /// Where in its recording the clip starts reading, when it is not the start.
        public var sourceInSeconds: Double?
        /// How many pieces cuts have made of it, when more than one.
        public var pieces: Int?
        /// How many zooms it carries.
        public var zooms: Int?
    }

    /// One word of a caption, and when it starts being said.
    public struct CaptionWord: Codable, Hashable, Sendable {
        public var text: String
        public var atSeconds: Double
    }

    /// One caption line: its layer, its words, when it is up. A command on a
    /// caption word picks the word being said at `seconds`.
    public struct CaptionLine: Codable, Hashable, Sendable {
        public var layer: String
        public var text: String
        public var inSeconds: Double
        public var outSeconds: Double
        public var words: [CaptionWord]
    }

    public struct Track: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var kind: String
        public var hidden: Bool?
        public var muted: Bool?
        public var locked: Bool?
        public var clips: [Clip]
    }

    public struct Transition: Codable, Hashable, Sendable {
        public var kind: String
        public var seconds: Double
    }

    public struct Cut: Codable, Hashable, Sendable {
        public var atSeconds: Double
        public var from: String
        public var to: String
        public var transition: Transition?
    }

    public var id: String
    public var title: String
    public var file: String?
    /// picture or video.
    public var kind: String
    public var canvas: Size
    /// Pixels per point of the capture, when it is not 1 (a Retina screenshot is 2).
    public var pixelScale: Double?
    public var durationSeconds: Double?
    public var playheadSeconds: Double?
    public var canUndo: Bool
    public var canRedo: Bool
    /// Every layer in the document, nested ones included.
    public var layerCount: Int
    /// Top of the stack first, each group's children nested inside it.
    public var layers: [Layer]
    /// Layers past `mostLayersListed`, counted and not listed.
    public var layersNotListed: Int?
    /// Top to bottom, as the timeline shows them.
    public var tracks: [Track]?
    /// Every cut a transition can go on, in time order.
    public var cuts: [Cut]?
    public var markers: [Double]?
    /// The caption lines in time order, when there are captions.
    public var captions: [CaptionLine]?
    /// Caption lines past `mostCaptionLinesListed`, counted and not listed.
    public var captionLinesNotListed: Int?

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    // MARK: Making one

    /// The read, or with `only` just that layer and its contents, listed with
    /// the whole budget (a board of hundreds of layers stops listing long
    /// before the group an agent is working on).
    public static func make(_ document: PhotonzDocument, context: Context, only: UUID? = nil) -> AgentDocumentRead {
        let hasTime = document.hasTime
        var budget = mostLayersListed
        let layers = only.flatMap(document.layer(id:)).map { [summarize($0, budget: &budget)] }
            ?? summarize(document.layers, budget: &budget)
        let count = document.allLayers.count
        var read = AgentDocumentRead(
            id: context.id, title: context.title, file: context.file,
            kind: hasTime ? "video" : "picture",
            canvas: Size(width: tidy(document.canvasSize.width), height: tidy(document.canvasSize.height)),
            pixelScale: document.pixelScale == 1 ? nil : Double(document.pixelScale),
            durationSeconds: hasTime ? seconds(document.documentDurationMS) : nil,
            playheadSeconds: hasTime ? seconds(context.playheadMS) : nil,
            canUndo: context.canUndo, canRedo: context.canRedo,
            layerCount: count, layers: layers,
            layersNotListed: only == nil && count > mostLayersListed ? count - mostLayersListed : nil)
        guard hasTime else { return read }
        let byID = Dictionary(document.layers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        read.tracks = document.timelineTracks.map { track in
            Track(id: track.id.uuidString, name: track.name, kind: track.kind.rawValue,
                  hidden: track.isHidden ? true : nil, muted: track.isMuted ? true : nil,
                  locked: track.isLocked ? true : nil,
                  clips: document.clipIDs(onTrack: track.id).compactMap { byID[$0] }.compactMap(clip))
        }
        let cuts = document.transitionCuts().map { cut in
            Cut(atSeconds: seconds(cut.atMS), from: cut.outgoingName, to: cut.incomingName,
                transition: cut.cut.transition.map {
                    Transition(kind: $0.kind.rawValue, seconds: seconds($0.lengthMS))
                })
        }
        read.cuts = cuts.isEmpty ? nil : cuts
        read.markers = document.markers.isEmpty ? nil : document.markers.map { seconds($0.atMS) }
        let cues = document.captionLayers
        if !cues.isEmpty {
            read.captions = cues.prefix(mostCaptionLinesListed).compactMap { cue in
                guard let time = cue.time, let words = document.captionWordsAsShown(of: cue.id) else { return nil }
                return CaptionLine(layer: cue.id.uuidString, text: cut(words.map(\.text).joined(separator: " ")),
                                   inSeconds: seconds(time.inMS), outSeconds: seconds(time.outMS),
                                   words: words.map { CaptionWord(text: $0.text, atSeconds: seconds($0.startMS)) })
            }
            read.captionLinesNotListed = cues.count > mostCaptionLinesListed ? cues.count - mostCaptionLinesListed : nil
        }
        return read
    }

    private static func clip(_ layer: PhotonzCore.Layer) -> Clip? {
        guard let time = layer.time else { return nil }
        let pieces = layer.clipPieces?.pieces.count ?? 1
        return Clip(layer: layer.id.uuidString, name: layer.name, kind: kind(of: layer),
                    inSeconds: seconds(time.inMS), outSeconds: seconds(time.outMS),
                    sourceInSeconds: time.sourceInMS > 0 ? seconds(time.sourceInMS) : nil,
                    pieces: pieces > 1 ? pieces : nil,
                    zooms: (layer.zooms?.isEmpty ?? true) ? nil : layer.zooms?.count)
    }

    /// The layers top first, spending `budget` as they are listed.
    private static func summarize(_ layers: [PhotonzCore.Layer], budget: inout Int) -> [Layer] {
        var out: [Layer] = []
        for layer in layers.reversed() {
            guard budget > 0 else { break }
            budget -= 1
            out.append(summarize(layer, budget: &budget))
        }
        return out
    }

    private static func summarize(_ layer: PhotonzCore.Layer, budget: inout Int) -> Layer {
        let style = layer.style
        let degrees = Double(layer.transform.rotation) * 180 / .pi
        // A group's stored size is unused: its frame here is the box it covers.
        let box = AgentDrawing.box(of: layer)
        var node = Layer(
            id: layer.id.uuidString, name: layer.name, kind: kind(of: layer),
            frame: Rect(x: tidy(box.minX), y: tidy(box.minY), width: tidy(box.width), height: tidy(box.height)),
            hidden: layer.isVisible ? nil : true,
            locked: layer.isLocked ? true : nil,
            opacity: style.opacity < 1 ? (style.opacity * 100).rounded() / 100 : nil,
            rotation: abs(degrees) < 0.05 ? nil : tidy(degrees),
            cornerRadius: style.cornerRadius > 0 ? tidy(style.cornerRadius) : nil,
            effects: style.effects.isEmpty ? nil : style.effects.map(\.kind.rawValue),
            time: layer.time.map { Time(inSeconds: seconds($0.inMS), outSeconds: seconds($0.outMS)) })
        let flips = FlipAxis.allCases.filter { layer.transform.isFlipped($0) }.map(\.rawValue)
        if !flips.isEmpty { node.flipped = flips }
        switch layer.content {
        case .image(let ref):
            node.pixels = Size(width: tidy(ref.pixelSize.width), height: tidy(ref.pixelSize.height))
        case .text(let text):
            node.text = Text(string: cut(text.string), font: text.fontName, size: tidy(text.fontSize),
                             color: text.colorHex, weight: text.weight.rawValue)
        case .annotation(let shape):
            node.shape = Shape(shape: shape.shape.rawValue, stroke: shape.colorHex,
                               strokeWidth: tidy(shape.strokeWidth), fill: shape.fillColorHex,
                               caption: shape.caption.map(cut))
        case .path(let path):
            node.path = Path(anchors: path.anchors.count, closed: path.isClosed, stroke: path.colorHex,
                             strokeWidth: tidy(path.strokeWidth), fill: path.fillColorHex,
                             brush: path.brush?.medium.rawValue)
        case .group(let group):
            node.layout = group.layout.map(Layout.make)
            let children = summarize(group.children, budget: &budget)
            node.children = children.isEmpty ? nil : children
        case .paint(let paint):
            var media: [String] = []
            for stroke in paint.strokes where !media.contains(stroke.settings.medium.rawValue) {
                media.append(stroke.settings.medium.rawValue)
            }
            var parts: [String] = []
            for stroke in paint.strokes {
                if let part = stroke.part, !parts.contains(part) { parts.append(part) }
            }
            node.paint = Painted(strokes: paint.strokes.count, media: media, parts: parts.isEmpty ? nil : parts)
        case .zoomCallout, .lens, .measure, .collage, .sound:
            break
        }
        return node
    }

    static func kind(of layer: PhotonzCore.Layer) -> String {
        switch layer.content {
        case .image: layer.movie != nil ? "clip" : "image"
        case .text: "text"
        case .annotation: "shape"
        case .path: "path"
        case .paint: "paint"
        case .zoomCallout: "zoom-callout"
        case .lens: "lens"
        case .measure: "measurement"
        case .collage: "collage"
        case .sound: "sound"
        case .group(let group):
            if group.componentID != nil || group.instanceOf != nil { "component" } else if group.isFrame { "frame" } else { "group" }
        }
    }

    /// One decimal place: as precise as anybody types a position.
    static func tidy(_ value: CGFloat) -> Double { tidy(Double(value)) }
    static func tidy(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    static func seconds(_ ms: Int) -> Double { Double(ms) / 1000 }

    static func cut(_ text: String) -> String {
        text.count > longestText ? String(text.prefix(longestText)) + "…" : text
    }
}

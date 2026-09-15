import CoreGraphics
import Foundation

/// What KIND of line a path is drawn with: how it ends, how it turns a corner,
/// and whether it is solid, dashed or dotted.
///
/// Reported by the user on 2026-09-14, on their first real session with the
/// Pen: "in appearance, there is a color but it's not clear its the stroke
/// color and thickness and also no brush style to choose". A path could be
/// given a colour and a weight and nothing else, so every line drawing came out
/// in exactly one voice.
///
/// It matters most for icons, which is what the Pen is here for. What makes a
/// set of line icons read as a set is that every line ends the same way and
/// every corner turns the same way, and it is the one thing about a stroke that
/// cannot be faked afterwards.
///
/// Everything here is a value and nothing here draws: `PathRasterizer` turns
/// these into pixels and `SVGExport` writes them into a file, and the two agree
/// because they read the same three answers.

// MARK: - How a line ends

/// What the ends of an open line look like, and the ends of every dash on a
/// dashed one.
///
/// The names are the shapes, not the drawing-engine words: a person choosing
/// between "butt" and "square" is choosing between two words that mean the same
/// thing in English.
public enum PathLineEnd: String, CaseIterable, Hashable, Codable, Sendable {
    /// Stops dead on the last point. ("butt" to a drawing engine.)
    case flat
    /// A half circle past the last point. What every stroke in the app ends in
    /// unless somebody says otherwise.
    case round
    /// A half square past the last point, so the line is as long as a round one
    /// but keeps its corners.
    case square

    public var title: String {
        switch self {
        case .flat: return "Flat"
        case .round: return "Round"
        case .square: return "Square"
        }
    }

    /// SVG's own word for it. The names part company here and nowhere else,
    /// so a file and the canvas can never disagree about what was drawn.
    var svgName: String {
        switch self {
        case .flat: return "butt"
        case .round: return "round"
        case .square: return "square"
        }
    }

    /// How far past the last point this end reaches, at its very furthest, as a
    /// multiple of the line's width. A round end is a half circle, so half a
    /// width in every direction; a square end is a half square, so its CORNER
    /// is further out than that.
    var reach: CGFloat {
        switch self {
        case .flat, .round: return 0.5
        case .square: return 0.5 * 2.0.squareRoot()
        }
    }
}

// MARK: - How a line turns a corner

/// How the outline turns where two runs meet at an angle.
public enum PathLineCorner: String, CaseIterable, Hashable, Codable, Sendable {
    /// Carried out to a point, the way two rulers cross. What a corner anchor
    /// exists to be. ("miter".)
    case sharp
    /// Turned through an arc of the line's own width.
    case round
    /// The point sliced straight off. ("bevel".)
    case flat

    public var title: String {
        switch self {
        case .sharp: return "Sharp"
        case .round: return "Round"
        case .flat: return "Flat"
        }
    }
}

extension PathLineCorner {

    /// SVG's own word for it.
    var svgName: String {
        switch self {
        case .sharp: return "miter"
        case .round: return "round"
        case .flat: return "bevel"
        }
    }
}

/// How far a sharp corner may be carried out before it is sliced off instead,
/// as a multiple of the line's width.
///
/// Without a limit a very shallow angle sends the point off into a spike
/// hundreds of points long. This is Core Graphics' own default, stated out loud
/// here so the canvas and the exported SVG cannot disagree about it: SVG's
/// default is 4, so a file that did not say would come back a different shape
/// in a browser than it is on the canvas.
public let pathMiterLimit: CGFloat = 10

// MARK: - Solid, dashed, dotted

/// Whether the line is unbroken, or broken into dashes or dots.
///
/// Three named patterns rather than a list of numbers to type. A dash editor is
/// a power tool with nowhere to live in this panel, and what an icon actually
/// needs is a dashed line that looks the same at every weight — which is why
/// these are measured in LINE WIDTHS rather than in points. Turn a dashed line
/// from 2 up to 8 and the dashes grow with it instead of turning into a smear.
public enum PathLinePattern: String, CaseIterable, Hashable, Codable, Sendable {
    case solid
    case dashed
    case dotted

    public var title: String {
        switch self {
        case .solid: return "Solid"
        case .dashed: return "Dashed"
        case .dotted: return "Dotted"
        }
    }

    /// The mark-and-gap pattern, in document points, for a line of this width.
    /// Nil for a solid line, which has none, and for a line of no width, which
    /// has nothing to break up.
    ///
    /// A dot is one width of mark: with round ends that is a dot, with flat
    /// ends a small square, and with square ends a slightly bigger one. The two
    /// settings COMPOSE rather than one of them quietly overriding the other,
    /// which is why the Ends control stays on offer as soon as dashes are on,
    /// even on a closed shape that has no ends of its own.
    public func pattern(forWidth width: CGFloat) -> [CGFloat]? {
        guard width > 0 else { return nil }
        switch self {
        case .solid: return nil
        case .dashed: return [width * 3, width * 2]
        case .dotted: return [width, width * 2]
        }
    }
}

// MARK: - What a path answers

extension PathContent {

    /// The mark-and-gap pattern this path is drawn with, or nil for a solid
    /// line.
    public var dashPattern: [CGFloat]? { linePattern.pattern(forWidth: strokeWidth) }

    /// Whether this path has ends anybody can see, which is what decides
    /// whether the panel asks about them.
    ///
    /// An open path has two. A closed one has none — until it is dashed, and
    /// then every dash has two, which is the whole reason the control stays on
    /// offer rather than being silently overridden.
    public var showsLineEnds: Bool { !isClosed || linePattern != .solid }
}

// MARK: - Setting it

extension PhotonzDocument {

    /// One choice, every picked path. Returns how many took it, so a caller can
    /// tell a no-op from an edit. Locked layers and layers that are not paths
    /// are left exactly as they are.
    @discardableResult
    public mutating func setPathLineEnd(layerIDs: [UUID], to end: PathLineEnd) -> Int {
        changePaths(layerIDs) { $0.lineEnd = end }
    }

    /// The same, for how a corner turns.
    @discardableResult
    public mutating func setPathLineCorner(layerIDs: [UUID], to corner: PathLineCorner) -> Int {
        changePaths(layerIDs) { $0.lineCorner = corner }
    }

    /// The same, for solid, dashed or dotted.
    @discardableResult
    public mutating func setPathLinePattern(layerIDs: [UUID], to pattern: PathLinePattern) -> Int {
        changePaths(layerIDs) { $0.linePattern = pattern }
    }

    /// Gives every picked path an outline, or takes it away.
    ///
    /// A path IS its stroke, so "no outline" is a width of nought rather than a
    /// missing paint: the colour stays put and comes back with the line, the
    /// way a switched-off fill keeps its colour. A path that is handed one back
    /// gets `width`, which is the weight a freshly drawn shape wears.
    ///
    /// The one colour that does NOT stay put is one that would be invisible.
    /// A closed path arrives as its fill and nothing else, both painted the ink
    /// the Pen was armed with, so the first outline it is ever asked for would
    /// otherwise land in the fill's own colour and draw nothing anybody can
    /// see. It takes an ink that reads instead, exactly as a box's first border
    /// does (`BorderInk.swift`).
    @discardableResult
    public mutating func setPathOutline(layerIDs: [UUID], on: Bool,
                                        width: CGFloat = PathContent.defaultStrokeWidth) -> Int {
        changePaths(layerIDs) { path in
            guard (path.strokeWidth > 0) != on else { return }
            guard on else {
                path.strokeWidth = 0
                return
            }
            path.gainingALineThatReads(width: max(width, 1))
        }
    }

    /// Every unlocked picked layer that is a path, changed in place.
    private mutating func changePaths(_ layerIDs: [UUID],
                                      _ change: (inout PathContent) -> Void) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked, var path = layer.path else { continue }
            let before = path
            change(&path)
            guard path != before else { continue }
            updateLayer(id: id) { $0.content = .path(path) }
            changed += 1
        }
        return changed
    }
}

// MARK: - What the three pickers read

/// The picked layers the line style rows reach, and what they say across them.
///
/// Its own reading rather than a question asked of `ShapeSelection`, for the
/// same reason `OutlineThicknessSelection` is: that selection is a list of
/// `AnnotationContent`s and a path has none of those settings. This one asks
/// about paths and nothing else.
public struct PathLineStyleSelection: Hashable, Sendable {

    public struct Member: Hashable, Sendable {
        public let id: UUID
        public let content: PathContent

        public init(id: UUID, content: PathContent) {
            self.id = id
            self.content = content
        }
    }

    public let members: [Member]
    /// How many layers are picked altogether, so a row can say what it leaves
    /// out.
    public let selectionCount: Int

    public init(members: [Member], selectionCount: Int) {
        self.members = members
        self.selectionCount = selectionCount
    }

    public var isEmpty: Bool { members.isEmpty }
    public var layerIDs: [UUID] { members.map(\.id) }

    /// The part of this selection ONE row speaks for. Pick a path and a box
    /// together and the Outline row reaches the path alone, so its pickers
    /// have to reach the path alone too.
    public func of(_ ids: [UUID]) -> PathLineStyleSelection {
        let wanted = Set(ids)
        return PathLineStyleSelection(members: members.filter { wanted.contains($0.id) },
                                      selectionCount: ids.count)
    }

    /// What they all say, or that they differ — the same reading every other
    /// row in the panel gives.
    public func reading<Value: Hashable>(_ of: (PathContent) -> Value) -> StyleReading<Value> {
        guard let first = members.first.map({ of($0.content) }) else {
            return StyleReading(value: nil, isMixed: false)
        }
        let mixed = members.dropFirst().contains { of($0.content) != first }
        return StyleReading(value: first, isMixed: mixed)
    }

    /// Whether the Ends picker is offered at all: as soon as ONE of them has
    /// ends anybody can see. A closed solid shape has none, so asking about
    /// them would be a control that cannot act (`PathContent.showsLineEnds`).
    public var showsLineEnds: Bool { members.contains { $0.content.showsLineEnds } }

    /// Whether there is a line to talk about at all. A path with no outline
    /// shows no line style, exactly as it shows no colour and no thickness.
    public var hasALine: Bool { members.contains { $0.content.strokeWidth > 0 } }
}

extension PhotonzDocument {

    /// The line style rows' view of a set of picked layers, in the order given:
    /// every unlocked path among them.
    public func pathLineStyleSelection(layerIDs: [UUID]) -> PathLineStyleSelection {
        var members: [PathLineStyleSelection.Member] = []
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked, let path = layer.path else { continue }
            members.append(PathLineStyleSelection.Member(id: id, content: path))
        }
        return PathLineStyleSelection(members: members, selectionCount: layerIDs.count)
    }
}

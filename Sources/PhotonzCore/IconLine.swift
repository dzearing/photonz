import CoreGraphics
import Foundation

/// The line an icon is already using, which is the line its next part starts
/// in.
///
/// Found on the whole-workflow walk of 2026-11-07: a Pen line drawn after a
/// 1.75 round outline came out red, 2 units and sharp cornered, so a glyph's
/// second part never matched its first until three rows were set again. The
/// Pen's armed ink and weight are a preference that crosses documents. What a
/// drawing already wears is a better answer to "what does this icon's line
/// look like" than either of them.
public struct IconLine: Hashable, Sendable {
    public var paint: Paint
    public var look: StrokeLook
    public var linePattern: PathLinePattern
    /// What the inside of a closed part beside it is painted with, or nil for
    /// a drawing of bare lines. An open path has no inside, so it says nil.
    public var fill: Paint?
    /// The saved stroke the line wears, so the next part wears it too and
    /// follows the set when its weight changes.
    public var savedStrokeID: UUID?
    /// The saved colours it wears, for the same reason.
    public var inkStyleID: UUID?
    public var fillStyleID: UUID?

    init(_ path: PathContent, on layer: Layer) {
        paint = path.paint
        look = path.strokeLook
        linePattern = path.linePattern
        fill = path.isClosed ? path.fill : nil
        savedStrokeID = path.savedStrokeID
        inkStyleID = layer.colorStyleID(for: .stroke)
        fillStyleID = path.isClosed ? layer.colorStyleID(for: .fill) : nil
    }

    /// The same line at a weight somebody just asked for on the tool bar. It no
    /// longer wears the saved stroke, whose weight this is not.
    public func keeping(width: CGFloat) -> IconLine {
        var line = self
        line.look.width = width
        line.savedStrokeID = nil
        return line
    }

    /// The same line in an ink somebody just asked for on the tool bar.
    public func keeping(paint: Paint) -> IconLine {
        var line = self
        line.paint = paint
        line.inkStyleID = nil
        return line
    }
}

extension PathContent {

    /// Takes on everything an icon's line says, short of its colour on the
    /// inside: that is decided by whether this path is closed.
    mutating func follow(_ line: IconLine) {
        paint = line.paint
        strokeWidth = line.look.width
        wear(line.look)
        linePattern = line.linePattern
        savedStrokeID = line.savedStrokeID
    }
}

extension PhotonzDocument {

    /// The line the icon under this point is using, or nil on anything that is
    /// not an icon, and on an icon with no line in it yet.
    ///
    /// What is picked speaks first, because that is the part you are working
    /// on; failing that it is the topmost line, which is the one last drawn.
    /// A part with no line of its own, or hidden, has nothing to say.
    public func iconLine(drawnAt point: CGPoint, picked: UUID?) -> IconLine? {
        iconFrameID(under: point).flatMap { iconLine(inIcon: $0, picked: picked) }
    }

    /// The same, for a row read before there is any point to ask about: the
    /// icon that is picked in, or failing that the one the pointer is over
    /// (`iconFrameSize(picked:pointerIn:)`). A canvas made as an icon is the one
    /// icon there is, so it needs nobody to name it: the pointer is up on the
    /// tool bar while the row is being read, and the row still has to say what
    /// the next line will be (`iconPreviewFrameID` says the same).
    public func iconLine(picked: UUID?, pointerIn hovered: UUID?) -> IconLine? {
        guard let id = picked ?? hovered ?? (isIconCanvas ? Self.iconCanvasID : nil) else {
            return nil
        }
        return iconFrameID(containing: id).flatMap { iconLine(inIcon: $0, picked: picked) }
    }

    /// The line a given icon is using.
    public func iconLine(inIcon icon: UUID, picked: UUID?) -> IconLine? {
        func line(on layer: Layer) -> IconLine? {
            guard layer.isVisible, let path = layer.path, path.strokeWidth > 0 else { return nil }
            return IconLine(path, on: layer)
        }
        if let picked, iconFrameID(containing: picked) == icon,
           let layer = layer(id: picked), let line = line(on: layer) {
            return line
        }
        for layer in iconContents(of: icon).reversed() {
            for part in layer.selfAndDescendants.reversed() {
                if let line = line(on: part) { return line }
            }
        }
        return nil
    }
}

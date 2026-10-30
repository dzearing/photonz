import CoreGraphics
import Foundation

/// Where an alignment guide lies: which way it runs, where it sits across
/// that, and the stretch it runs along. A `.vertical` guide sits at
/// x = `position` and runs down y = `span`; `.horizontal` mirrors it.
public struct AlignmentGuideLine: Hashable, Sendable {
    public var axis: MeasureMode
    public var position: CGFloat
    public var span: ClosedRange<CGFloat>

    public init(axis: MeasureMode, position: CGFloat, span: ClosedRange<CGFloat>) {
        self.axis = axis
        self.position = position
        self.span = span
    }

    /// The line through two ends. The cross-axis position is read off `start`,
    /// since a guide's two ends always share it.
    public init(axis: MeasureMode, from start: CGPoint, to end: CGPoint) {
        switch axis {
        case .vertical:
            self.init(axis: axis, position: start.x, span: min(start.y, end.y)...max(start.y, end.y))
        case .horizontal:
            self.init(axis: axis, position: start.y, span: min(start.x, end.x)...max(start.x, end.x))
        }
    }

    public var start: CGPoint {
        axis == .vertical ? CGPoint(x: position, y: span.lowerBound)
                          : CGPoint(x: span.lowerBound, y: position)
    }

    public var end: CGPoint {
        axis == .vertical ? CGPoint(x: position, y: span.upperBound)
                          : CGPoint(x: span.upperBound, y: position)
    }

    /// The same line moved by `offset`, for a guide read in its parent's
    /// space and wanted in the document's.
    public func offset(by offset: CGPoint) -> AlignmentGuideLine {
        let (cross, along) = axis == .vertical ? (offset.x, offset.y) : (offset.y, offset.x)
        return AlignmentGuideLine(axis: axis, position: position + cross,
                                  span: (span.lowerBound + along)...(span.upperBound + along))
    }

    /// Whether two lines are the same line to well under a pixel, so a
    /// round trip through a frame does not read as a move.
    func isSame(as other: AlignmentGuideLine) -> Bool {
        let e: CGFloat = 0.001
        return axis == other.axis && abs(position - other.position) < e
            && abs(span.lowerBound - other.span.lowerBound) < e
            && abs(span.upperBound - other.span.upperBound) < e
    }
}

/// The picture an alignment guide reads: the edge map and brightness field of
/// the screenshot under it, both in document space, and its pixel scale.
/// `none` is a canvas with no picture, where only the boxes the document drew
/// have edges.
public struct AlignmentPicture: Sendable {
    public var edges: EdgeMap
    public var luma: LumaField
    public var pixelScale: CGFloat

    public init(edges: EdgeMap, luma: LumaField = .empty, pixelScale: CGFloat = 1) {
        self.edges = edges
        self.luma = luma
        self.pixelScale = pixelScale
    }

    public static let none = AlignmentPicture(edges: .empty)
}

/// What a guide found along a line: the check, and the line it settles on
/// (the reference edge the elements agree on, at the drawn span).
public struct AlignmentMeasurement: Hashable, Sendable {
    public var check: AlignmentCheck
    public var settled: AlignmentGuideLine
}

extension AlignmentScan {

    /// Everything a guide laid along `line` finds, in document space: the
    /// edges the picture shows and the edges of the drawn `boxes`, as one
    /// list, judged at `tolerance` (device px). The ONE scan behind a guide
    /// drawn fresh and a guide moved, stretched, nudged or typed into a new
    /// place, so the two can never disagree.
    ///
    /// The guide settles on the verdict's reference; with one edge it sits on
    /// that edge, and with none it stays where it was put.
    public static func measure(_ line: AlignmentGuideLine, picture: AlignmentPicture,
                               boxes: [CGRect], tolerance: CGFloat) -> AlignmentMeasurement {
        let drawn = drawnItems(axis: line.axis, position: line.position, span: line.span,
                               boxes: boxes)
        let read = items(axis: line.axis, position: line.position, span: line.span,
                         in: picture.edges, luma: picture.luma, pixelScale: picture.pixelScale)
        let found = merged(drawn: drawn, picture: read)
        // Counted only when the count means something: the picture was read,
        // or every item on the list is a box the document drew, which is
        // exactly one element each.
        let check = AlignmentCheck(items: found, tolerance: tolerance,
                                   itemsAreElements: !picture.luma.isEmpty || found.count == drawn.count)
        let reference = check.verdict?.reference ?? found.first?.edge ?? line.position
        var settled = line
        settled.position = reference
        return AlignmentMeasurement(check: check, settled: settled)
    }
}

extension Layer {
    /// An alignment guide's line, in its PARENT's space (the document's, for a
    /// guide at the top level). Nil for anything that is not a guide.
    public var alignmentGuideLine: AlignmentGuideLine? {
        guard let m = measure, m.alignment != nil,
              let start = measureEndpoint(.start), let end = measureEndpoint(.end) else { return nil }
        return AlignmentGuideLine(axis: m.mode, from: start, to: end)
    }
}

extension MeasureBuilder {

    /// `layer`, an alignment guide, measured again along `line` (document
    /// space) exactly as a guide drawn there fresh would be: new items, new
    /// verdict, settled on the new reference, its readout placed again unless
    /// somebody put it by hand. Its name, look, tolerance and identity stay.
    ///
    /// `parentOrigin` is where the guide's parent sits in the document, so a
    /// guide inside a group is laid back down in the group's own space.
    /// Anything that is not a guide comes back untouched.
    public static func remeasured(_ layer: Layer, along line: AlignmentGuideLine,
                                  picture: AlignmentPicture, boxes: [CGRect],
                                  canvas: CGSize?, avoiding others: [CGRect],
                                  parentOrigin: CGPoint = .zero) -> Layer {
        guard var m = layer.measure, let old = m.alignment else { return layer }
        let found = AlignmentScan.measure(line, picture: picture, boxes: boxes,
                                          tolerance: old.tolerance)
        m.mode = line.axis
        m.headOffset = 0
        m.start = found.settled.start
        m.end = found.settled.end
        m.alignment = found.check
        if !m.labelPinned {
            m.apply(MeasureLabelPlanner.plan(for: m, canvas: canvas, avoiding: others))
        }
        // Built in document space, then carried into the parent's.
        let built = self.layer(content: m, from: found.settled.start, to: found.settled.end)
        var updated = layer
        updated.frame = built.frame.offsetBy(dx: -parentOrigin.x, dy: -parentOrigin.y)
        updated.content = built.content
        return updated
    }
}

extension PhotonzDocument {

    /// Measures again every alignment guide whose line this edit changed, so
    /// a guide moved, stretched, nudged, typed into a new place or moved by an
    /// agent says what is under it NOW (the user, 2026-10-30). Run on every
    /// edit, beside `keepMeasureNamesInStep`, so the move and the new verdict
    /// are one undo step.
    ///
    /// A guide this edit added is left alone (it was measured as it was laid
    /// down), and so is one whose line did not change: a restyle, a rename, a
    /// hide. `picture` nil means the screenshot's edges are not known yet, and
    /// a guide keeps what it found rather than finding nothing.
    public mutating func keepAlignmentGuidesMeasured(since before: PhotonzDocument?,
                                                     picture: AlignmentPicture?) {
        guard let before, let picture else { return }
        var moved: [(id: UUID, line: AlignmentGuideLine)] = []
        forEachLayer { layer in
            guard let line = layer.alignmentGuideLine,
                  let was = before.layer(id: layer.id)?.alignmentGuideLine,
                  !line.isSame(as: was) else { return }
            moved.append((layer.id, line))
        }
        guard !moved.isEmpty else { return }
        let boxes = LayerElements.boxes(in: self)
        for (id, line) in moved {
            let origin = parentOrigin(of: id) ?? .zero
            let others = canvasMeasureLayers.filter { $0.id != id }.compactMap(MeasureBuilder.readoutRect)
            let canvas = canvasSize
            updateLayer(id: id) {
                $0 = MeasureBuilder.remeasured($0, along: line.offset(by: origin), picture: picture,
                                               boxes: boxes, canvas: canvas, avoiding: others,
                                               parentOrigin: origin)
            }
        }
    }
}

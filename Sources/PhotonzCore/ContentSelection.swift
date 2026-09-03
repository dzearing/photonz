import CoreGraphics
import Foundation

// The type rows and the shape rows, speaking for a whole selection.
//
// The Color and Effects sections already do this: pick four buttons and one
// pull on Corner Radius rounds all four. These two sections did not, so making
// three labels 14pt was three trips round the panel and three undo steps, and
// picking a second arrow made the shape settings vanish altogether.
//
// The reading rules are the ones `LayerStyleSelection` set (`StyleReading`
// lives there): what they agree on, or Mixed. What is new here is that these
// rows are not offered by every layer. A rectangle has corners and an arrow has
// a head, so a selection offers the rows the picked shapes SHARE rather than
// every row any of them has.

// MARK: - Text

/// The picked text layers, and what one type row reads across them.
public struct TextLayerSelection: Hashable, Sendable {

    public struct Member: Hashable, Sendable {
        public let id: UUID
        public let content: TextContent

        public init(id: UUID, content: TextContent) {
            self.id = id
            self.content = content
        }
    }

    public let members: [Member]
    /// Everything picked, including the layers that are not text, so the
    /// section can say what it does and does not reach.
    public let selectionCount: Int

    public init(members: [Member], selectionCount: Int) {
        self.members = members
        self.selectionCount = selectionCount
    }

    public var count: Int { members.count }
    public var isEmpty: Bool { members.isEmpty }
    /// The layers one change in this section restyles, in panel order.
    public var layerIDs: [UUID] { members.map(\.id) }

    /// What one row reads: the thing they all say, or that they differ.
    public func reading<Value: Hashable & Sendable>(
        _ read: (TextContent) -> Value
    ) -> StyleReading<Value> {
        guard let first = members.first.map({ read($0.content) }) else {
            return StyleReading(value: nil, isMixed: false)
        }
        let mixed = members.dropFirst().contains { read($0.content) != first }
        return StyleReading(value: first, isMixed: mixed)
    }

    /// The same reading for the rows that carry a number.
    public func number(_ read: (TextContent) -> CGFloat) -> StyleReading<CGFloat> {
        reading { read($0) }
    }

    /// Every family the picked labels are set in, so a menu offering a curated
    /// list still offers the ones already on screen. In the order they were
    /// picked, without repeats.
    public var fontNames: [String] { distinct { $0.fontName } }

    /// And every size, for the same reason: a label at 37pt must not lose its
    /// size just because 37 is not on the list.
    public var fontSizes: [CGFloat] { distinct { $0.fontSize } }

    private func distinct<Value: Hashable>(_ read: (TextContent) -> Value) -> [Value] {
        var seen: Set<Value> = []
        return members.compactMap { seen.insert(read($0.content)).inserted ? read($0.content) : nil }
    }

    /// What the section says out loud when it is leaving a picked layer out.
    /// Nil when it reaches everything, because a sentence saying "this does
    /// what it looks like it does" is a sentence in the way.
    public var note: String? { reachNote(count: count, selectionCount: selectionCount) }
}

// MARK: - Shapes

/// One row in a shape's own settings. Not every shape has every one, which is
/// the whole reason a selection has to work out which rows it can offer.
public enum ShapeSettingRow: String, CaseIterable, Hashable, Sendable {
    /// How thick the stroke is. Every shape but a highlight.
    case thickness
    /// The words on an arrow. Content rather than looks, so it is offered for
    /// ONE arrow only: a single field over three arrows could only give all
    /// three the same words, which nobody has ever wanted.
    case caption
    /// How big those words are, once there are some.
    case labelSize
    /// An arrowhead's size.
    case headSize
}

extension AnnotationContent {
    /// The rows this one shape offers, in the order the section shows them.
    public var settingRows: [ShapeSettingRow] {
        var rows: [ShapeSettingRow] = []
        if shape != .highlight { rows.append(.thickness) }
        if shape == .arrow {
            rows.append(.caption)
            if hasCaption { rows.append(.labelSize) }
            rows.append(.headSize)
        }
        return rows
    }
}

/// The picked shapes, the rows they can all answer for, and what those rows
/// read across them.
public struct ShapeSelection: Hashable, Sendable {

    public struct Member: Hashable, Sendable {
        public let id: UUID
        public let content: AnnotationContent
        /// A ring the old Effects Border slider left on this shape's LOOK.
        /// Shapes drawn since have none: the Thickness row is the only way to
        /// a line round a shape now, and it writes the shape's own stroke.
        /// Carried here so that row can read the ring actually on screen.
        public let styleBorderWidth: CGFloat

        public init(id: UUID, content: AnnotationContent, styleBorderWidth: CGFloat = 0) {
            self.id = id
            self.content = content
            self.styleBorderWidth = styleBorderWidth
        }
    }

    public let members: [Member]
    public let selectionCount: Int

    public init(members: [Member], selectionCount: Int) {
        self.members = members
        self.selectionCount = selectionCount
    }

    public var count: Int { members.count }
    public var isEmpty: Bool { members.isEmpty }
    public var layerIDs: [UUID] { members.map(\.id) }

    /// The rows every picked shape has. A Head Size slider over a rectangle
    /// would be a control that does nothing, so a rectangle picked with an
    /// arrow takes the head away and leaves the thickness they share.
    public var rows: [ShapeSettingRow] {
        guard let first = members.first else { return [] }
        var shared = Set(first.content.settingRows)
        for member in members.dropFirst() {
            shared.formIntersection(member.content.settingRows)
        }
        // The caption is one arrow's words, never a selection's.
        if count > 1 { shared.remove(.caption) }
        return ShapeSettingRow.allCases.filter { shared.contains($0) }
    }

    public func reading<Value: Hashable & Sendable>(
        _ read: (AnnotationContent) -> Value
    ) -> StyleReading<Value> {
        guard let first = members.first.map({ read($0.content) }) else {
            return StyleReading(value: nil, isMixed: false)
        }
        let mixed = members.dropFirst().contains { read($0.content) != first }
        return StyleReading(value: first, isMixed: mixed)
    }

    public func number(_ read: (AnnotationContent) -> CGFloat) -> StyleReading<CGFloat> {
        reading { read($0) }
    }

    /// The picked arrows whose label pill was dragged by hand, and so have a
    /// spot to be put back from.
    public var pinnedCaptionIDs: [UUID] {
        members.filter { $0.content.hasCaption && $0.content.captionPinned }.map(\.id)
    }

    /// What the section is headed. One shape is named after itself, several of
    /// a kind are named in the plural, and a mixture is just Shapes — because
    /// heading a rectangle's settings "Annotation" is a word out of the code
    /// and nothing on screen is called that.
    public var title: String {
        guard let first = members.first?.content.shape else { return "Shapes" }
        guard members.allSatisfy({ $0.content.shape == first }) else { return "Shapes" }
        return count > 1 ? first.pluralTitle : first.title
    }

    public var note: String? { reachNote(count: count, selectionCount: selectionCount) }
}

/// The one sentence both sections say when they are speaking for fewer layers
/// than are picked. One place, so they cannot word it differently.
private func reachNote(count: Int, selectionCount: Int) -> String? {
    guard count > 0, count < selectionCount else { return nil }
    return "Applies to \(count) of the \(selectionCount) selected layers."
}

// MARK: - Reading them off a document

extension PhotonzDocument {

    /// The type rows' view of a set of picked layers: the text among them, in
    /// the order given, with locked layers left out for the same reason the
    /// color rows leave them out.
    public func textSelection(layerIDs: [UUID]) -> TextLayerSelection {
        var members: [TextLayerSelection.Member] = []
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  case .text(let content) = layer.content else { continue }
            members.append(TextLayerSelection.Member(id: id, content: content))
        }
        return TextLayerSelection(members: members, selectionCount: layerIDs.count)
    }

    /// The same for the shape rows. A highlight sits the section out rather
    /// than emptying it: it has nothing but a color, and its color is in the
    /// Color section with every other color.
    public func shapeSelection(layerIDs: [UUID]) -> ShapeSelection {
        var members: [ShapeSelection.Member] = []
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  let annotation = layer.annotation,
                  annotation.shape.hasSettingsBesidesColor else { continue }
            members.append(ShapeSelection.Member(id: id, content: annotation,
                                                 styleBorderWidth: layer.style.borderWidth))
        }
        return ShapeSelection(members: members, selectionCount: layerIDs.count)
    }
}

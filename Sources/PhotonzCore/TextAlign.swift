import CoreGraphics
import Foundation

/// Where the words sit inside the box that holds them.
///
/// A text layer has always been drawn from the top left of its box, which is
/// invisible while the box hugs the words and wrong the moment it does not: a
/// label told to stretch across a button fills the width and leaves its word
/// stuck against the left edge. This is the missing half of that: the box says
/// how big it is, and this says where the words sit in it.
///
/// See `docs/design/ui-building.md`, "Where the words sit in their box".
public enum TextAlign: String, CaseIterable, Hashable, Codable, Sendable {
    case left
    case center
    case right

    public var title: String {
        switch self {
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        }
    }
}

/// The same idea down the box.
public enum TextVerticalAlign: String, CaseIterable, Hashable, Codable, Sendable {
    case top
    case middle
    case bottom

    public var title: String {
        switch self {
        case .top: "Top"
        case .middle: "Middle"
        case .bottom: "Bottom"
        }
    }
}

extension TextContent {

    /// Where the words actually sit across the box. Nothing set means the left
    /// edge, which is what every piece of text in every document written
    /// before this existed was drawn at.
    public var usedAlignment: TextAlign { alignment ?? .left }

    /// And down it: the top, for the same reason.
    public var usedVerticalAlignment: TextVerticalAlign { verticalAlignment ?? .top }
}

extension Layer {

    /// This layer's own words, if it holds any.
    public var text: TextContent? {
        if case .text(let content) = self.content { return content }
        return nil
    }

    /// The words this layer should carry once it has been told to fill the
    /// width of whatever holds it, or nil when nothing about them changes.
    ///
    /// Telling a piece of text to stretch has to DO something, and a box that
    /// spans the container with its word still against the left edge is the
    /// picture you already had. So the moment text is set to stretch, and only
    /// while it has never been given an alignment of its own, its words move to
    /// the middle of the box they now fill. It is one ordinary edit: the Align
    /// row reads Center afterwards, one undo puts it back, and choosing Left
    /// there sticks — coming off stretch later never rewrites it again.
    public func textAlignedToFill(horizontal: HorizontalPlacement?) -> TextContent? {
        guard horizontal == .stretch, var content = text, content.alignment == nil else { return nil }
        content.alignment = .center
        return content
    }

    /// The same, down the box: a piece of text told to fill the height centres
    /// its lines in it rather than hugging the top edge of a box it no longer
    /// fits.
    public func textAlignedToFill(vertical: VerticalPlacement?) -> TextContent? {
        guard vertical == .stretch, var content = text,
              content.verticalAlignment == nil else { return nil }
        content.verticalAlignment = .middle
        return content
    }

    /// The box this text goes back to the moment it stops being told to fill
    /// the height of what holds it, or nil when it is already that box.
    ///
    /// Nothing else can hand that height back. A text box has no height handle
    /// and its Height field takes no number, so a label left at the height of
    /// the row it used to fill would be stuck that tall for good, and the only
    /// way out would be to delete it and type it again. The width is untouched:
    /// only the height was ever the container's to give.
    public var textReleasedFromFill: CGRect? {
        guard text != nil else { return nil }
        let box = textRefitted(hugging: false, anchor: .left).frame
        return box == frame ? nil : box
    }
}

extension PhotonzDocument {

    /// Moves one text layer's words across their box.
    ///
    /// The box itself never changes: alignment is about where the words sit in
    /// the room they already have, so a label that was dragged wide stays wide
    /// and a stretched one keeps its stretch.
    public mutating func setTextAlignment(id: UUID, _ alignment: TextAlign) {
        guard var content = layer(id: id)?.text else { return }
        content.alignment = alignment
        updateLayer(id: id) { $0.content = .text(content) }
    }

    /// The same, down the box.
    public mutating func setTextAlignment(id: UUID, _ alignment: TextVerticalAlign) {
        guard var content = layer(id: id)?.text else { return }
        content.verticalAlignment = alignment
        updateLayer(id: id) { $0.content = .text(content) }
    }
}

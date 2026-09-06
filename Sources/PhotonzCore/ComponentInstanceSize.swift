import CoreGraphics
import Foundation

/// A copy with a size of its own (`docs/design/ui-building.md`, "A copy can be
/// given its own size").
///
/// Everything inside a copy belongs to its original and is refilled after every
/// edit, which is why the copy's width and height boxes used to be dead: a
/// number typed there was gone by the next redraw. The size is the one answer
/// worth keeping, because the same nav bar is 1200 points wide on a desktop
/// screen and 375 on a phone, and breaking a copy away from its family to say
/// so loses every future edit to the original.
///
/// The rule is the same one the colour knob follows: **the original's answer
/// first, the copy's few own answers written over the top**. So a copy that has
/// been widened still takes a new colour, new wording and new spacing from its
/// original; only the side it was given stops following. It is owned one axis
/// at a time, because a nav bar copy owning its width and still following the
/// original's height is the ordinary case, not a special one.

/// The width and height a copy has been given, where it has been given them.
/// Nil on an axis is the whole point: that side still comes from the original.
public struct InstanceSize: Hashable, Codable, Sendable {
    public var width: CGFloat?
    public var height: CGFloat?

    public init(width: CGFloat? = nil, height: CGFloat? = nil) {
        self.width = width
        self.height = height
    }

    /// A copy that follows its original on both sides, which is every copy the
    /// moment it is placed.
    public static let following = InstanceSize()

    /// Whether this copy has been given nothing at all, so the record can be
    /// dropped rather than saved as a pair of blanks.
    public var isFollowing: Bool { width == nil && height == nil }

    /// The size actually used on each axis. Negative is not a thing anyone
    /// means, and typing over a field passes through odd values on the way to a
    /// number, so the model holds the floor rather than refusing the typing —
    /// the same reading `GroupLayout` gives its own two sides.
    public var usedWidth: CGFloat? { Self.usedSide(width) }
    public var usedHeight: CGFloat? { Self.usedSide(height) }

    private static func usedSide(_ side: CGFloat?) -> CGFloat? {
        guard let side, side.isFinite else { return nil }
        return max(0, side)
    }

    /// What this copy owns, in the words the Component section uses: `1200
    /// wide`, `48 tall`, or both. Nil when it owns neither, so the row is not
    /// there at all rather than there and empty.
    public var inWords: String? {
        var parts: [String] = []
        if let width = usedWidth { parts.append("\(Self.number(width)) wide") }
        if let height = usedHeight { parts.append("\(Self.number(height)) tall") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// A measurement as somebody would say it out loud: no trailing nought on a
    /// number that is a whole one, which nearly all of them are.
    private static func number(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", Double(value))
    }
}

/// Putting a copy's own size back over the original's answer.
///
/// Both the places that rebuild a copy from its original go through here — the
/// layout for an ordinary copy, the box for a copy of a screen — so the two can
/// never disagree about which side the copy owns.
enum InstanceSizing {

    /// The layout a copy works to: its original's, with any side the copy owns
    /// written over the top.
    ///
    /// An original that arranges nothing and has never been given a layout at
    /// all still hands one back here, because a copy that owns a width needs
    /// somewhere to keep it. It is the layout that original is already working
    /// to (`Layer.workingLayout`), so nothing about the copy moves except the
    /// side that was set.
    static func layout(main: Layer, own: InstanceSize?) -> GroupLayout? {
        guard let own, !own.isFollowing else { return main.group?.layout }
        var layout = main.group?.layout ?? main.workingLayout
        if let width = own.usedWidth { layout.width = width }
        if let height = own.usedHeight { layout.height = height }
        return layout
    }

    /// The box a copy of a SCREEN fills. A screen's size is its own frame
    /// rather than anything in its layout, so the override lands there instead.
    static func frameSize(main: Layer, own: InstanceSize?) -> CGSize {
        CGSize(width: own?.usedWidth ?? main.frame.size.width,
               height: own?.usedHeight ?? main.frame.size.height)
    }

    /// A copy whose contents have been moved out of the box its ORIGINAL fills
    /// and into the box the copy was given, by the same rules a resize of the
    /// original would have followed.
    ///
    /// A copy is rebuilt from its original after every edit, so its contents
    /// always arrive laid out for the original's box. A stack or a grid puts
    /// them right on its own, because a flow lays out into whatever bounds it
    /// is handed. A group that arranges nothing does not: it leaves everything
    /// where it was put and only stretches what asked to stretch. Without this,
    /// a nav bar copy dragged out to 1200 keeps its title where 320 put it,
    /// while the same bar resized as the original centres it.
    static func fitted(_ copy: Layer, filling original: CGSize) -> Layer {
        guard let group = copy.group, group.layout?.arranges != true else { return copy }
        let box = copy.localBounds.size
        guard box != original, original.width > 0 || original.height > 0 else { return copy }
        var out = copy
        out.children = LayerScaling.placingContents(
            copy.children,
            from: CGRect(origin: .zero, size: original),
            to: CGRect(origin: .zero, size: box),
            container: group.contentPlacement,
            // A screen hands nothing a rule it did not ask for, so a piece
            // nobody placed holds still there rather than being magnified.
            unsetHoldsStill: group.isFrame)
        return out
    }
}

// MARK: - Reading and setting it

extension Layer {

    /// The size this copy has been given, nil for anything that is not a copy
    /// and for a copy that follows its original on both sides.
    public var instanceSize: InstanceSize? { group?.instanceSize }

    /// Whether this copy has stopped following its original on either side.
    public var ownsItsSize: Bool { !(instanceSize?.isFollowing ?? true) }

    /// This copy's own size, set or dropped, leaving everything else alone. A
    /// record with nothing in it is dropped rather than kept as a pair of
    /// blanks, so "follows the original" has exactly one spelling.
    mutating func setInstanceSize(_ size: InstanceSize?) {
        guard var group, group.instanceOf != nil else { return }
        group.children = children
        group.instanceSize = (size?.isFollowing ?? true) ? nil : size
        content = .group(group)
    }
}

extension PhotonzDocument {

    /// Whether this copy has a size of its own on either side. What puts the
    /// "Its own size" row on the Component section.
    public func instanceOwnsSize(id: UUID) -> Bool {
        layer(id: id)?.ownsItsSize ?? false
    }

    /// What that row says: `1200 wide`, `48 tall`, or both. Nil for a copy that
    /// follows its original, and for anything that is not a copy.
    public func instanceOwnSizeLabel(instance: UUID) -> String? {
        layer(id: instance)?.instanceSize?.inWords
    }

    /// What that row says for SEVERAL picked copies: the one copy's own words
    /// when one is picked, else how many of them have a size of their own.
    /// Nil when none of them does, which is what keeps the row off the section
    /// until there is something to say.
    public func instanceOwnSizeLabel(instances: [UUID]) -> String? {
        let own = instances.filter { instanceOwnsSize(id: $0) }
        guard !own.isEmpty else { return nil }
        if instances.count == 1 { return instanceOwnSizeLabel(instance: instances[0]) }
        return ComponentInstanceCount.phrase(own.count, of: instances.count,
                                             singular: "has its own size",
                                             plural: "have their own size")
    }

    /// Puts copies back on their original's size, both sides at once. Returns
    /// how many had something to put back, so a caller can tell a no-op from an
    /// edit.
    ///
    /// One way back rather than one per side, because "make it the size the
    /// original is" is the errand, and a copy that owns only its width already
    /// shows only that in the row above the button.
    @discardableResult
    public mutating func clearInstanceSize(instances: [UUID]) -> Int {
        var count = 0
        for id in instances where instanceOwnsSize(id: id) {
            guard layer(id: id)?.isLocked != true else { continue }
            updateLayer(id: id) { $0.setInstanceSize(nil) }
            count += 1
        }
        return count
    }
}


/// How a row about several copies counts them, so the two rows that do it say
/// it the same way rather than inventing a sentence each.
public enum ComponentInstanceCount {

    /// "All 3", "2 of the 3 copies", "1 of the 3 copies", with the verb that
    /// goes with the count.
    public static func phrase(_ some: Int, of all: Int,
                              singular: String, plural: String) -> String {
        let verb = some == 1 ? singular : plural
        if some == all { return "All \(all) \(verb)" }
        return "\(some) of the \(all) copies \(verb)"
    }
}

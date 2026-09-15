import Foundation

/// The colours a row can PAINT with but cannot wear the NAME of.
///
/// Reported by the user on 2026-09-15:
///
/// > I have a circle and a line. The line is a different color than the
/// > circle's border. I want to quickly match them. It's hard. I save the style
/// > of the circle border, try to use that for the color of the line, no luck.
/// > they mismatch on type. this is weird. Any style which holds a color should
/// > be usable for a color style.
///
/// A colour row has always offered a SHORT list: only the saved colours meant
/// for the part it paints, because a row that offered every colour in the
/// document put a colour somebody made for hairlines on the menu as something
/// to fill a box with (`ColorStyleRole`). That is still right, and it is not
/// what went wrong here.
///
/// What went wrong is that everything the short list leaves out disappears
/// without trace. Three things fall down that gap:
///
/// * The colour inside a saved BORDER, shadow, glow or way of setting text. It
///   is a style and it holds a colour, but it is not a saved COLOUR, so no
///   colour row has ever had a way to reach it. That is the one the user hit:
///   "the style of the circle border" is the Style row at the top of the Border
///   section, and the colour in it had no way out.
/// * A saved colour kept for other parts. The row knows it is kept for fills
///   and says nothing about it, so the colour somebody saved a minute ago reads
///   as gone.
/// * A saved ramp on a row that can only draw one flat colour. The row drops it
///   silently, even though letting the ramp GO on that row has always been
///   allowed and has always said so out loud (`ColorDrop`).
///
/// So the row keeps its short list of names, and gains a second list under it:
/// the colours it can still paint with, each saying where it comes from. Nobody
/// has to know which kind of style a colour was saved in to use it as a colour,
/// which is exactly what the user asked for.
///
/// Picking one paints the colour and no more. It cannot carry a name, because
/// the name belongs to a border or to a way of setting text and a line wearing
/// "Circle edge" would claim to follow something it cannot follow. That is the
/// same answer a drag already gives when a saved colour lands on a part it is
/// not kept for: the colour lands, the name stays behind, and the swatch says
/// so before you let go.
public struct BorrowedColor: Identifiable, Hashable, Sendable {

    /// Where a colour that is not on the short list came from.
    public enum Source: Hashable, Sendable {
        /// A saved colour kept for other parts of a layer.
        case keptForOtherParts([ColorStyleRole])
        /// A saved ramp, on a row that can only draw one flat colour.
        case gradient
        /// The colour inside a saved way of setting text.
        case textStyle
        /// The colour inside a saved effect: a border, a shadow, a glow.
        case effectStyle(EffectKind)
    }

    /// The style this colour was taken out of. Unique in one list, which is
    /// what makes it the id.
    public let id: UUID
    /// What that style is called.
    public var name: String
    /// The colour as this row would paint it: already flat where the row can
    /// only draw one colour, so what the menu says is what lands.
    public var paint: Paint
    public var source: Source

    public init(id: UUID, name: String, paint: Paint, source: Source) {
        self.id = id
        self.name = name
        self.paint = paint
        self.source = source
    }

    /// Where this colour comes from, in a couple of plain words, for the menu
    /// row to carry beside the name. Without it a second list of names under
    /// the first one reads as the same list twice.
    public var origin: String {
        switch source {
        case .keptForOtherParts(let roles):
            return "for \(BorrowedColor.plainWords(roles))"
        case .gradient: return "gradient"
        case .textStyle: return "text"
        case .effectStyle(let kind): return kind.title.lowercased()
        }
    }

    /// The whole menu row: the name first, because that is what somebody is
    /// looking for, and where it comes from after it in brackets.
    public var label: String { "\(name) (\(origin))" }

    /// What this colour is kept for, in plain words, when it is a saved colour
    /// that is kept for other parts. Nil for every other kind, which is not
    /// kept for anything: a border's colour is simply a border's colour.
    ///
    /// This is the sentence a drag says too, so the menu and the swatch under
    /// a drag give the same reason rather than two different ones.
    public var keptFor: String? {
        guard case .keptForOtherParts(let roles) = source else { return nil }
        return BorrowedColor.plainWords(roles)
    }

    /// Whether this is a saved COLOUR, which is the only kind whose reach the
    /// Library can widen. Nobody can tick a border into being a fill colour, so
    /// a list holding only borrowed effect colours has nowhere to send anybody.
    public var isSavedColor: Bool {
        switch source {
        case .keptForOtherParts, .gradient: return true
        case .textStyle, .effectStyle: return false
        }
    }

    /// "fills and backgrounds", "outlines and text", or both joined — the words
    /// the Library's own tick boxes use, lowercased to sit inside a sentence.
    public static func plainWords(_ roles: [ColorStyleRole]) -> String {
        let kept = ColorStyleRole.allCases.filter { roles.contains($0) }
        let words = (kept.isEmpty ? ColorStyleRole.allCases : kept).map { $0.title.lowercased() }
        return ListWords.and(words)
    }
}

// MARK: - What one row can borrow

extension PhotonzDocument {

    /// Every colour in the document a row could paint with that is not already
    /// on its short list of names, each saying where it came from.
    ///
    /// The order is the order somebody would look in: saved colours first,
    /// because those ARE colours and being on this list rather than the one
    /// above is the surprise worth answering first; then the ways of setting
    /// text; then the saved effects.
    ///
    /// A colour already reachable on this row is never repeated: not the ones
    /// the row wears as names, and not a second style that happens to hold the
    /// same colour. The point of the list is reaching a colour, and the same
    /// colour twice is a longer menu that can do no more than a shorter one.
    public func borrowedColors(for slot: ColorSlot) -> [BorrowedColor] {
        var seen = colorStyles(for: slot).map { $0.paint(for: slot) }
        var borrowed: [BorrowedColor] = []

        func take(_ id: UUID, _ name: String, _ paint: Paint?, _ source: BorrowedColor.Source) {
            guard let paint else { return }
            let landing = slot.acceptsGradient ? paint : Paint(hex: paint.hex)
            guard !seen.contains(where: { $0.draws(sameAs: landing) }) else { return }
            seen.append(landing)
            borrowed.append(BorrowedColor(id: id, name: name, paint: landing, source: source))
        }

        for style in colorStyles {
            let roles = effectiveColorStyleRoles(id: style.id)
            if !roles.contains(slot.styleRole) {
                take(style.id, style.name, style.paint, .keptForOtherParts(roles))
            } else if style.isGradient, !slot.acceptsGradient {
                take(style.id, style.name, style.paint, .gradient)
            }
        }
        for style in textStyles {
            take(style.id, style.name, Paint(hex: style.treatment.colorHex), .textStyle)
        }
        for style in effectStyles {
            let paint = style.effect.border?.paint
                ?? style.effect.colorHex.map { Paint(hex: $0) }
            take(style.id, style.name, paint, .effectStyle(style.kind))
        }
        return borrowed
    }

    /// The colour behind one entry in that list, ready to paint this row with.
    /// Nil once the style behind it has gone, which is what a menu left open
    /// across an undo is holding.
    public func borrowedColor(id: UUID, for slot: ColorSlot) -> BorrowedColor? {
        borrowedColors(for: slot).first { $0.id == id }
    }
}

// MARK: - Joining words

/// "a", "a and b", "a, b and c". One place, because a list read out in a
/// sentence is a thing several sentences in the app now do.
enum ListWords {
    static func and(_ words: [String]) -> String {
        guard let last = words.last else { return "" }
        guard words.count > 1 else { return last }
        return words.dropLast().joined(separator: ", ") + " and " + last
    }
}

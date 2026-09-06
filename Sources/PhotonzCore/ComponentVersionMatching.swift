import CoreGraphics
import Foundation

/// One edit reaching every version of a component
/// (`docs/design/ui-building.md`, "A component holds more than one version").
///
/// A version is a whole drawing rather than a list of differences, which is
/// what the user chose on 2026-09-05, and the cost accepted with that choice
/// was that a change meant for all of them has to be made in each one. A new
/// corner radius on a button has to be typed three times; the third time it
/// gets typed wrong, and the versions drift apart again.
///
/// This is the sanded-down version of that cost, and it is deliberately the
/// SMALL answer rather than the big one:
///
/// - Not a mode you enter to edit every version together. A mode you have to
///   enter is a mode you forget you are in, and it would fight the whole point
///   of versions, which is that they may differ anywhere at all.
/// - Not "make the other versions match this one" over the whole drawing. That
///   deletes exactly the divergence versions exist to hold.
///
/// Instead: you edit ONE PIECE in the drawing you are looking at, the ordinary
/// way, with the ordinary tools. Then one command gives the same piece in every
/// other version this piece's LOOK and WORDING. Where each piece sits, how big
/// it is, and what is inside it are left alone, so a version that is arranged
/// differently, or has a part the others do not, comes through untouched.
///
/// It is one undoable step for every version it reaches, because it goes
/// through `History.perform` like everything else — and the copies of each
/// version it touched are put back in step inside that same step.

// MARK: - What it would do to one version

/// The piece one other version would have changed, and whether it would
/// actually change.
public struct ComponentVersionPieceMatch: Hashable, Sendable {
    /// The version holding it.
    public var version: ComponentVersion
    /// The piece inside that version this one lines up with.
    public var layerID: UUID
    /// False when that piece already looks and reads exactly like the source,
    /// which is what keeps a version out of the menu title it would not change.
    public var wouldChange: Bool

    public init(version: ComponentVersion, layerID: UUID, wouldChange: Bool) {
        self.version = version
        self.layerID = layerID
        self.wouldChange = wouldChange
    }
}

/// The whole of what "apply to other versions" would do, worked out BEFORE it
/// runs so the row that offers it can say so.
///
/// Acceptance for this feature was that it is clear before it runs which
/// versions it would change, and that is why this exists as a value rather than
/// living inside the mutation: the menu title, the tooltip and the pill
/// afterwards are all read off the same one answer.
public struct ComponentVersionApply: Hashable, Sendable {
    public var componentID: UUID
    /// The version whose piece is being copied FROM: the drawing you are on.
    public var sourceVersion: ComponentVersion
    /// The piece you have selected.
    public var sourceLayer: UUID
    /// What that piece is called, which is the noun every sentence here uses.
    public var pieceName: String
    /// Every other version that has a piece lining up with it.
    public var matches: [ComponentVersionPieceMatch]
    /// Every other version that does not, or whose matching piece is locked.
    /// Named out loud rather than quietly missed.
    public var skipped: [ComponentVersion]

    public init(componentID: UUID, sourceVersion: ComponentVersion, sourceLayer: UUID,
                pieceName: String, matches: [ComponentVersionPieceMatch],
                skipped: [ComponentVersion]) {
        self.componentID = componentID
        self.sourceVersion = sourceVersion
        self.sourceLayer = sourceLayer
        self.pieceName = pieceName
        self.matches = matches
        self.skipped = skipped
    }

    /// The versions that would actually come out different.
    public var changing: [ComponentVersionPieceMatch] { matches.filter(\.wouldChange) }

    /// Whether the piece is the DRAWING ITSELF rather than something inside it.
    /// Then only the drawing's own surface travels, and saying "Button already
    /// matches" would be a lie about the whole thing when it is only true of
    /// its surface — so the sentence changes with it.
    public var isWholeDrawing: Bool { sourceLayer == sourceVersion.layerID }

    /// Whether pressing it would do anything at all.
    public var wouldChangeAnything: Bool { !changing.isEmpty }

    /// What the row says. It NAMES the versions it would change while there are
    /// few enough to name, because "which ones is this about to touch" is the
    /// question somebody asks with their hand on the menu.
    public var title: String {
        let names = changing.map(\.version.name)
        switch names.count {
        case 0:
            // Dimmed, and saying why it is dimmed. A dead row with no reason on
            // it is a row people hunt the reason for.
            return skipped.isEmpty ? "Other Versions Already Match" : "No Other Version Has This Part"
        case 1: return "Apply to \(names[0])"
        case 2: return "Apply to \(names[0]) and \(names[1])"
        default: return "Apply to \(names.count) Other Versions"
        }
    }

    /// The sentence under the pointer: what travels, what does not, and what
    /// got left out.
    public var help: String {
        var lines: [String] = []
        let names = changing.map(\.version.name)
        if isWholeDrawing {
            lines.append(names.isEmpty
                ? "This drawing's own surface already matches every other version. The pieces inside are carried across one at a time, by selecting one."
                : "Gives \(ComponentVersionApply.list(names)) this drawing's own surface: its colour, rounding, border, shadow and fade. The pieces inside each version are left alone, and are carried across one at a time.")
        } else if names.isEmpty {
            lines.append(skipped.isEmpty
                ? "\(pieceName) already looks and reads the same in every other version."
                : "No other version has a \(pieceName) this could reach.")
        } else {
            lines.append("Gives \(pieceName) in \(ComponentVersionApply.list(names)) this one's look and wording. Where it sits, how big it is and what is inside it are left alone.")
        }
        if !skipped.isEmpty {
            let left = skipped.map(\.name)
            lines.append(left.count == 1
                ? "\(left[0]) has no \(pieceName) to change."
                : "\(ComponentVersionApply.list(left)) have no \(pieceName) to change.")
        }
        return lines.joined(separator: " ")
    }

    /// "Hover", "Hover and Disabled", "Hover, Disabled and Pressed".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}

// MARK: - The look and the wording, and nothing else

extension Layer {

    /// This layer wearing another's look and wording: its colours, its
    /// rounding, its border, its shadow, its fade, the saved colours it points
    /// at, and — when both are text — the words themselves.
    ///
    /// What deliberately does NOT come across:
    ///
    /// - **where it sits**, so a version that arranges its pieces differently
    ///   keeps its arrangement;
    /// - **how big it is**, except for text, whose box IS its wording: the same
    ///   words in the same type need the same room, and leaving the old box
    ///   would clip them;
    /// - **what is inside it**, so a version with an extra part keeps it. A
    ///   change to something inside is applied by selecting that thing;
    /// - **whether it is hidden or locked**, which is a fact about this drawing
    ///   and not about the look.
    func wearingTheLookAndWording(of source: Layer) -> Layer {
        var out = self
        out.style = source.style
        out.colorStyleBindings = source.colorStyleBindings
        switch (source.content, content) {
        case (.text(let words), .text):
            out.content = .text(words)
            out.frame.size = source.frame.size
        case (.annotation(let from), .annotation(var to)):
            // Paint and rounding, not the shape and not the two points it is
            // drawn between: those are the drawing, not the look.
            to.strokeWidth = from.strokeWidth
            to.paint = from.paint
            to.cornerRadius = from.cornerRadius
            to.fill = from.fill
            to.arrowheadScale = from.arrowheadScale
            to.caption = from.caption
            to.captionFontSize = from.captionFontSize
            out.content = .annotation(to)
        case (.group(let from), .group(var to)):
            // A group's own surface colour. Its children, its knobs, its
            // layout and which component it is are all untouched.
            to.background = from.background
            out.content = .group(to)
        default:
            break
        }
        return out
    }
}

// MARK: - Working out what it would reach

extension PhotonzDocument {

    /// The version drawing a layer belongs to: itself when it IS one, and the
    /// nearest original above it otherwise. Nil when the layer is not part of
    /// an original at all, and nil when a COPY sits in between — a copy's
    /// contents are rebuilt from its own original, so an edit written into one
    /// has nowhere to live and nothing to push.
    func componentVersionRoot(of layerID: UUID) -> Layer? {
        guard let layer = layer(id: layerID) else { return nil }
        if layer.isMainComponent { return layer }
        var current = parentID(of: layerID)
        while let id = current, let above = self.layer(id: id) {
            if above.instanceOf != nil { return nil }
            if above.isMainComponent { return above }
            current = parentID(of: id)
        }
        return nil
    }

    /// What "apply to other versions" would do from this piece, or nil when it
    /// does not apply here at all: the layer is not part of an original, or its
    /// component has only the one version.
    ///
    /// A component with one version answers nil rather than an empty plan, so
    /// nothing has to show a row that could never mean anything.
    public func componentVersionApply(from layerID: UUID) -> ComponentVersionApply? {
        guard let root = componentVersionRoot(of: layerID),
              let componentID = root.componentID,
              let piece = layer(id: layerID) else { return nil }
        let versions = componentVersions(of: componentID)
        guard versions.count > 1,
              let source = versions.first(where: { $0.layerID == root.id }) else { return nil }

        var matches: [ComponentVersionPieceMatch] = []
        var skipped: [ComponentVersion] = []
        for version in versions where version.id != source.id {
            guard let target = layer(id: version.layerID),
                  let counterpart = counterpartPiece(of: layerID, under: root, in: target),
                  let existing = layer(id: counterpart), !existing.isLocked
            else {
                skipped.append(version)
                continue
            }
            matches.append(ComponentVersionPieceMatch(
                version: version, layerID: counterpart,
                wouldChange: existing.wearingTheLookAndWording(of: piece) != existing))
        }
        return ComponentVersionApply(componentID: componentID, sourceVersion: source,
                                     sourceLayer: layerID, pieceName: piece.name,
                                     matches: matches, skipped: skipped)
    }

    /// Whether the command would do anything from this layer.
    public func canApplyToOtherComponentVersions(from layerID: UUID) -> Bool {
        componentVersionApply(from: layerID)?.wouldChangeAnything ?? false
    }

    /// The piece in `target` that lines up with `piece` in `root`, or nil when
    /// that version has nothing standing in the same place.
    ///
    /// Three ways of asking, strongest first:
    ///
    /// 1. **A knob.** A new version is made by duplicating an old one and the
    ///    duplicate KEEPS THE KNOB IDS, pointed at its own layers, so a piece
    ///    somebody made adjustable carries an exact handle across every version
    ///    however the drawings are later rearranged.
    /// 2. **Its place inside the drawing, when the thing standing there is
    ///    called the same.** Versions start out identical, so the same position
    ///    is the same piece — but only while the name agrees. Position alone
    ///    would hand a version that grew an extra part at the front the wrong
    ///    piece every time, and repaint a glow with a button's colour.
    /// 3. **Its name**, and only when exactly one piece over there wears it.
    ///    Two layers called "Label" is a guess, and a guess that silently
    ///    repaints the wrong one is worse than skipping the version.
    ///
    /// When none of the three answers, the version is skipped and SAID to be
    /// skipped. Nothing here ever settles for a piece it is not sure about.
    func counterpartPiece(of piece: UUID, under root: Layer, in target: Layer) -> UUID? {
        if let knob = root.componentProperties.first(where: { $0.target == piece }),
           let mirrored = target.componentProperties.first(where: { $0.id == knob.id })?.target,
           target.selfAndDescendants.contains(where: { $0.id == mirrored }) {
            return mirrored
        }
        guard let name = layer(id: piece)?.name else { return nil }
        if let rootPath = path(of: root.id), let piecePath = path(of: piece),
           piecePath.count >= rootPath.count, Array(piecePath.prefix(rootPath.count)) == rootPath,
           let targetPath = path(of: target.id),
           let found = layer(atPath: targetPath + Array(piecePath.dropFirst(rootPath.count))),
           found.name == name {
            return found.id
        }
        let sameName = target.selfAndDescendants.filter { $0.name == name }
        return sameName.count == 1 ? sameName[0].id : nil
    }

    // MARK: - Doing it

    /// Gives the same piece in every other version this piece's look and
    /// wording, and answers what it reached. Nil when there was nothing to do,
    /// so a caller can tell "it worked" from "there was nothing here".
    ///
    /// One call, so one undo step, however many versions it touched — and every
    /// copy of every version it touched follows inside the same step, because
    /// `History.perform` puts the copies back in step after the mutation.
    @discardableResult
    public mutating func applyToOtherComponentVersions(from layerID: UUID) -> ComponentVersionApply? {
        guard let plan = componentVersionApply(from: layerID), plan.wouldChangeAnything,
              let piece = layer(id: layerID) else { return nil }
        for match in plan.changing {
            updateLayer(id: match.layerID) { layer in
                layer = layer.wearingTheLookAndWording(of: piece)
            }
        }
        return plan
    }
}

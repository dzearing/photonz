import Foundation

/// The notice pill (Next): the glass pill at the bottom of the canvas that
/// answers Copy as Spec List, Copy Measurement and Copy Image, and that says
/// how many copies of a component followed an edit of its original.
///
/// Nothing else on screen changes when text lands on the clipboard, so without
/// it a person cannot tell whether the key was taken. It is a glance, not a
/// banner: the verdict in its own weight, one line saying what was copied,
/// and it fades on its own after `lifetime`. It shares the canvas-bottom slot
/// with the Measure mode hint (`MeasureModeHint`) so two pills never stack.
///
/// Session chrome only: it never enters the document or the undo history.
public struct CopyConfirmation: Hashable, Sendable {
    /// What landed on the clipboard, so the line reads differently for a
    /// whole list and for one row. Counts are what the text carries: the
    /// spec list lists visible measurements only, and a list whose rows are
    /// all hidden still copies its header.
    public enum Subject: Hashable, Sendable {
        case specList(measurements: Int)
        case measurements(count: Int)
        /// Copy Image: the picture, plus the spec list when `measurements`
        /// is above zero (`CompositeCopy`).
        case image(measurements: Int)
        /// Copies of a component followed an edit of their original
        /// (`docs/design/ui-building.md`, step C5). Nothing else on screen says
        /// how far an edit reached: the pieces that moved are somewhere else on
        /// the canvas, often off it, so without this you edit one thing and
        /// have no idea what else you changed. `component` names the original
        /// when exactly one was involved.
        case componentInstances(count: Int, component: String?)
        /// A copy of a component was NOT placed, because it would have put a
        /// component inside itself.
        case componentCycle
        /// A copy stopped following its original (`docs/design/ui-building.md`,
        /// step C6). Detaching changes nothing you can see — the picture is
        /// identical the instant after — so without a word on screen the
        /// command looks like it did nothing at all. `component` names the
        /// original it used to follow.
        case componentDetached(component: String?, count: Int)
        /// Layers became a set of alternatives with a knob that picks between
        /// them (`docs/design/ui-building.md`, the C6 follow-up). Settling the
        /// choice HIDES all but one of the shapes that were just selected, so
        /// without a word on screen it reads as the app having deleted one.
        case componentChoiceMade(options: Int, knob: String)
        /// An edit inside a copy was refused (`ComponentPieceRefusal`). A
        /// piece of a copy comes from the original, so typing over one has
        /// nowhere to land unless the original made it adjustable. Without a
        /// word on screen the double click simply does nothing, which reads as
        /// the app being broken.
        case componentPieceRefused(ComponentPieceRefusal)
        /// A copy was showing a version of its component that has just been
        /// deleted, so it was put back on one the component still has
        /// (`ComponentVersions`). Nothing else on screen says so: the copy
        /// simply draws something else the next time you look at it.
        case componentVersionGone(count: Int, version: String?)
        /// One piece's look and wording was pushed onto the same piece in
        /// every other version of its component
        /// (`ComponentVersionMatching`). The versions it reached are drawings
        /// somewhere else on the canvas, usually scrolled off it, so without a
        /// word on screen the command looks like it did nothing at all.
        case componentVersionsMatched(piece: String, versions: [String])
        /// Something stopped following what it came from: a color let go of a
        /// named style, a part of a copy's look was set by hand, a copy was
        /// ungrouped, or an original was deleted out from under its copies
        /// (`LinkBreakReport`). All four say it in one frame, because to the
        /// person they are one thing that just happened.
        case linksBroken(LinkBreakReport)
        /// The saved colour a TOOL was holding could not come with it
        /// (`ToolColorStyleNotice`): a plain colour was picked underneath it,
        /// or it drew in a document that has never heard of the name. Neither
        /// changes anything you can see at the moment it happens, and both
        /// change what the NEXT shape comes out.
        case toolColorStyle(ToolColorStyleNotice)
    }

    /// How long the pill stays up before fading. Enough to catch, short enough
    /// that a fluent user is never waiting for it to leave.
    public static let lifetime: TimeInterval = 1.6

    /// How long a broken link stays up. Longer, because it is the only one of
    /// these you might want to act on: it is a whole sentence naming two
    /// things, and 1.6 seconds is under the time it takes to read one and
    /// decide whether to press Command Z.
    public static let breakLifetime: TimeInterval = 3.0

    public var subject: Subject
    public var shownAt: Date

    public init(subject: Subject, shownAt: Date) {
        self.subject = subject
        self.shownAt = shownAt
    }

    /// How long THIS pill stays up, which depends on how much it is asking of
    /// the person reading it.
    public var lifetime: TimeInterval {
        switch subject {
        // These are the ones you might want to ACT on, and 1.6 seconds is
        // under the time it takes to read a sentence naming two things and
        // decide what to do about it.
        case .linksBroken, .componentPieceRefused, .toolColorStyle,
             .componentVersionGone, .componentVersionsMatched: return Self.breakLifetime
        default: return Self.lifetime
        }
    }

    /// Whether the pill should still be on screen at `now`. Strictly inside the
    /// window, so a clock that runs backwards cannot pin it up forever.
    public func isLive(at now: Date) -> Bool {
        let age = now.timeIntervalSince(shownAt)
        return age >= 0 && age < lifetime
    }

    /// The same pill, re-shown for a new copy with its clock restarted. Two
    /// quick copies keep one pill up that fades from the last one.
    public func reshown(as subject: Subject, at now: Date) -> CopyConfirmation {
        CopyConfirmation(subject: subject, shownAt: now)
    }

    /// The verdict, set in its own weight at the head of the pill.
    public var title: String {
        switch subject {
        case .specList, .measurements, .image: return "Copied"
        case .componentInstances: return "Updated"
        case .componentCycle: return "Not placed"
        case .componentDetached: return "Detached"
        case .componentChoiceMade: return "Choice added"
        case .componentVersionGone: return "Version deleted"
        case .componentVersionsMatched: return "Applied"
        case .componentPieceRefused(let refusal): return refusal.title
        case .linksBroken(let report): return report.title
        case .toolColorStyle(let notice): return notice.title
        }
    }

    /// What was copied, in plain words.
    public var detail: String {
        switch subject {
        case .specList(let count):
            return "Spec list with \(count == 0 ? "no visible measurements" : Self.measurementPhrase(count))"
        case .measurements(let count):
            return Self.measurementPhrase(count)
        case .image(let count):
            return count == 0 ? "Image" : "Image and spec list with \(Self.measurementPhrase(count))"
        case .componentInstances(let count, let component):
            let copies = count == 1 ? "1 copy" : "\(count) copies"
            guard let component, !component.isEmpty else { return copies }
            return "\(copies) of \(component)"
        case .componentCycle:
            return "A component cannot hold a copy of itself"
        case .componentDetached(let component, let count):
            let one = count == 1
            guard let component, !component.isEmpty else {
                return one ? "It no longer follows its original"
                           : "\(count) copies no longer follow their original"
            }
            return one ? "It no longer follows \(component)"
                       : "\(count) copies no longer follow \(component)"
        case .componentChoiceMade(let options, let knob):
            return "1 of \(options) shapes shows. Copies pick it with \(knob)"
        case .componentVersionGone(let count, let version):
            let copies = count == 1 ? "1 copy" : "\(count) copies"
            guard let version, !version.isEmpty else { return "\(copies) moved to another version" }
            return "\(copies) moved to \(version)"
        case .componentVersionsMatched(let piece, let versions):
            guard !versions.isEmpty else { return piece }
            return "\(piece) now matches in \(ComponentVersionApply.list(versions))"
        case .componentPieceRefused(let refusal):
            return refusal.detail
        case .linksBroken(let report):
            return report.detail ?? ""
        case .toolColorStyle(let notice):
            return notice.detail
        }
    }

    /// "1 measurement" / "N measurements".
    private static func measurementPhrase(_ count: Int) -> String {
        count == 1 ? "1 measurement" : "\(count) measurements"
    }
}

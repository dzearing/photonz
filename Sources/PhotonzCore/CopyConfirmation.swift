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
        /// A copy was pointed at a DIFFERENT component (`ComponentSwap`). The
        /// picture changes, so the swap itself is obvious; what is not obvious
        /// is which of the settings you had typed came with it, and a knob the
        /// new component does not offer is gone until you undo. So the line
        /// names them rather than leaving you to find out later.
        case componentSwapped(component: String?, count: Int, dropped: [String],
                              droppedOwnType: Bool)
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
        /// The FIRST drag of a component off the shelf, which puts TWO
        /// drawings on the canvas: the copy you let go of, and the original it
        /// follows, standing clear of the drop
        /// (`FirstDropIsAnInstanceTests`). Without a word on screen that reads
        /// as the app having dropped the same thing twice, and the difference
        /// between the two is a small mark on a name chip. `component` names
        /// the original.
        case componentOriginalArrived(component: String?)
        /// A component was given another version (`ComponentVersions`).
        /// Adding one puts a WHOLE SECOND DRAWING on the canvas, which is the
        /// part the command does not look like it did: without a word on
        /// screen a person sees the menu close and nothing else, and the new
        /// drawing is just something that turned up next to their work.
        case componentVersionAdded(version: String, component: String?,
                                   property: String = ComponentNaming.defaultVariantPropertyName)
        /// A copy was showing a version of its component that has just been
        /// deleted, so it was put back on one the component still has
        /// (`ComponentVersions`). Nothing else on screen says so: the copy
        /// simply draws something else the next time you look at it.
        case componentVersionGone(count: Int, version: String?,
                                  property: String = ComponentNaming.defaultVariantPropertyName)
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
        /// A marquee could not take a piece out of the layer you picked
        /// (`RegionSliceRefusal`), because that layer is a shape, a piece of
        /// text, or a picture that has been cropped or turned. Both keys used
        /// to answer this by lying: cut took the whole layer, and delete did
        /// nothing at all. This is the line that says which it was.
        case regionSliceRefused(RegionSliceRefusal)
        /// A picture was taken apart by Separate into Layers. The canvas looks
        /// IDENTICAL the instant after — nothing moves, the words are simply on
        /// their own layers now — so without a word on screen the command reads
        /// as having done nothing at all.
        ///
        /// The two counts of what stayed behind are two different sentences and
        /// must not be merged into one. `skipped` is what the app could not
        /// read confidently and will never take, which is the half of the
        /// command nobody would otherwise find out about. `crowded` is what it
        /// read perfectly well and left because one command only takes so much
        /// (`SeparateBudget`) — and the thing to do about those is run the
        /// command again.
        case separatedIntoLayers(runs: Int, boxes: Int, skipped: Int, crowded: Int = 0)
        /// A separated run of text was turned back into WORDS, or was not
        /// (`TextReading`). Both halves need saying. On the way in, the canvas
        /// looks identical the instant after and the only visible change is in
        /// the layers list, so the pill is what tells you the words are yours
        /// now and what face they came out in. On the way out, a refusal a
        /// person cannot account for reads as the app being broken: a run that
        /// stays a picture has to say WHY, and every reason here is a sentence
        /// they can do something about.
        case turnedIntoText(TextReading.Outcome)
        /// EVERY run in a separated picture was read in one press
        /// (`TextReading.Batch`, `next-read-every-label`). The singular line
        /// above names one label and the face it came out in, which says
        /// nothing useful about forty of them and would be forty pills raised
        /// over each other. This one counts them, names the family the page was
        /// held to once, and says how many stayed pictures.
        case turnedIntoTextInBatch(TextReading.Batch)
        /// The same reading, while it is still going. Reading a dense page is
        /// about two seconds and the press takes the pill that started it off
        /// screen, so without this the button looks like it did nothing at all.
        case readingTheWords(labels: Int)
        /// ⇧⌘J: a piece is now on a layer of its own and the space it came
        /// from has been filled in.
        ///
        /// Raised ONLY when the fill was not read off the picture. A cut whose
        /// surroundings agreed changed the canvas in front of the person who
        /// asked for it, and a pill saying so is nagging. A fill the app could
        /// not justify is the opposite: it looks exactly like a repair, and
        /// nobody can tell the two apart without being told.
        case cutToOwnLayer(PatchHeal)
        /// The look of one layer was picked up, ready to be put on another
        /// (`LayerLook.swift`). NOTHING on screen changes when a look is
        /// copied — the layer it came off is untouched — so without a word
        /// there is no way to tell the key was taken, which is the same reason
        /// Copy as Spec List has a pill.
        case lookCopied(layer: String)
        /// A look was put on some layers. It says how far it reached and what
        /// did not fit, because a look is best effort by design: a result that
        /// is not quite a match has to be explained rather than mysterious.
        case lookPasted(LookPaste)
        /// Two or more shapes became one (`PathCombining.swift`). It carries
        /// the two things the canvas cannot show: WHICH shape's look the
        /// result is wearing, since two overlapping circles of the same colour
        /// say nothing about which was underneath, and whether the result has a
        /// hole in it or came apart into pieces. It is also the only place a
        /// combination that came to NOTHING can say why, and that is the case
        /// it exists for: without it, Keep Overlap on two shapes that do not
        /// touch is a menu item that does nothing at all.
        case shapesCombined(PathCombinePlan)
        /// A clip's sound was taken off its picture (`SoundClip.swift`). The
        /// canvas does not change at all when it happens — the picture is
        /// identical the instant after — so without a word on screen the
        /// command reads as having done nothing.
        case soundDetached(clip: String)
        /// A sound was brought in from a file and put on the timeline. It
        /// draws nothing on the canvas, so the same reason applies twice over:
        /// the only place it shows up is the timeline and the layers list.
        case soundAdded(name: String)
        /// A recording was let go on a document that runs in time and landed
        /// as a clip over it (`MediaDrop`). It DOES draw on the canvas, unlike
        /// a piece of sound, but it lands at the playhead and the playhead is
        /// rarely where a person just let go, so without a word a clip that
        /// arrives somewhere else in time reads as a drop that did nothing.
        case clipAdded(name: String)
        /// ⌘T put nothing on (`DefaultTransition.swift`). A key that does
        /// nothing reads as a key that is broken, so it says why.
        case defaultTransitionRefused(DefaultTransitionRefusal)
        /// A tile was made the one ⌘T puts on a cut. Nothing on the canvas
        /// changes when it is, so without a word it reads as a menu row that
        /// did nothing.
        case defaultTransitionSet(ClipTransitionKind)
        /// A sound or a recording let go on the TIMELINE landed on a track at
        /// the moment it was let go at (`ClipLanding`), which is not the
        /// playhead, so the words say where.
        case landedOnTrack(name: String, track: String, atMS: Int, isSound: Bool)
        /// A sound or a recording was let go and could not be taken after all:
        /// the file has nothing playable in it, or it went away between the
        /// drag and the drop. The drag promised this would land, so the app
        /// owes an explanation rather than silence.
        case mediaWouldNotOpen(name: String)
        /// Recordings or sounds went into the Library and nowhere else
        /// (`LibraryImport`). The shelf may be scrolled or folded, and nothing
        /// on the canvas or the timeline moves, so without a word an Import
        /// reads as a menu row that did nothing.
        case broughtIntoLibrary(LibraryImport)
        /// The mix was written out as one sound file, or could not be.
        case mixWritten(file: String?)
        /// The mix was written, and it had to be held down to fit in a file
        /// (`AudioHeadroom`). Its own case rather than a quieter `mixWritten`
        /// because the level on disk is not the level in the room, and a person
        /// who is not told that spends the next ten minutes wondering why the
        /// file sounds quieter than the timeline did.
        case mixHeldDown(file: String, byDB: Double)
        /// The app listened to the recording and wrote the captions
        /// (`Captions.swift`). The words land in the title-safe band at the
        /// bottom of the picture and on the timeline, and on a long recording
        /// the playhead is usually nowhere near the first of them, so without a
        /// word on screen a minute of listening ends in what looks like
        /// nothing happening.
        case captionsWritten(words: Int, cues: Int, ofMS: Int)
        /// ...and where it heard nothing, or was stopped part way, or there
        /// was nothing to listen to. One case for all three because they are
        /// the same sentence to the person reading it: here is what you got.
        case captionsCameTo(String)
        /// The captions were written out as a subtitle file, or could not be.
        case captionsFileWritten(file: String?)
        /// The document was written out as a video, or could not be
        /// (`EditorState+VideoExport`). The window looks identical the instant
        /// after, so without a word there is nothing to say a file landed.
        case videoWritten(file: String?)
        /// One frame of it was written out as a picture, or could not be. Its
        /// own words rather than the video's: a pill saying "Video written"
        /// over a PNG of one frame is a pill nobody believes.
        case frameWritten(file: String?)
    }

    /// How long the pill stays up before fading. Enough to catch, short enough
    /// that a fluent user is never waiting for it to leave.
    public static let lifetime: TimeInterval = 1.6

    /// How long a broken link stays up. Longer, because it is the only one of
    /// these you might want to act on: it is a whole sentence naming two
    /// things, and 1.6 seconds is under the time it takes to read one and
    /// decide whether to press Command Z.
    public static let breakLifetime: TimeInterval = 3.0

    /// How long a notice that carries a BUTTON stays up (`CanvasNoticeAction`).
    /// Longest of the three, because it is the only one you are asked to reach
    /// for: three seconds is enough to read a refusal and not enough to read
    /// it, decide, and travel to a control. A button that leaves while you are
    /// reaching for it teaches you that the app takes things away.
    public static let actionLifetime: TimeInterval = 6.0

    /// The longest a notice can be held on screen by a pointer resting on it,
    /// counted from the moment it went up.
    ///
    /// Resting on a pill stops its clock so it cannot leave while somebody is
    /// reaching for it, but "the pointer is over it" and "the pointer happens
    /// to be parked where it appeared" look identical from the inside, and a
    /// notice has no close control. Without a ceiling, a pill that turns up
    /// under a hand that never moves again stays up for good — which a walk
    /// caught doing exactly that on 2026-09-08. Twice the action clock is more
    /// than enough for anyone actually reading it.
    public static let heldLifetime: TimeInterval = 12.0

    /// How long a notice that is reporting WORK IN PROGRESS stays up.
    ///
    /// Not a glance and not an offer: it is the app saying it is busy, and it
    /// has to still be there when the answer lands, however dense the picture
    /// was. The reading that raises it is two seconds on the densest capture
    /// measured, so thirty is far more room than it can need — and it is a
    /// ceiling rather than no clock at all, because nothing on screen may live
    /// forever if the work it is describing never comes back.
    public static let workingLifetime: TimeInterval = 30.0

    public var subject: Subject
    public var shownAt: Date
    /// The one thing this notice offers you to press, when it has one. Nil for
    /// every notice but a refusal that knows its own way out, so the pill stays
    /// inert and click-through in every other case.
    public var action: CanvasNoticeAction?

    public init(subject: Subject, shownAt: Date, action: CanvasNoticeAction? = nil) {
        self.subject = subject
        self.shownAt = shownAt
        self.action = action
    }

    /// How long THIS pill stays up, which depends on how much it is asking of
    /// the person reading it.
    public var lifetime: TimeInterval {
        // A pill you are meant to press outranks both: see `actionLifetime`.
        if action != nil { return Self.actionLifetime }
        switch subject {
        // These are the ones you might want to ACT on, and 1.6 seconds is
        // under the time it takes to read a sentence naming two things and
        // decide what to do about it.
        case .mediaWouldNotOpen,
             .linksBroken, .componentPieceRefused, .toolColorStyle,
             .componentVersionGone, .componentVersionsMatched,
             .componentVersionAdded, .regionSliceRefused,
             .separatedIntoLayers, .turnedIntoText, .turnedIntoTextInBatch,
             .lookPasted, .shapesCombined: return Self.breakLifetime
        // ...and a swap is one of them exactly when it left something behind:
        // "Title did not carry over" is a sentence naming a thing you may want
        // to press Command Z about, and the swap that carried everything is
        // just a confirmation you glance at.
        case .componentSwapped(_, _, let dropped, let droppedOwnType):
            return dropped.isEmpty && !droppedOwnType ? Self.lifetime : Self.breakLifetime
        // Something that would not open is a sentence worth reading.
        case .broughtIntoLibrary(let outcome):
            return outcome.unreadable.isEmpty ? Self.lifetime : Self.breakLifetime
        // Still working: it waits for its own answer (see `workingLifetime`).
        case .readingTheWords: return Self.workingLifetime
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
    /// The new notice's own action is what it carries: a plain notice landing
    /// on top of a refusal must take the button away rather than inherit it.
    public func reshown(as subject: Subject, at now: Date,
                        action: CanvasNoticeAction? = nil) -> CopyConfirmation {
        CopyConfirmation(subject: subject, shownAt: now, action: action)
    }

    /// The verdict, set in its own weight at the head of the pill.
    public var title: String {
        switch subject {
        case .soundDetached: return "Sound taken off"
        case .soundAdded: return "Sound added"
        case .clipAdded: return "Clip added"
        case .defaultTransitionRefused: return "No transition added"
        case .defaultTransitionSet: return "Default transition"
        case .landedOnTrack(_, _, _, let isSound): return isSound ? "Sound added" : "Clip added"
        case .mediaWouldNotOpen: return "Not added"
        case .broughtIntoLibrary(let outcome): return outcome.title
        case .mixWritten(let file): return file == nil ? "Not written" : "Mix written"
        case .mixHeldDown: return "Mix written, held down"
        case .captionsWritten: return "Captions written"
        case .captionsCameTo: return "Captions"
        case .captionsFileWritten(let file): return file == nil ? "Not written" : "Captions written"
        case .videoWritten(let file): return file == nil ? "Not written" : "Video written"
        case .frameWritten(let file): return file == nil ? "Not written" : "Frame written"
        case .specList, .measurements, .image: return "Copied"
        case .componentInstances: return "Updated"
        case .componentCycle: return "Not placed"
        case .componentDetached: return "Detached"
        case .componentSwapped: return "Swapped"
        case .componentChoiceMade: return "Choice added"
        case .componentOriginalArrived: return "Copy placed"
        // The author owns this word: a component whose question they called
        // State says "State added", never "Variant added"
        // (`ComponentVariantWording`).
        case .componentVersionAdded(_, _, let property):
            return "\(ComponentVariantWording(property).one) added"
        case .componentVersionGone(_, _, let property):
            return "\(ComponentVariantWording(property).one) deleted"
        case .componentVersionsMatched: return "Applied"
        case .componentPieceRefused(let refusal): return refusal.title
        case .linksBroken(let report): return report.title
        case .toolColorStyle(let notice): return notice.title
        case .regionSliceRefused(let refusal): return refusal.title
        case .separatedIntoLayers(let runs, let boxes, _, _):
            return runs + boxes == 0 ? "Nothing to separate" : "Separated"
        case .turnedIntoText(let outcome):
            return outcome.reading == nil ? "Still a picture" : "Turned into text"
        case .turnedIntoTextInBatch(let batch): return batch.title
        case .readingTheWords: return TextReading.Batch.workingTitle
        case .cutToOwnLayer:
            return "Cut to its own layer"
        case .lookCopied: return "Copied"
        case .lookPasted(let report): return report.title
        case .shapesCombined(let plan): return plan.title
        }
    }

    /// What was copied, in plain words.
    public var detail: String {
        switch subject {
        case .soundDetached(let clip):
            return "\(clip) keeps its picture. Its sound is a layer of its own now"
        case .soundAdded(let name):
            return "\(name) is on the timeline"
        case .defaultTransitionRefused(let refusal):
            return refusal.detail
        case .defaultTransitionSet(let kind):
            return "\u{2318}T now puts \(kind.title) on a cut"
        case .clipAdded(let name):
            return "\(name) is on the timeline at the playhead"
        case .landedOnTrack(let name, let track, let ms, _):
            return "\(name) is on \(track) at \(CaptionProgress.clock(ms))"
        case .mediaWouldNotOpen(let name):
            return "There is nothing in \(name) the app can play"
        case .broughtIntoLibrary(let outcome):
            return outcome.detail
        case .mixWritten(let file):
            guard let file else { return "The mix could not be written" }
            return file
        case .mixHeldDown(let file, let byDB):
            return String(format: "%@ was %.1f dB past what a file can hold, so the whole mix came down by that much",
                          file, byDB)
        case .captionsWritten(let words, let cues, let ofMS):
            return CaptionProgress.heard(words: words, cues: cues, ofMS: ofMS)
        case .captionsCameTo(let said):
            return said
        case .captionsFileWritten(let file):
            guard let file else { return "The captions could not be written" }
            return file
        case .videoWritten(let file):
            guard let file else { return "The video could not be written" }
            return file
        case .frameWritten(let file):
            guard let file else { return "The frame could not be written" }
            return file
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
        case .componentSwapped(let component, let count, let dropped, let droppedOwnType):
            let what = count == 1 ? "It follows" : "\(count) copies follow"
            let named = component.flatMap { $0.isEmpty ? nil : $0 } ?? "a different component"
            var line = "\(what) \(named) now"
            var left = dropped
            if droppedOwnType { left.append("the type it set for its own words") }
            guard !left.isEmpty else { return line }
            line += ". \(ComponentVersionApply.list(left)) did not carry over"
            return line
        case .componentChoiceMade(let options, let knob):
            return "1 of \(options) shapes shows. Copies pick it with \(knob)"
        case .componentOriginalArrived(let component):
            guard let component, !component.isEmpty else {
                return "The original arrived beside it. Editing that changes every copy"
            }
            return "The original of \(component) arrived beside it. "
                + "Editing that changes every copy"
        case .componentVersionAdded(let version, let component, _):
            guard let component, !component.isEmpty else {
                return "\(version) is now its own drawing on the canvas"
            }
            return "\(version) is now its own drawing of \(component) on the canvas"
        case .componentVersionGone(let count, let version, let property):
            let copies = count == 1 ? "1 copy" : "\(count) copies"
            guard let version, !version.isEmpty else {
                return "\(copies) moved to another \(ComponentVariantWording(property).one)"
            }
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
        case .regionSliceRefused(let refusal):
            // With a button in the pill the line must stop naming the menu:
            // two ways out in one sentence is one too many to read, and the
            // button IS the way out.
            return refusal.detail(offeringItsOwnWayOut: action != nil)
        case .separatedIntoLayers(let runs, let boxes, let skipped, let crowded):
            var parts: [String] = []
            if runs > 0 { parts.append(runs == 1 ? "1 run of text" : "\(runs) runs of text") }
            if boxes > 0 { parts.append(boxes == 1 ? "1 box" : "\(boxes) boxes") }
            guard !parts.isEmpty else {
                // Two different nothings, and saying the wrong one is a lie.
                // Running the command twice finds nothing at all, because the
                // first run took it; a photograph with a caption on it finds
                // something and cannot read it. Nothing came out here, so
                // there is no point sending anybody round again: whatever was
                // crowded out would be picked and refused the same way.
                let left = skipped + crowded
                guard left > 0, left <= Self.unreadableWorthNaming else {
                    return "Nothing here reads as text or a box"
                }
                let pieces = left == 1 ? "1 piece" : "\(left) pieces"
                return "\(pieces) left in the picture, too unclear to read"
            }
            let made = parts.joined(separator: " and ")
            // The count is EVERYTHING still in the picture, for both reasons,
            // because that is the number a person can check by looking at it.
            // What changes is what to do about it: a piece the limit crowded
            // out comes out on the next run, and one it could not read never
            // does.
            guard skipped + crowded > 0 else { return made }
            guard crowded > 0 else {
                return "\(made). \(skipped) left in the picture, too unclear to read"
            }
            return "\(made). \(skipped + crowded) left in the picture, run it again for more"
        case .turnedIntoText(let outcome):
            switch outcome {
            case .read(let reading):
                // The face is named because it is the thing that might be
                // wrong, and naming it is what lets somebody look at the label
                // and disagree. A fallback says so in the same breath: the app
                // did not identify this face, it picked the closest one it can
                // set, and that is a different promise.
                let face = reading.provenance == .matched
                    ? "set in \(reading.face.displayName)"
                    : "set in \(reading.face.displayName), the closest face to the picture"
                return "\(TextReading.layerName(for: reading.string)), \(face)"
            case .refused(let why):
                return why.sentence
            }
        case .turnedIntoTextInBatch(let batch):
            return batch.detail
        case .readingTheWords(let labels):
            return TextReading.Batch.working(labels: labels)
        case .cutToOwnLayer(let heal):
            switch heal {
            case .matched:
                return "The space it came from was filled in with the colours around it"
            case .guessed:
                // Said plainly, because it looks exactly like a repair. The
                // person asked for the cut, so the app made one rather than
                // ignoring the key, and this is the sentence that stops the
                // guess passing itself off as a reading.
                return "The colours around it did not agree, so the fill is a guess at the middle of them"
            case .cleared:
                return "There was nothing around it to read, so the space it came from is empty"
            }
        case .lookCopied(let layer):
            return layer.isEmpty ? "The look of that layer" : "The look of \(layer)"
        case .lookPasted(let report):
            return report.detail
        case .shapesCombined(let plan):
            return plan.detail
        }
    }

    /// The line as the pill DRAWS it: the part that is only read, and the part
    /// of it that can also be pressed.
    ///
    /// Every notice in the app is inert by default, and that rule is what stops
    /// a pill turning up unprompted and swallowing a click meant for the canvas
    /// underneath it. One notice opts out: the one whose line counts something
    /// a person cannot otherwise find (`CanvasNoticeAction.findStillPictures`).
    /// There, the words that count are the way to what they count, so they take
    /// the pointer and the rest of the sentence still does not.
    ///
    /// The pressable words are taken off the END of the line the notice already
    /// says, and they have to be the action's own label, so a drawn pill and a
    /// read one can never be two different sentences.
    public var line: NoticeLine {
        let whole = detail
        guard let action, action.presentation == .wordsInTheLine else {
            return NoticeLine(lead: whole, pressable: nil)
        }
        let words = action.label
        // An action whose words are not the tail of its own line has nothing to
        // press: the line stays a plain report rather than the pill inventing a
        // control that does not match what it says.
        guard whole.count > words.count, whole.hasSuffix(words) else {
            return NoticeLine(lead: whole, pressable: nil)
        }
        let lead = String(whole.dropLast(words.count))
        return NoticeLine(lead: lead.trimmingCharacters(in: .whitespaces), pressable: words)
    }

    /// How many unreadable pieces are worth counting out loud when NOTHING
    /// came out of a picture.
    ///
    /// A photograph with a caption burnt into it offers one or two things a
    /// person can see and did not get, and saying so is the whole point: they
    /// are looking straight at the caption wondering why it is still there.
    ///
    /// A photograph of a mountain is a different picture entirely. Measured on
    /// one: 437 pieces found in the grass and the rock face, none of them
    /// readable, none of them anything a person would point at. "437 pieces
    /// left in the picture" is a true sentence about texture and a useless one
    /// about the photograph — it reads as the app having failed at something,
    /// when what actually happened is that this is not a screenshot. Past a
    /// handful, the plain answer is the honest one.
    public static let unreadableWorthNaming = 5

    /// "1 measurement" / "N measurements".
    private static func measurementPhrase(_ count: Int) -> String {
        count == 1 ? "1 measurement" : "\(count) measurements"
    }
}

/// A notice's line, split where a part of it can be pressed
/// (`CopyConfirmation.line`). `pressable` is nil for every notice but the one
/// that counts something findable, and then the whole sentence is `lead`.
public struct NoticeLine: Hashable, Sendable {
    /// The part that is only ever read.
    public var lead: String
    /// The words on the end of it that are also the way to what they count.
    public var pressable: String?

    public init(lead: String, pressable: String? = nil) {
        self.lead = lead
        self.pressable = pressable
    }
}

// Pressing something in the right hand panel, for a scripted walk.
//
// A walk could only ever click the picture: every click went straight to the
// canvas view, so a point over the panel landed on the picture behind it and
// read as a click on nothing. Anything that lives in the panel could therefore
// be photographed and never used, and three audits on 2026-09-04 had to hand
// back a picture of a button instead of a press.
//
// There are two kinds of thing to press there and they are found different
// ways. A button, a link, a row that goes somewhere is drawn by SwiftUI and
// says who it is through a marker behind it (`playtestControl`), the same way
// a shelf tile or a layer row already does. A segmented picker — Free / Stack /
// Grid, Row / Column, Hug / Fixed, which is most of the Layout section — is a
// real AppKit control underneath, so its segments can be read straight off it
// and need no marker at all.
//
// Either way the press itself is real mouse events posted to the app's queue,
// never the control's action called behind its back: a button that is dimmed,
// covered or wired to nothing has to fail a walk the way it fails a person.
#if PHOTONZ_PLAYTEST
import AppKit

/// One thing in the panel a `press` step can land on.
struct PlaytestPressTarget {
    /// The words a walk names it by.
    var name: String
    /// Where it lives, for the log and for the list a `panel` step writes.
    var detail: String
    /// Where to put the pointer, in the coordinates of `window`.
    var point: CGPoint
    /// The control's own box, in the same coordinates. A press lands in its
    /// middle; `pressed(across:)` moves along this instead, which is the only
    /// way to put a slider's knob anywhere but halfway.
    var box: CGRect = .zero
    /// The part of that box a person can actually see, in the same
    /// coordinates: what is left of it after the dock's scrolling area has cut
    /// off whatever has run past its top or bottom edge.
    ///
    /// This is not the same as being inside the window. A row scrolled until
    /// only its last two points show is still inside the window, and a press
    /// aimed at its middle lands on the panel's edge and changes nothing --
    /// which is exactly how a walk came to press Corner Radius twice and
    /// report a pass both times while the radius never moved. `.infinite`
    /// means nothing is known to clip this one, so only the window bounds
    /// decide.
    var visible: CGRect = .infinite
    /// Nothing happens if this is pressed, and the walk should say so rather
    /// than reporting a pass.
    var isEnabled: Bool
    /// The window the point belongs to. Usually the editor window, but a
    /// popover — the colour picker above all — is a window of its own sitting
    /// on top of it, and a click meant for it has to be addressed to it.
    var window: NSWindow?

    /// The same target, pressed a fraction of the way along its own width.
    /// 0 is its left edge, 1 its right; a control with no box keeps its point.
    func pressed(across fraction: CGFloat) -> PlaytestPressTarget {
        guard box.width > 0 else { return self }
        var moved = self
        moved.point = CGPoint(x: box.minX + box.width * min(max(fraction, 0), 1), y: box.midY)
        return moved
    }
}

enum PlaytestPanelPress {
    /// Every segmented picker in the window, segment by segment. SwiftUI draws
    /// `.pickerStyle(.segmented)` as an `NSSegmentedControl`, so the words on
    /// each segment are readable without the panel having to name them.
    ///
    /// The words alone are not enough to say WHICH picker, though: the Layout
    /// section holds a Hug and a Fixed for Width and another pair for Height,
    /// and a walk that pressed "Fixed" would be pressing whichever came first.
    /// So a marker behind a picker lends the picker its name — "Width" — and
    /// the walk can say which row it means.
    @MainActor static func segments(in content: NSView,
                                    named fields: [PanelTargetView]) -> [PlaytestPressTarget] {
        segmentedControls(in: content).flatMap { control -> [PlaytestPressTarget] in
            let box = control.convert(control.bounds, to: nil)
            let shown = control.convert(control.visibleRect, to: nil)
            let chosen = control.selectedSegment
            let row = field(of: control, among: fields)
            let anchors = hintAnchors(in: content)
            return (0..<control.segmentCount).compactMap { index in
                guard let label = name(ofSegment: index, in: control) else { return nil }
                let point = CGPoint(x: centre(ofSegment: index, in: control, box: box), y: box.midY)
                var detail = row ?? "a picker"
                if index == chosen { detail += ", already on \(label)" }
                // What resting HERE would say. A row of pictures gets one
                // tooltip per picture, and the only way to know a name landed
                // on the picture it belongs to is to read it back at that
                // picture's own middle.
                detail += ", tooltip \(tip(at: point, among: anchors).map { "\"\($0)\"" } ?? "none")"
                return PlaytestPressTarget(
                    name: label, detail: detail,
                    point: point,
                    box: box,
                    visible: shown,
                    isEnabled: control.isEnabled && control.isEnabled(forSegment: index),
                    window: control.window)
            }
        }
    }

    /// What a walk calls one segment. A segment with words on it says them; a
    /// segment that is a PICTURE — the alignment rows are three little pictures
    /// each — has no words at all, so it was skipped and could never be pressed.
    /// Its image's accessibility description is the name a person hears for it,
    /// so that is the name a walk uses too: the alignment rows come out as
    /// "align left", "align center", "align right", which is what the system
    /// itself calls those pictures. (A SwiftUI `.accessibilityLabel` on the
    /// Image does NOT reach the segment — tried, and the symbol's own name came
    /// through instead — so a picture segment is named by its symbol.)
    @MainActor static func name(ofSegment index: Int, in control: NSSegmentedControl) -> String? {
        if let label = control.label(forSegment: index), !label.isEmpty { return label }
        if let described = control.image(forSegment: index)?.accessibilityDescription,
           !described.isEmpty { return described }
        return nil
    }

    /// The row a thing sits on: the smallest labelled row it falls inside, so
    /// a picker takes its own row's word and not the one below it.
    @MainActor static func field(of view: NSView, among fields: [PanelTargetView]) -> String? {
        Self.fields(of: view, among: fields).last
    }

    /// EVERY labelled row this sits inside, widest first, so a control says who
    /// owns it as well as what it is: `["Border 2", "Width"]`.
    ///
    /// The smallest one alone is not enough the moment a row can arrive twice.
    /// Two borders in the Effects list both hold a row called Width, and named
    /// by that word alone neither could be pressed: the walk is told two things
    /// answer to it and stops. With the owner in front, `in: "Border 2"` picks
    /// one out, exactly as `in: "Width"` picks Layout's Fixed out from
    /// Height's.
    ///
    /// A frame alone is not enough to say a row holds something, because the
    /// panel does not scroll as one piece. The Effects list scrolls INSIDE the
    /// dock, so an expanded Shadow taller than that little window keeps its
    /// whole height as a frame while only a strip of it is on screen, and the
    /// part scrolled away lies across whatever the dock shows underneath --
    /// which is how the Component section's one button came to answer as
    /// "Shadow, there is something to carry" and stopped a walk on 2026-09-07.
    /// So a row may only lend its name to something its OWN scrolling area
    /// holds too: the same area, or the row sits in one further out.
    @MainActor static func fields(of view: NSView, among fields: [PanelTargetView]) -> [String] {
        let box: CGRect = view.convert(view.bounds, to: nil)
        let holding: Set<ObjectIdentifier> = Set(scrollAreas(of: view))
        var around: [(name: String, frame: CGRect)] = []
        for field in fields {
            let frame: CGRect = field.convert(field.bounds, to: nil)
            guard frame.contains(box) else { continue }
            // The row's own scrolling area has to hold this too. A row that
            // sits outside every scroller cuts nothing off, so it keeps its say.
            if let nearest = scrollAreas(of: field).first, !holding.contains(nearest) { continue }
            around.append((field.name, frame))
        }
        around.sort { first, second in
            first.frame.width * first.frame.height > second.frame.width * second.frame.height
        }
        return around.map(\.name)
    }

    /// The scrolling areas that cut this view off, nearest first. Empty for
    /// something the panel never scrolls.
    @MainActor static func scrollAreas(of view: NSView) -> [ObjectIdentifier] {
        var found: [ObjectIdentifier] = []
        var above = view.superview
        while let here = above {
            if let clip = here as? NSClipView { found.append(ObjectIdentifier(clip)) }
            above = here.superview
        }
        return found
    }

    /// Every tooltip anchor in the window: the invisible tracking views the
    /// designed tooltip watches the pointer with.
    @MainActor static func hintAnchors(in content: NSView) -> [HintAnchorView] {
        var found: [HintAnchorView] = []
        func walk(_ view: NSView) {
            if let anchor = view as? HintAnchorView,
               !view.isHiddenOrHasHiddenAncestor { found.append(anchor) }
            for sub in view.subviews { walk(sub) }
        }
        walk(content)
        return found
    }

    /// The tooltip a pointer resting on this point would show: the SMALLEST
    /// anchor covering it, so one picture's own anchor wins over an anchor
    /// laid across the whole row it sits in.
    @MainActor static func tip(at point: CGPoint, among anchors: [HintAnchorView]) -> String? {
        anchors
            .map { ($0, $0.convert($0.bounds, to: nil)) }
            .filter { $0.1.contains(point) }
            .min { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?
            .0.label
    }

    /// Every segmented picker in the window.
    @MainActor static func segmentedControls(in content: NSView) -> [NSSegmentedControl] {
        var controls: [NSSegmentedControl] = []
        func walk(_ view: NSView) {
            if let control = view as? NSSegmentedControl,
               !view.isHiddenOrHasHiddenAncestor { controls.append(control) }
            for sub in view.subviews { walk(sub) }
        }
        walk(content)
        return controls
    }

    /// The middle of one segment, across the control. A picker that gave its
    /// segments no widths of their own shares the room out evenly, which is
    /// what the segmented style in the panel does.
    @MainActor private static func centre(ofSegment index: Int, in control: NSSegmentedControl,
                                          box: CGRect) -> CGFloat {
        let widths = (0..<control.segmentCount).map { control.width(forSegment: $0) }
        let given = widths.reduce(0, +)
        guard given > 0, given <= box.width else {
            let share = box.width / CGFloat(control.segmentCount)
            return box.minX + share * (CGFloat(index) + 0.5)
        }
        // Whatever room the given widths left over is shared out evenly, the
        // way AppKit hands the slack to the segments that asked for nothing.
        let unsized = widths.filter { $0 <= 0 }.count
        let slack = unsized > 0 ? (box.width - given) / CGFloat(unsized) : 0
        var x = box.minX
        for earlier in 0..<index { x += widths[earlier] > 0 ? widths[earlier] : slack }
        let own = widths[index] > 0 ? widths[index] : slack
        return x + own / 2
    }
}
#endif

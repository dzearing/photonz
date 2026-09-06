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
            let chosen = control.selectedSegment
            let row = field(at: box, among: fields)
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

    /// The row a thing at this point sits on: the smallest labelled row it
    /// falls inside, so a picker takes its own row's word and not the one
    /// below it.
    @MainActor static func field(at box: CGRect, among fields: [PanelTargetView]) -> String? {
        fields
            .map { ($0, $0.convert($0.bounds, to: nil)) }
            .filter { $0.1.contains(box) }
            .min { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?
            .0.name
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

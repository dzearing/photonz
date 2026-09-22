import CoreGraphics
import Foundation

// The timing strip: one lap of the motion, a bar for every moving property.
//
// The Motion list in the side column can say WHAT changes and BY HOW MUCH, and
// it can say a start and a duration as two numbers. What it cannot say is how
// two parts of one drawing sit against each other IN TIME, because that is a
// comparison and a comparison needs width: the bell swings, the knob hanging
// off it swings a tenth of a second later, and the only way to see that is both
// bars on one ruler at once.
//
// Everything in this file is the arithmetic of that strip and none of it is the
// strip. The view is a thin shell over these types, which is both the rule for
// `PhotonzCore` and the reason a synthesized drag can be tested at all: SwiftUI
// gestures do not answer posted mouse events, so every number a drag decides
// has to be decidable without one.
//
// A note for the day the VIDEO timeline is built on this. The lanes, the bars,
// the drag and the gap readout are all the same job there and can be taken as
// they are. `MotionStripRuler` is the one thing that must NOT be shared: an
// icon strip measures ONE LAP with no end, so it leaves room past the loop mark
// for a bar to overrun into, while a video strip measures a document with a
// last frame and has nothing past it.

// MARK: - What is in the strip

/// One value a property is nailed to part way along its bar: a mark on the
/// bar, and the thing a hand can move without moving the rest of the move.
///
/// The two ENDS are not in here. They are the bar's own two handles, they
/// already have a gesture on them, and a mark sitting on top of one would take
/// the hand that was reaching for it.
public struct MotionStripKey: Hashable, Sendable {
    /// The moment, on the same clock the bar it sits on is drawn in.
    public var ms: Int
    /// What the property IS there, in the words the side column uses, so the
    /// mark can say "200%" rather than being an anonymous tick.
    public var reading: String

    public init(ms: Int, reading: String) {
        self.ms = ms
        self.reading = reading
    }
}

/// One bar: one property of one layer, changing over time.
public struct MotionStripLane: Identifiable, Hashable, Sendable {
    public var layerID: UUID
    public var motionID: UUID
    /// What the lane is called down the left hand edge: the property's name,
    /// the same words the entry in the side column wears.
    public var title: String
    public var timing: MotionTiming
    /// The moments BETWEEN the bar's two ends that the value is nailed to,
    /// first to last (`MotionStop`).
    ///
    /// Empty on everything that simply goes from one value to another, which
    /// is nearly everything, so a plain bar draws exactly as it always did. A
    /// punch in that pushes in, holds and pulls back out has two of them, and
    /// without them on the bar its four seconds say that something happens and
    /// nothing about where the camera arrives or how long it sits there.
    public var keys: [MotionStripKey]
    /// The switch on the entry in the side column. A lane that is off keeps its
    /// bar and is drawn quiet, exactly the way the eye on an effect works.
    public var isOn: Bool

    public var id: UUID { motionID }

    public init(layerID: UUID, motionID: UUID, title: String,
                timing: MotionTiming, isOn: Bool, keys: [MotionStripKey] = []) {
        self.layerID = layerID
        self.motionID = motionID
        self.title = title
        self.timing = timing
        self.keys = keys
        self.isOn = isOn
    }

    /// This lane re-timed, with its keys carried along in proportion.
    ///
    /// The same bargain `LayerMotion.retimed(to:)` strikes, and for the same
    /// reason: a bar under a hand is drawn where the hand has it, so its marks
    /// have to travel with it or the hold would appear to slide out of the move
    /// that owns it for as long as the drag lasts.
    public func retimed(to timing: MotionTiming) -> MotionStripLane {
        var moved = self
        moved.timing = timing
        guard !keys.isEmpty, self.timing.durationMS > 0 else { return moved }
        let stretch = Double(timing.durationMS) / Double(self.timing.durationMS)
        moved.keys = keys.map {
            var key = $0
            let along = Double($0.ms - self.timing.startMS) * stretch
            key.ms = timing.startMS + Int(along.rounded())
            return key
        }
        return moved
    }
}

/// The lanes belonging to one layer, under its row.
///
/// **A layer row carries a bar when the layer occupies time, and is a bare
/// heading when it does not** (`docs/design/video-surface.md` §2). One rule,
/// both jobs, no fork: a bell that rotates does not occupy time — the
/// properties on it do, so a bar on its row would be a bar with no start and
/// no duration, which is a bar that lies. A clip is exactly a start and an end,
/// so its row is a bar and the lanes under it are what moves while it plays.
public struct MotionStripGroup: Identifiable, Hashable, Sendable {
    public var layerID: UUID
    public var layerName: String
    public var lanes: [MotionStripLane]
    /// The stretch of the document's time this layer occupies, nil for a layer
    /// that is simply there the whole way through.
    public var bar: LayerTime?
    /// Whether this row's bar carries a SOUND, which is the one thing that
    /// makes a bar taller: a waveform squeezed into eighteen points is a smear,
    /// and a level line with nowhere to go up or down is not draggable
    /// (`docs/design/video-audio.md`).
    public var isSound: Bool

    public var id: UUID { layerID }

    public init(layerID: UUID, layerName: String, lanes: [MotionStripLane],
                bar: LayerTime? = nil, isSound: Bool = false) {
        self.layerID = layerID
        self.layerName = layerName
        self.lanes = lanes
        self.bar = bar
        self.isSound = isSound
    }
}

/// One end of some OTHER bar: what a drag can catch on, and what the gap
/// readout is measured from.
public struct MotionStripEdge: Hashable, Sendable {
    public var ms: Int
    /// The layer the edge belongs to, so the readout can say "90 ms after Bell
    /// body" rather than printing a number on its own.
    public var name: String
    /// True for the left hand end of a bar. Only ever used to prefer a start
    /// over a finish when the two are the same distance away, because lining a
    /// bar up with another bar's start is the far commoner thing to want.
    public var isStart: Bool

    public init(ms: Int, name: String, isStart: Bool) {
        self.ms = ms
        self.name = name
        self.isStart = isStart
    }
}

extension PhotonzDocument {

    /// Every moving property in the document, grouped under the layer it is on,
    /// **in the order the layers panel reads: topmost first**.
    ///
    /// The WHOLE document, unlike the Motion list in the side column, which
    /// speaks for the one layer you have picked. That difference is the reason
    /// the strip exists: a lag is a relationship between two layers, and a
    /// surface that can only see one of them can never show it.
    ///
    /// **Top down, because the stack IS the composite order**
    /// (`LayerCompositing.swift`). The renderer draws the array from the front,
    /// so the LAST layer in it is the one on top, and the layers panel has
    /// always turned that round to read topmost first. The strip used to read
    /// the array straight, which put a title's bar UNDERNEATH the bar of the
    /// clip it is laid over — saying, in the one surface where a video is
    /// arranged, that the title is behind the picture. One order now, in both
    /// places, and dragging a row up the layers list moves its bar up the
    /// timeline to match.
    public func motionStrip() -> [MotionStripGroup] {
        var groups: [MotionStripGroup] = []
        // **A part inherits the clock of the thing it is inside**, which is
        // the rule `drawn(atTimeMS:)` already samples motion by
        // (`DocumentTime.movedTree`). Without it here, a badge placed at four
        // seconds whose pieces move drew those pieces' lanes at nought: the
        // strip said the badge moves three seconds before it is on screen,
        // while the canvas played it correctly
        // (`components-on-the-timeline-animated-the-way-ever`).
        func walk(_ list: [Layer], shiftMS: Int) {
            for layer in list.reversed() {
                let shift = layer.occupiesTime ? layer.motionShiftMS : shiftMS
                if let group = stripGroup(layer, shiftMS: shift) { groups.append(group) }
                if layer.isGroup { walk(layer.children, shiftMS: shift) }
            }
        }
        walk(layers, shiftMS: 0)
        return groups
    }

    /// One layer's row on the strip, or nil where it has nothing to draw.
    ///
    /// `shiftMS` is how far this layer's own clock sits along the document's:
    /// its own where it occupies time, and whatever it is inside where it does
    /// not.
    private func stripGroup(_ layer: Layer, shiftMS: Int) -> MotionStripGroup? {
        let motions = layer.motions ?? []
        // A row earns its place by having something to draw: a stretch of
        // time, something moving, or both. A layer with neither is a
        // labelled hairline with nothing under it.
        guard !motions.isEmpty || layer.occupiesTime else { return nil }
        return MotionStripGroup(
            layerID: layer.id,
            // What the LAYERS LIST calls it, which for words nobody has
            // renamed is the words themselves. A title's bar on the
            // timeline saying "Text" among clips named after their
            // recordings is a row you have to click to identify
            // (`TitleTime.swift`).
            layerName: layer.displayName(readWords: [:]),
            // Drawn where it HAPPENS, on the document's clock. Nought in a
            // document with no time in it, so an icon's strip is exactly what
            // it was.
            lanes: motions.map { motion in
                MotionStripLane(layerID: layer.id, motionID: motion.id,
                                title: motion.property.title,
                                timing: motion.timing.shifted(byMS: shiftMS),
                                isOn: motion.isOn,
                                // The ones BETWEEN the ends, on the document's
                                // clock like the bar they sit on.
                                keys: motion.keys.dropFirst().dropLast().map {
                                    MotionStripKey(ms: $0.atMS + shiftMS,
                                                   reading: motion.property.format($0.value))
                                })
            },
            bar: layer.time,
            isSound: layer.sound != nil)
    }

    /// The ends of every bar except one: what the bar being dragged can catch
    /// on, and what its gap is measured from. The top of the lap is in here
    /// too, so that nought is as easy to come back to as any other bar.
    public func motionStripEdges(excluding motionID: UUID) -> [MotionStripEdge] {
        var edges = [MotionStripEdge(ms: 0, name: MotionStripCopy.topOfTheLap, isStart: true)]
        for group in motionStrip() {
            // A clip's own two ends are edges like any other, so a motion
            // dragged along the strip can be landed on the cut it belongs to.
            if let bar = group.bar {
                edges.append(MotionStripEdge(ms: bar.inMS, name: group.layerName, isStart: true))
                edges.append(MotionStripEdge(ms: bar.outMS, name: group.layerName, isStart: false))
            }
            for lane in group.lanes where lane.motionID != motionID {
                edges.append(MotionStripEdge(ms: lane.timing.startMS, name: group.layerName,
                                             isStart: true))
                edges.append(MotionStripEdge(ms: lane.timing.endMS, name: group.layerName,
                                             isStart: false))
            }
        }
        return edges
    }
}

/// The few words the strip says, in one place so the view and the tests agree.
public enum MotionStripCopy {
    public static let topOfTheLap = "the start"
    public static let title = "One cycle"
    /// What the same strip is called when what it measures FINISHES rather
    /// than starting over: a recording, not an icon.
    public static let documentTitle = "Timeline"
    /// What the strip is called when it is not open: the name on the row left
    /// behind, so a person who put it away can see what they put away.
    public static let stripName = "Timing"
    /// What the row says it will do, because the whole complaint it answers is
    /// that there was nothing on screen saying the strip could come back.
    public static let showAgain = "click to open"
}

// MARK: - What the row says while the strip is put away

/// The one line a put-away strip leaves on screen.
///
/// The reason you pushed the strip down was to look at the picture, so the
/// question you have while it is away is "what am I still editing", not "is
/// there a timing strip". So the row leads with the ANSWER — the layer and the
/// properties moving on it — and the strip's own name is only the label in
/// front of it.
public enum MotionStripSummary {

    /// Past this many properties the row counts the rest. A row is one line
    /// and it is read at a glance; a list of five property names on it is a
    /// list nobody finishes.
    static let namedLimit = 2

    /// `Bell body · Rotation · 900 ms`, or `2 layers moving · 900 ms` when no
    /// one layer can speak for the strip.
    ///
    /// Empty when nothing moves, because then there is no strip and no row.
    public static func text(groups: [MotionStripGroup],
                            selectedLayerID: UUID?,
                            cycleMS: Int) -> String {
        guard !groups.isEmpty else { return "" }
        let lap = "\(max(1, cycleMS)) ms"
        guard let group = spokenFor(groups: groups, selectedLayerID: selectedLayerID) else {
            return "\(groups.count) layers moving · \(lap)"
        }
        let moving = properties(of: group)
        // A clip with nothing moving on it has no middle to say. An empty
        // segment between two separators reads as a missing word.
        guard !moving.isEmpty else { return "\(group.layerName) · \(lap)" }
        return "\(group.layerName) · \(moving) · \(lap)"
    }

    /// The one layer the row can speak for: the picked one where it is moving,
    /// and the only mover where there is only one. Several movers and a pick
    /// that is not among them leaves nobody entitled to the row, so it counts
    /// instead — naming one of two would be picking a side.
    static func spokenFor(groups: [MotionStripGroup],
                          selectedLayerID: UUID?) -> MotionStripGroup? {
        if let selectedLayerID,
           let picked = groups.first(where: { $0.layerID == selectedLayerID }) {
            return picked
        }
        return groups.count == 1 ? groups[0] : nil
    }

    /// `Rotation`, `Rotation, Opacity`, `Rotation and 2 more`.
    static func properties(of group: MotionStripGroup) -> String {
        let titles = group.lanes.map(\.title)
        guard titles.count > namedLimit else { return titles.joined(separator: ", ") }
        return "\(titles[0]) and \(titles.count - 1) more"
    }
}

// MARK: - The ruler

/// What the numbers along the top of the strip mean.
///
/// It measures ONE LAP and then some. The room past the lap is not decoration:
/// a motion that starts late finishes after the loop has already restarted, and
/// that overrun is the thing the dashed line is there to let you see. With the
/// ruler ending exactly at the lap there would be nowhere to draw it and the
/// bar would simply be clipped, which reads as a bug rather than as a fact
/// about the animation.
public struct MotionStripRuler: Hashable, Sendable {
    /// How long one lap is. For a document that finishes, the document itself.
    public let cycleMS: Double
    /// How much time the strip's width covers, lap and headroom together. On
    /// a timeline opened out, how much time the WINDOW covers.
    public let spanMS: Double
    /// The moment at the strip's left hand edge. Nought unless the timeline
    /// has been opened out, which is the only thing that moves it
    /// (`TimelineZoom.swift`).
    public let startMS: Double
    /// Whether what this ruler measures starts over when it gets to the end.
    ///
    /// True for an icon, which is what the headroom and the dashed line are
    /// for. False for a document with a last frame: there is nothing past the
    /// last frame to overrun into and nothing to restart, so the ruler ends
    /// exactly where the picture does.
    public let repeats: Bool

    /// How much room past the end of the lap, as a share of the lap. A third is
    /// enough to draw a bar that overruns by a tenth of a second and still
    /// leaves the lap itself the great majority of the width.
    static let headroom = 1.0 / 3

    public init(cycleMS: Int) {
        let cycle = Double(max(1, cycleMS))
        self.cycleMS = cycle
        self.spanMS = cycle * (1 + Self.headroom)
        self.startMS = 0
        self.repeats = true
    }

    /// The ruler a document with a last frame gets: it measures the document
    /// and stops. No headroom, because a bar cannot overrun a picture that has
    /// ended, and no restart mark, because nothing restarts.
    public init(documentMS: Int) {
        let length = Double(max(1, documentMS))
        self.cycleMS = length
        self.spanMS = length
        self.startMS = 0
        self.repeats = false
    }

    /// The ruler a document gets once the timeline has been **opened out**: it
    /// measures the stretch on screen rather than the whole document
    /// (`TimelineZoom.swift`).
    ///
    /// Everything drawn on the strip goes through the two calls below, so
    /// windowing the ruler is the whole of the zoom: no bar, join, waveform or
    /// playhead knows it has happened.
    public init(documentMS: Int, zoom: TimelineZoom) {
        let length = Double(max(1, documentMS))
        let window = zoom.clamped(documentMS: length)
        self.cycleMS = length
        self.spanMS = window.visibleMS(documentMS: length)
        self.startMS = window.startMS
        self.repeats = false
    }

    /// Where a millisecond falls across the strip's width, nought at the left
    /// edge and one at the right.
    ///
    /// A MOMENT, which on an opened out timeline is measured from the left
    /// hand edge of the window rather than from the start of the document.
    public func fraction(ofMS ms: Double) -> Double { (ms - startMS) / spanMS }

    /// The other way round: the millisecond a fraction of the width lands on.
    public func ms(atFraction fraction: Double) -> Double { startMS + fraction * spanMS }

    /// How wide a LENGTH of time is, as a share of the strip's width.
    ///
    /// Not the same question as `fraction(ofMS:)` and the difference only
    /// shows once the strip is opened out: a moment is measured from the
    /// window's left hand edge, a length is measured from nothing. Taking the
    /// window's start off a duration would make every bar on a zoomed
    /// timeline the wrong size.
    public func fraction(spanningMS ms: Double) -> Double { ms / spanMS }

    /// The other way round: how long a sideways travel across the strip is
    /// worth, which is what a drag asks.
    public func msSpanning(fraction: Double) -> Double { fraction * spanMS }

    /// One moment, said out loud, in the units this ruler is written in.
    ///
    /// A recording is read in seconds, because that is how long one is and how
    /// everything that has ever played one says so. A lap stays in
    /// milliseconds, because ninety of them is the whole reason the strip
    /// exists.
    public func reading(ofMS ms: Int) -> String {
        repeats ? "\(ms) ms" : String(format: "%.1fs", Double(ms) / 1000)
    }

    /// Where the dashed line goes: the moment the lap starts over. It sits on
    /// the right hand edge, and so is not drawn, for a ruler that does not
    /// repeat.
    public var repeatsFraction: Double { fraction(ofMS: cycleMS) }

    /// One number written along the top.
    public struct Tick: Hashable, Sendable {
        public let ms: Double
        public let label: String
    }

    /// The numbers along the top, evenly spaced on a step a person would say
    /// out loud. Only the last one carries the unit, because a row reading
    /// "0ms 200ms 400ms" is a row of units with some numbers in it.
    public var ticks: [Tick] {
        let step = Self.step(for: spanMS)
        var values: [Double] = []
        // The first round number at or after the window's left hand edge, so
        // an opened out ruler reads off the same ladder the whole one does
        // rather than counting from wherever the window happens to start.
        var ms = (startMS / step).rounded(.down) * step
        if ms < startMS - 0.001 { ms += step }
        while ms <= startMS + spanMS + 0.001 {
            values.append(ms)
            ms += step
        }
        // A document is read in minutes and seconds, because that is how long a
        // recording is and how everything that has ever played one says so. A
        // lap stays in milliseconds, because ninety of them is the whole reason
        // the strip exists (`docs/design/video.md`).
        guard repeats else {
            return values.map { Tick(ms: $0, label: MotionStripRuler.timecode($0, step: step)) }
        }
        return values.enumerated().map { index, ms in
            let number = MotionStripRuler.number(ms)
            return Tick(ms: ms, label: index == values.count - 1 ? "\(number) ms" : number)
        }
    }

    /// `0:04`, or `1:02:11` once there are hours in it.
    public static func timecode(_ ms: Double) -> String {
        let total = Int((max(0, ms) / 1000).rounded(.down))
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// The same, in tenths where the numbers are closer together than a
    /// second. A timeline opened right out puts a second across the whole
    /// width, and a row reading "0:12 0:12 0:12 0:12" is not a ruler.
    static func timecode(_ ms: Double, step: Double) -> String {
        guard step < 1000 else { return timecode(ms) }
        let tenths = (max(0, ms) / 100).rounded()
        let whole = (tenths / 10).rounded(.down) * 1000
        return timecode(whole) + "." + String(Int(tenths) % 10)
    }

    /// A step that gives between four and nine numbers, chosen off the 1, 2, 5
    /// ladder so every one of them is round.
    static func step(for span: Double) -> Double {
        let target = span / 6
        let magnitude = pow(10, (log10(max(target, 1))).rounded(.down))
        for multiple in [1.0, 2.0, 2.5, 5.0, 10.0] {
            let step = multiple * magnitude
            if step >= target { return step }
        }
        return magnitude * 10
    }

    static func number(_ ms: Double) -> String {
        ms == ms.rounded() ? String(Int(ms.rounded())) : String(format: "%g", ms)
    }
}

// MARK: - Dragging a bar

/// A bar under a hand.
///
/// It holds the timing the bar had when it was GRABBED and works every answer
/// out from that, so the numbers can never creep: a drag that adds its delta to
/// wherever the bar got to last would drift a little further every frame, which
/// is exactly the bug that makes a timeline feel slippery.
public struct MotionStripDrag: Hashable, Sendable {

    /// Which part of the bar is in the hand.
    public enum Grab: Hashable, Sendable {
        /// The bar itself: it moves, keeping its length.
        case body
        /// Its left hand end: the start moves and the finish stays put.
        case start
        /// Its right hand end: the finish moves and the start stays put.
        case end
    }

    /// A bar is never shorter than this. A motion of nought milliseconds is a
    /// division by nought in the frame loop, and one of a single millisecond is
    /// a bar too thin to ever grab again.
    public static let shortestMS = 10

    public let grab: Grab
    /// The timing the bar had when it was taken hold of.
    public let timing: MotionTiming
    /// The ends of every other bar, and the top of the lap.
    public let others: [MotionStripEdge]
    /// How close a drop has to land to catch on one of those.
    public let snapWithinMS: Int

    public init(grab: Grab, timing: MotionTiming,
                others: [MotionStripEdge] = [], snapWithinMS: Int = 0) {
        self.grab = grab
        self.timing = timing
        self.others = others
        self.snapWithinMS = snapWithinMS
    }

    /// What the timing becomes when the hand has moved this many milliseconds,
    /// with nothing caught on.
    public func moved(byMS delta: Int) -> MotionTiming {
        switch grab {
        case .body:
            return MotionTiming(startMS: max(0, timing.startMS + delta),
                                durationMS: timing.durationMS)
        case .end:
            return MotionTiming(startMS: timing.startMS,
                                durationMS: max(Self.shortestMS, timing.durationMS + delta))
        case .start:
            // The finish is the fixed point, which is what makes this feel like
            // pulling one end of a thing rather than moving the whole thing.
            let finish = timing.endMS
            let start = min(max(0, timing.startMS + delta), finish - Self.shortestMS)
            return MotionTiming(startMS: start, durationMS: finish - start)
        }
    }

    /// Where the bar lands, and what it caught on to get there.
    public struct Landing: Hashable, Sendable {
        public let timing: MotionTiming
        public let snappedTo: MotionStripEdge?
    }

    /// The drop: the same arithmetic as `moved(byMS:)`, and then a look at
    /// whether the end that moved came down near another bar's end.
    ///
    /// The catching is deliberately SHORT — a handful of milliseconds — because
    /// the job this strip exists for is putting the knob ninety milliseconds
    /// behind the bell, and a snap wide enough to be helpful for lining things
    /// up would eat exactly that.
    public func landing(byMS delta: Int) -> Landing {
        let free = moved(byMS: delta)
        guard snapWithinMS > 0, !others.isEmpty else {
            return Landing(timing: free, snappedTo: nil)
        }
        let moving = grab == .end ? free.endMS : free.startMS
        let nearest = others
            .filter { abs($0.ms - moving) <= snapWithinMS }
            // Nearest wins; a tie goes to a start, because lining up with where
            // something BEGINS is the far commoner thing to want.
            .min { a, b in
                let da = abs(a.ms - moving), db = abs(b.ms - moving)
                return da == db ? (a.isStart && !b.isStart) : da < db
            }
        guard let nearest, nearest.ms != moving else {
            return Landing(timing: free, snappedTo: nil)
        }
        return Landing(timing: moved(byMS: delta + (nearest.ms - moving)), snappedTo: nearest)
    }
}

// MARK: - Dragging one key along a bar

/// One of the keys between a bar's two ends, under a hand.
///
/// A whole bar in the hand is `MotionStripDrag`: the move happens later, or
/// takes longer, and everything nailed down inside it travels in proportion.
/// This is the other half of the same surface and it is deliberately the
/// opposite bargain: **the move stays exactly where it is and ONE of its
/// moments changes.** On a punch in that pushes in, holds and pulls back out,
/// that is the difference between "start the whole thing a second later" and
/// "sit there a second longer before pulling out", and only one of those two
/// could be said before.
///
/// Like the bar drag, it works everything out from the keys as they were when
/// the mark was GRABBED, so a drag can never creep frame by frame.
public struct MotionStopDrag: Hashable, Sendable {

    /// A key never lands nearer than this to the key either side of it. Nearer
    /// and the two marks are one mark to the eye and neither can be grabbed
    /// again; past it they would swap over, which draws one move as a
    /// different move.
    public static let shortestMS = 10

    /// Every key on the bar when the mark was taken hold of, first to last,
    /// the bar's own two ends included.
    public let keys: [Int]
    /// Which of the ones BETWEEN those ends is in the hand, counting from
    /// nought at the left.
    public let middle: Int

    /// Nil where there is no such mark to take hold of. The two ends are not
    /// keys a hand can move here: they are the bar's own handles and they
    /// already have a gesture on them.
    public init?(keys: [Int], middle: Int) {
        let index = middle + 1
        guard middle >= 0, index < keys.count - 1 else { return nil }
        self.keys = keys
        self.middle = middle
    }

    /// Where the key is into the bar's index of keys, ends counted.
    private var index: Int { middle + 1 }

    /// Where the key was when it was grabbed.
    public var heldMS: Int { keys[index] }

    /// Where it lands once the hand has moved this many milliseconds.
    public func moved(byMS delta: Int) -> Int {
        let earliest = keys[index - 1] + Self.shortestMS
        let latest = keys[index + 1] - Self.shortestMS
        // Two keys already crowded closer than twice the gap leave nowhere to
        // go. The mark stays put rather than jumping to a bound it is already
        // the wrong side of.
        guard earliest <= latest else { return heldMS }
        return min(max(heldMS + delta, earliest), latest)
    }
}

// MARK: - What a drag does to the lap

/// What the drag leaves the lap's length as.
///
/// The rule is one sentence and it is the whole of why the lap is writable at
/// all: **a bar dragged past the end of the lap holds the lap where it was and
/// overruns it; a bar dragged back inside it hands the lap back to following
/// the longest motion.**
///
/// Without the first half nothing could ever run past the restart, because the
/// lap would simply grow to swallow it — and a bar still finishing while the
/// loop has already begun again IS what a lag in something that repeats looks
/// like. Without the second half, one drag out and back would leave a held
/// number behind that nobody asked for and that would then refuse to grow for
/// the next motion added.
public enum MotionStripCycle {

    /// - Parameters:
    ///   - held: how long the lap was when the bar was taken hold of.
    ///   - automatic: how long it would be now if nobody had written one down,
    ///     which is the end of the longest motion after the drag.
    ///   - current: what the document has written down now, nil for following.
    /// - Returns: what to write down, nil for going back to following.
    public static func after(drag held: Int, automatic: Int, current: Int?) -> Int? {
        // Something now runs past the lap: hold the lap, let it overrun.
        if automatic > held { return held }
        // The written number and the automatic one agree, so there is nothing
        // for the written one to say: hand it back.
        if current == automatic { return nil }
        return current
    }
}

// MARK: - The number between two bars

/// The lag: how far the bar in the hand starts from the nearest end of any
/// other bar, and what that other bar is called.
///
/// The mock drew one bracket from the left edge of the strip to the bar's
/// start, which only reads as a lag because in its example the bell happens to
/// start at nought. With five bars on the strip that number says nothing at
/// all. So this measures to the NEAREST OTHER EDGE and names it, which is the
/// relationship a person is actually making while they drag.
public struct MotionStripGap: Hashable, Sendable {
    /// How far after that edge this bar starts. Negative means before it.
    public let ms: Int
    /// The millisecond it is measured from, so the bracket knows where to
    /// start being drawn.
    public let fromMS: Int
    public let name: String

    public init?(startMS: Int, others: [MotionStripEdge]) {
        guard let nearest = others.min(by: { abs($0.ms - startMS) < abs($1.ms - startMS) })
        else { return nil }
        self.ms = startMS - nearest.ms
        self.fromMS = nearest.ms
        self.name = nearest.name
    }

    /// What the little label over the bracket says.
    public var reading: String {
        if ms == 0 { return "together with \(name)" }
        return "\(abs(ms)) ms \(ms > 0 ? "after" : "before") \(name)"
    }
}

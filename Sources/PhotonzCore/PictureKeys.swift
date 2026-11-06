import Foundation

// A picture animated by setting moments and changing things
// (task `animating-a-picture-is-as-simple-as-setting-a-mo`,
// `docs/design/mocks/pages/picture-keys.html`).
//
// The user, 2026-11-04: "I want to just start creating keyframes where maybe I
// position something, save a keyframe, or click on one, adjust some things ...
// and it persists on that keyframe and auto tweens." So a picture keys the way
// a video does (`KeyMoments.swift`) and it stays a picture: it has a lap rather
// than a duration, because `hasTime` flips the document's kind, its tool bar
// and its title chip, and an icon repeats where a video finishes.
//
// Only pressing Add Key starts this. A picture nobody pressed it on has no key
// clock, and every motion on it reads and plays exactly as it did, a saved
// Once included.

/// How a keyed picture's lap plays.
public struct KeyLap: Hashable, Codable, Sendable {
    /// True goes round for ever, which is what an animated SVG does. False
    /// plays one lap and holds the last moment.
    public var repeats: Bool

    public init(repeats: Bool = true) {
        self.repeats = repeats
    }
}

extension KeyLap {

    /// One number on the strip's ruler.
    public struct Tick: Hashable, Sendable {
        public var ms: Int
        public var label: String
    }

    /// The numbers on a lap's ruler, in seconds, stopping short of the end:
    /// the word at the repeats mark sits there and must not land on a number.
    public static func ticks(lapMS: Int) -> [Tick] {
        let step = lapMS >= 1500 ? 1000 : lapMS >= 600 ? 500 : 100
        return stride(from: 0, to: lapMS - step / 4, by: step).map { ms in
            let seconds = Double(ms) / 1000
            let text = ms % 1000 == 0 ? String(ms / 1000) : String(format: "%.1f", seconds)
            return Tick(ms: ms, label: text + "s")
        }
    }

    /// A moment on the lap as the bar writes it: a lap is seconds long, so
    /// hundredths are what tell two keys apart ("0:01.50").
    public static func timecode(ms: Int) -> String {
        let hundredths = max(0, ms) / 10
        return String(format: "%d:%02d.%02d", hundredths / 6000, hundredths / 100 % 60, hundredths % 100)
    }
}

extension PhotonzDocument {

    /// How long a picture's lap is when the first key makes one: enough to
    /// hold a move and a fade, where a swing's 0.9 seconds is not.
    public static let firstKeyLapMS = 2000

    /// Whether this is a picture animated by keys: Add Key was pressed and
    /// something on it still has a key or a hollow moment. Asked rather than
    /// stored, so the last key leaving by any route (Delete, a row's cross,
    /// the layer itself going) is a still picture again, and Undo brings the
    /// lap back with the keys.
    public var isKeyedPicture: Bool {
        guard keyLap != nil, !hasTime else { return false }
        return allLayers.contains { isAnimating($0) }
    }

    /// Whether keys have a clock to stand on here: a document with time, or a
    /// keyed picture. Its playhead is the window's document time on both.
    public var hasKeyClock: Bool { hasTime || isKeyedPicture }

    /// The first key on a picture gives it a lap. One already written down is
    /// kept, and a lap following motions already on the picture is written
    /// down at that length, so a key does not change how they play.
    mutating func startKeyLap() {
        guard !hasTime, !isKeyedPicture else { return }
        if keyLap == nil { keyLap = KeyLap() }
        if motionCycleMS == nil {
            let following = automaticMotionCycleLengthMS
            motionCycleMS = following > 0 ? following : Self.firstKeyLapMS
        }
    }

    /// The Repeat button on a keyed picture's bar.
    public mutating func setKeyLapRepeats(_ repeats: Bool) {
        guard keyLap != nil else { return }
        keyLap?.repeats = repeats
    }

    /// The shortest a keyed picture's lap can be made: just past its last key
    /// or hollow moment, so the repeats mark cannot cross one and leave a key
    /// that never plays.
    public var shortestKeyLapMS: Int {
        var last = 0
        for layer in allLayers {
            last = max(last, clipKeyMarks(layerID: layer.id).map(\.documentMS).max() ?? 0)
        }
        return last + 1
    }

    /// `posedForCanvas` on a keyed picture: every layer that moves wears its
    /// place, size and angle at `ms`, however deep in a frame it sits.
    func posedPicture(atTimeMS ms: Int, posing: Set<MotionProperty>) -> PhotonzDocument {
        let cycle = max(1, timelineLengthMS)
        var posed = self
        posed.layers = layers.map { $0.posedTree(atMS: ms, cycleMS: cycle, posing: posing) }
        return posed
    }

    /// What a still of this document shows: on a keyed picture its first
    /// moment, because the layers as stored are where they were before any
    /// key, somewhere the picture may never have been. Everything else is
    /// itself.
    public var keyedStill: PhotonzDocument {
        isKeyedPicture ? moved(toMotionTimeMS: 0) : self
    }

    /// This document as it PLAYS: on a repeating keyed picture every key goes
    /// round with the lap. Keys are stored as `once`, which is what makes them
    /// keys, so this is asked at the moment of drawing or writing a file and
    /// never written back. A motion on its own pace keeps it.
    public var lappingKeys: PhotonzDocument {
        guard keyLap?.repeats == true, isKeyedPicture else { return self }
        var lapping = self
        lapping.layers = layers.map(\.lappingKeys)
        return lapping
    }
}

extension Layer {

    /// This layer and everything inside it, wearing the box and the turn it
    /// has at `ms`, and nothing else.
    func posedTree(atMS ms: Int, cycleMS: Int, posing: Set<MotionProperty>) -> Layer {
        var pose = self
        if (motions ?? []).contains(where: { posing.contains($0.property) }) {
            var uncut = self
            if hasKeyedCrop { uncut.motions = motions?.filter { !$0.property.isCrop } }
            let moved = uncut.moved(toMotionTimeMS: ms, cycleMS: cycleMS)
            pose.frame = moved.frame
            pose.transform.rotation = moved.transform.rotation
            pose.turn3D = moved.turn3D
        }
        if var group = pose.group {
            group.children = group.children.map { $0.posedTree(atMS: ms, cycleMS: cycleMS, posing: posing) }
            pose.content = .group(group)
        }
        return pose
    }

    /// `PhotonzDocument.lappingKeys`, for this layer and everything inside it.
    var lappingKeys: Layer {
        var layer = self
        layer.motions = motions?.map { motion in
            guard motion.repeats == .once else { return motion }
            var lapping = motion
            lapping.repeats = .everyLap
            return lapping
        }
        if var group = layer.group {
            group.children = group.children.map(\.lappingKeys)
            layer.content = .group(group)
        }
        return layer
    }
}

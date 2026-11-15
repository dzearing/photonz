import Foundation

/// The general ways a part of a drawing can move, which Ask picks from and
/// combines for a moving icon (`docs/design/ask.md`, "The techniques it picks
/// from"). Each is said by what it does to parts, pivots, paths and time, and
/// by the keys that carry it, never by a subject: the user, 2026-11-14, after
/// twenty passes on one story, "i want it to be able to draw a thing and
/// animate something about it. I want it to have techniques for doing that."
///
/// Not in the model's prompt yet. Wired in four ways on 2026-11-14 (the whole
/// catalogue in the plan; only the techniques the design named; with the look
/// and a pivot check; with fold and turn told apart), the sealed motion set read
/// 35.8, 37.3, 34.1 and 32.9 against 38.6 without it, so each was taken out
/// (docs/design/ask.md, "The techniques it picks from"). `chosen` and
/// `howToKey` are what the second way used.
public enum AskMotionTechnique: String, CaseIterable, Sendable {
    case turn, fold, squash, throwArc, shake, pulse, sway, spin, drawsOn, pop, entersOrLeaves, restsBetweenLaps, followThrough

    /// What the model calls it in its design.
    public var name: String {
        switch self {
        case .turn: "turn on a pivot"
        case .fold: "fold over an edge"
        case .squash: "squash and stretch"
        case .throwArc: "throw on an arc"
        case .shake: "shake"
        case .pulse: "pulse"
        case .sway: "sway in a chain"
        case .spin: "spin or orbit"
        case .drawsOn: "draw a line on"
        case .pop: "pop in or out"
        case .entersOrLeaves: "enter or leave the frame"
        case .restsBetweenLaps: "rest between laps"
        case .followThrough: "follow through and stagger"
        }
    }

    /// What it does to parts, pivots, paths and time, and how it is keyed,
    /// in the words the model reads.
    public var does: String {
        switch self {
        case .turn:
            "a part fixed at one point swings about it flat across the picture, as far as it could really go and back: a part that hangs, a stick or arm seen side on. rotation, pivot ON the joint at the part's end (never its middle); Ease in out, 300 to 600 ms a swing; lifting is negative rotation when the pivot is at the part's left end, positive at its right end. It is never for a part that opens or shuts on a hinge along its edge: that is fold over an edge."
        case .fold:
            "a flat part hinged along a whole straight edge, seen from the front, folds over that edge as it opens or shuts: anything that opens or shuts on a hinge along its edge is a fold. rotationX for a level edge (it tips toward or away from you), rotationY for an upright one (it swings toward you like a page), pivot the middle of that edge, 180 lying open the other side; never rotation, which turns it flat like a clock hand."
        case .squash:
            "a soft or springy part keeps its bulk: lower and wider as it lands or presses, taller and narrower as it leaps or pulls, 80 to 150 ms each, then back on Ease out back. Squash: rotationX 30 to 40 with pivot on the middle of its bottom edge, and scale 106 to 110. Stretch: rotationY 25 to 35 with pivot on its upright middle line, and scale 108 to 115."
        case .throwArc:
            "a part travels from where it is first seen (in view, or past the frame) along a curve: position x and y keyed together at the same times, rising keys Ease out, falling keys Ease in; it lands at speed, squashes, hops back up about half as high and half as long each time (two or three hops), and settles."
        case .shake:
            "the whole object, all of it in one <g>, jolts back and forth: rotation 8 to 12 degrees each way about its middle (or its base, for something standing), or position 1 to 1.5 on the grid, 50 to 80 ms a jolt, three or four times, then still. A buzz is the same, quicker and smaller, in bursts with still gaps between."
        case .pulse:
            "a part grows and shrinks about its own middle: scale 100 to 108 to 115 and back. A beat is quick, about 150 ms up and 250 ms down; breathing is slow, 1 to 2 s, Ease in out. A glow is a copy or ring behind it that grows while its opacity falls to 0."
        case .sway:
            "a part made of a chain (segments, strips, blades, a stalk) waves with each piece a little behind the last: each piece its own part, keyed with the same curve of rotation (pivot at the joint nearer the fixed end) or position y, each one 60 to 120 ms later and a little bigger toward the free end, Ease in out, so a ripple runs along it."
        case .spin:
            "a part turns round and round: rotation 0 to 360, Linear, pivot exactly at the centre it turns about (its own centre for a spin; for an orbit, the centre of the circle it travels round, so it goes round that). A lap ends on a whole 360."
        case .drawsOn:
            "a line appears along its own length as if being drawn: trimEnd 0 to 100, Ease in out, several lines one after another a little apart; it holds drawn, then fades out and is undrawn while unseen before the lap starts again."
        case .pop:
            "a part appears from nothing at its own middle: scale 0 to 115 to 100 on Ease out back within 150 to 250 ms, opacity 0 to 100 in its first 80 ms; it leaves by swelling a little and shrinking to 0 as it fades. What bursts swells, is gone within 100 ms, and three to six small pieces fly out from where it was, slowing and fading."
        case .entersOrLeaves:
            "a part travels in from past the frame's edge to its rest on Ease out, or from its rest all the way out past the edge on Ease in, over 300 to 500 ms, tilted a little into the way it goes, seen the whole way. position only; it never stops half over the edge, and it comes back by the next lap."
        case .restsBetweenLaps:
            "the action plays in the first half of the lap and every part then holds still at rest until the lap ends, so the action reads as an event that repeats, not a jitter: set_timing seconds 2 to 4, each value's last key (position, rotation, scale, opacity) at the lap's end equal to its first."
        case .followThrough:
            "what hangs from or rides on a moving part starts its rotation or position 40 to 100 ms after it, overshoots and settles back, each swing smaller (Ease out back, or one small swing past rest and back); several parts doing the same thing start one after another 60 to 120 ms apart, never all at once."
        }
    }

    /// The values that carry it: every one an animated SVG keeps
    /// (`MotionSVG.carried`).
    public var keys: [MotionProperty] {
        switch self {
        case .turn: [.rotation]
        case .fold: [.rotationX, .rotationY]
        case .squash: [.rotationX, .rotationY, .scale]
        case .throwArc: [.position, .rotation]
        case .shake: [.rotation, .position, .opacity]
        case .pulse: [.scale, .opacity]
        case .sway: [.rotation, .position]
        case .spin: [.rotation]
        case .drawsOn: [.trimEnd, .opacity]
        case .pop: [.scale, .opacity, .position]
        case .entersOrLeaves: [.position, .rotation]
        case .restsBetweenLaps: [.position, .scale, .rotation, .opacity, .rotationX, .rotationY, .trimEnd]
        case .followThrough: [.rotation, .position, .scale]
        }
    }

    /// What else a design may call it: a model names a technique in its own
    /// words as often as by the catalogue's.
    var said: [String] {
        switch self {
        case .turn: [name, "turn on its pivot", "turn on pivot", "turns on a pivot"]
        case .fold: [name, "fold over its edge", "folds over", "fold"]
        case .squash: [name, "squash", "stretch"]
        case .throwArc: [name, "thrown on an arc", "throw"]
        case .shake: [name, "buzz"]
        case .pulse: [name, "breathe", "breathing"]
        case .sway: [name, "sway"]
        case .spin: [name, "spin", "orbit"]
        case .drawsOn: [name, "draws on", "draw on", "draws itself", "draw itself"]
        case .pop: [name, "pops in", "pops out", "pop"]
        case .entersOrLeaves: [name, "enter the frame", "enters the frame", "leave the frame", "leaves the frame"]
        case .restsBetweenLaps: [name, "rests between laps"]
        case .followThrough: [name, "follow through", "follows through", "stagger"]
        }
    }

    /// The techniques a design names, in the catalogue's order.
    public static func chosen(in design: String) -> [AskMotionTechnique] {
        let words = " " + design.lowercased().map { $0.isLetter ? $0 : " " }.split(separator: " ").joined(separator: " ") + " "
        return allCases.filter { technique in technique.said.contains { words.contains(" \($0) ") } }
    }

    /// How to key what a design chose, for the plan that draws it: only those
    /// techniques, so the plan reads a few lines rather than the catalogue.
    /// Read whole, the catalogue lengthened the plan and broke three times as
    /// many tool calls on the sealed motion set (2026-11-14, 12 of 233
    /// against 4 of 187).
    public static func howToKey(_ chosen: [AskMotionTechnique]) -> String? {
        guard !chosen.isEmpty else { return nil }
        return "How to key the techniques you chose:\n" + chosen.map { "- \($0.name): \($0.does)" }.joined(separator: "\n")
    }

    /// The catalogue as the model reads it: one line a technique.    /// The catalogue as the model reads it: one line a technique.
    public static var catalogue: String {
        "- Techniques. Pick for each part that moves the technique that makes it do what the words say, and combine two or more when the words ask for more than one thing:\n"
            + allCases.map { "  - \($0.name): \($0.does)" }.joined(separator: "\n")
    }
}

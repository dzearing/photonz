// The one word a control says when the layers it speaks for do not agree.
//
// Three different types used to each keep their own copy of it — a style row's,
// a geometry field's, a color row's — and nothing held them together beyond
// their spelling. A design review on 2026-09-04 found the panel reading as two
// panels for the same reason on the other side: the same word drawn at three
// different strengths, and in one place not drawn at all.
//
// So the word lives here, once, and every control takes it from here. How it
// is DRAWN is the app layer's business (`MixedLook.swift`), because a strength
// is a color and PhotonzCore stays pure; what a control must not do is invent
// its own wording.

/// What every control shows in place of a value when the things it speaks for
/// do not agree on one.
public enum MixedValue {
    /// The word itself. One spelling, one capitalisation, everywhere.
    public static let text = "Mixed"
}

import Foundation

// What Merge Down may take (Photoshop ⌘E).
//
// Merging bakes everything it takes into ONE still picture. That is right for
// two pictures, a picture and a title, a shape and its shadow; it is never
// right for anything with time, because a still has none: merging a title into
// the recording under it turned the clip into a frame and emptied the timeline
// (task `command-e-on-a-video-never-flattens-the-recordin`, 2026-10-15).

extension Layer {

    /// Whether Merge Down may bake this layer into a still: anything but a
    /// recording, a sound, a layer with an in and an out, or a group holding
    /// one of those.
    public var mayBeMerged: Bool {
        if isClip || occupiesTime { return false }
        if case .sound = content { return false }
        return group?.children.allSatisfy(\.mayBeMerged) ?? true
    }

    /// Whether these layers may be merged into one: two or more, and every one
    /// of them still.
    public static func canMerge(_ layers: [Layer]) -> Bool {
        layers.count >= 2 && layers.allSatisfy(\.mayBeMerged)
    }
}

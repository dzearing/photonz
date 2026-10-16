import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Merge Down bakes what it merges into ONE still picture, so it may never take
/// a layer with time (task `command-e-on-a-video-never-flattens-the-recordin`).
///
/// Written before the rule. On 2026-10-15 a title typed over the sample
/// recording and merged with ⌘E took the recording with it: the timeline went
/// empty and the clip was a still until undo.
struct MergeNeverTakesTimeTests {

    private let frame = CGRect(x: 0, y: 0, width: 200, height: 100)

    private func picture(_ name: String) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    private func title(_ name: String) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame)
    }

    private func clip() -> Layer {
        var layer = picture("Recording")
        layer.movie = MovieRef(pixelSize: frame.size, durationMS: 12_000)
        layer.time = LayerTime(inMS: 0, outMS: 12_000, sourceLengthMS: 12_000)
        return layer
    }

    @Test func twoStillLayersMergeAsBefore() {
        #expect(Layer.canMerge([picture("Background"), title("Hello")]))
    }

    @Test func aClipIsNeverMerged() {
        #expect(!Layer.canMerge([clip(), title("Shipping today")]))
        #expect(!clip().mayBeMerged)
    }

    @Test func aClipWithNoInOrOutIsStillNeverMerged() {
        var recording = clip()
        recording.time = nil
        #expect(!recording.mayBeMerged)
    }

    @Test func aTitleWithAnInAndAnOutIsNeverMerged() {
        var timed = title("Lower third")
        timed.time = LayerTime(inMS: 1_000, outMS: 4_000)
        #expect(!Layer.canMerge([picture("Background"), timed]))
    }

    @Test func aSoundIsNeverMerged() {
        let sound = Layer(name: "Music", content: .sound(SoundRef(durationMS: 10_000)), frame: .zero)
        #expect(!sound.mayBeMerged)
    }

    @Test func aGroupHoldingAClipIsNeverMerged() {
        let group = Layer(name: "Screen", content: .group(GroupContent(children: [clip()])), frame: frame)
        #expect(!Layer.canMerge([picture("Background"), group]))
    }

    @Test func aGroupOfStillLayersMerges() {
        let group = Layer(name: "Screen", content: .group(GroupContent(children: [title("A")])), frame: frame)
        #expect(Layer.canMerge([picture("Background"), group]))
    }

    @Test func fewerThanTwoLayersIsNothingToMerge() {
        #expect(!Layer.canMerge([picture("Background")]))
    }
}

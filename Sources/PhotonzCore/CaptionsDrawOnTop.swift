import Foundation

// **Captions are drawn over everything, wherever their row is listed**
// (`docs/design/mocks/pages/video.html` TIMELINE MODEL).
//
// The mock lists the tracks Title, V1, V2, Captions, Audio: the Captions row
// under the picture, just over the sound. A higher picture track draws in front
// of a lower one, but a Captions track is not a picture track: it is the words
// read over the film, the way Premiere's caption tracks and Resolve's subtitle
// tracks draw over every video track whichever row they sit in. So where the
// Captions row is listed changes nothing about what you see, and a title typed
// after the captions still sits under them.
extension PhotonzDocument {

    /// The top level layers in the order they are drawn, bottom first: the
    /// stack as it is, with every Captions layer lifted to the end, keeping
    /// their own order between them.
    public var drawingOrder: [Layer] {
        let order = Self.drawingIndices(of: layers)
        return order.map { layers[$0] }
    }

    /// The indices of `layers` in the order they are drawn, bottom first. The
    /// stack's own order when no Captions layer has anything over it, which is
    /// every document without captions.
    public static func drawingIndices(of layers: [Layer]) -> [Int] {
        // Already drawn last: nothing to lift.
        var settled = layers.count
        while settled > 0, layers[settled - 1].isCaptionsLayer { settled -= 1 }
        guard layers[..<settled].contains(where: \.isCaptionsLayer) else { return Array(layers.indices) }
        let under = layers.indices.filter { !layers[$0].isCaptionsLayer }
        let over = layers.indices.filter { layers[$0].isCaptionsLayer }
        return under + over
    }
}

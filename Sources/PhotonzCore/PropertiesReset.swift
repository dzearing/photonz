import CoreGraphics
import Foundation

// Reset to Defaults, on the three dots of the Properties header
// (`docs/design/mocks/pages/video.html`, `#propMenu`).
//
// Premiere's Reset on Motion and Opacity, said in this app's model. What goes
// is what the Properties pane is about: every key on every value (a title's
// fade in and a punch-in included, since both ARE keys), the turn, the fade,
// and the volume. What stays is the look (colour, blur, shadow, a flip: the
// Effects list and Copy Look own those) and the place and size the layer holds
// without keys. Keys never write into those, so for a keyed layer that is
// exactly where it stood before anything animated it.

extension Layer {

    /// Whether Reset to Defaults would change anything: something keyed, a
    /// turn, a fade, or a volume away from full.
    public var hasPropertiesToReset: Bool {
        if motions?.isEmpty == false { return true }
        if transform.rotation != 0 { return true }
        if style.opacity != 1 { return true }
        if let level = soundLevel, !level.points.isEmpty || level.gain != AudioLevel.unityGain {
            return true
        }
        return false
    }

    /// This layer with every value in the Properties pane back at its default.
    public func resetToDefaults() -> Layer {
        var reset = self
        reset.motions = nil
        reset.transform.rotation = 0
        reset.style.opacity = 1
        if var level = soundLevel {
            level.clearPoints()
            level.gain = AudioLevel.unityGain
            reset.setSoundLevel(level)
        }
        return reset
    }
}

extension PhotonzDocument {

    /// Reset to Defaults on one layer. False where there is no such layer or
    /// nothing about it would change, so the menu can say so and no empty
    /// step lands in the history.
    @discardableResult
    public mutating func resetPropertiesToDefaults(layerID: UUID) -> Bool {
        guard let layer = layer(id: layerID), layer.hasPropertiesToReset else { return false }
        updateLayer(id: layerID) { $0 = $0.resetToDefaults() }
        return true
    }
}

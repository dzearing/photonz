import AppKit
import PhotonzCore

/// A ring drawn as two strokes of one path: the layer's own stroke is the
/// light casing, and `ink` above it is the line itself. The ink follows the
/// path the canvas hands this layer, and hides with it, so every place that
/// moves or hides the outline keeps working on the one layer it always did.
final class CasedRingLayer: CAShapeLayer {
    let ink = CAShapeLayer()

    override var path: CGPath? {
        didSet { ink.path = path }
    }

    override init() {
        super.init()
        ink.fillColor = nil
        addSublayer(ink)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Dresses the ring in `ring`'s look.
    func apply(_ ring: PickedRing) {
        let inkColor: NSColor = switch ring.ink {
        case .accent: .controlAccentColor
        case .systemBlue: .systemBlue
        }
        ink.strokeColor = inkColor.withAlphaComponent(ring.opacity).cgColor
        ink.lineWidth = ring.width
        ink.lineCap = ring.dash == nil ? .butt : .round
        ink.lineJoin = .miter
        ink.lineDashPattern = ring.dash?.map { NSNumber(value: Double($0)) }
        if let casing = ring.casing {
            strokeColor = CGColor(gray: casing.white, alpha: casing.opacity)
            lineWidth = casing.width
            lineDashPattern = nil
        } else {
            strokeColor = nil
            lineWidth = 0
        }
    }
}

extension CanvasNSView {
    /// Puts the picked ring and the multi-selection rings in the look the
    /// release's switch asks for (`next-solid-picked-ring`), and only when that
    /// changes: the switch can be flipped in Experiments while a window is open.
    func applyPickedRingStyle() {
        let solid = Experiments.shared.solidPickedRingEnabled
        guard pickedRingIsSolid != solid else { return }
        pickedRingIsSolid = solid
        layerOutlineLayer.apply(.picked(solid: solid))
        multiSelectOutlineLayer.apply(.member(solid: solid))
    }
}

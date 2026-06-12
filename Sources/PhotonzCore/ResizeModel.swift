import CoreGraphics
import Foundation

/// State machine behind the resize dialog: pixel/percent units, aspect lock,
/// uniform presets. Field values live in the current unit; `targetSize` is
/// always whole pixels.
public struct ResizeModel: Equatable, Sendable {
    public enum Unit: String, CaseIterable, Hashable, Sendable {
        case pixels
        case percent

        public var label: String {
            switch self {
            case .pixels: "px"
            case .percent: "%"
            }
        }
    }

    public let originalSize: CGSize
    public private(set) var unit: Unit = .pixels
    public private(set) var lockAspect = true
    /// Width/height in the current unit (pixels or percent of original).
    public private(set) var width: CGFloat
    public private(set) var height: CGFloat

    public init(originalSize: CGSize) {
        self.originalSize = originalSize
        self.width = originalSize.width
        self.height = originalSize.height
    }

    // MARK: - Edits

    public mutating func setWidth(_ value: CGFloat) {
        width = value
        if lockAspect { height = crossValue(from: value, alongWidth: true) }
    }

    public mutating func setHeight(_ value: CGFloat) {
        height = value
        if lockAspect { width = crossValue(from: value, alongWidth: false) }
    }

    /// Re-locking snaps height to follow the current width.
    public mutating func setLockAspect(_ locked: Bool) {
        lockAspect = locked
        if locked { height = crossValue(from: width, alongWidth: true) }
    }

    /// Converts the displayed fields; the target size is unchanged.
    public mutating func setUnit(_ newUnit: Unit) {
        guard newUnit != unit, originalSize.width > 0, originalSize.height > 0 else {
            unit = newUnit
            return
        }
        switch newUnit {
        case .percent:
            width = width / originalSize.width * 100
            height = height / originalSize.height * 100
        case .pixels:
            width = width / 100 * originalSize.width
            height = height / 100 * originalSize.height
        }
        unit = newUnit
    }

    /// Uniform preset (50%, @2x→@1x, …): switches to percent and sets both
    /// fields regardless of the aspect lock.
    public mutating func applyPercent(_ percent: CGFloat) {
        unit = .percent
        width = percent
        height = percent
    }

    // MARK: - Output

    /// The size `PhotonzDocument.resize(to:)` should receive — whole pixels,
    /// at least 1×1 (when the fields are valid).
    public var targetSize: CGSize {
        let s = rawTargetSize
        return CGSize(width: max(1, s.width.rounded()), height: max(1, s.height.rounded()))
    }

    public var isValid: Bool {
        rawTargetSize.width > 0 && rawTargetSize.height > 0
    }

    public var isIdentity: Bool {
        targetSize == CGSize(width: originalSize.width.rounded(),
                             height: originalSize.height.rounded())
    }

    private var rawTargetSize: CGSize {
        switch unit {
        case .pixels:
            CGSize(width: width, height: height)
        case .percent:
            CGSize(width: width / 100 * originalSize.width,
                   height: height / 100 * originalSize.height)
        }
    }

    /// The other field's value preserving the original aspect ratio.
    private func crossValue(from value: CGFloat, alongWidth: Bool) -> CGFloat {
        switch unit {
        case .percent:
            value // percent fields match exactly when locked
        case .pixels:
            originalSize.width > 0 && originalSize.height > 0
                ? (alongWidth ? value * originalSize.height / originalSize.width
                              : value * originalSize.width / originalSize.height)
                : value
        }
    }
}

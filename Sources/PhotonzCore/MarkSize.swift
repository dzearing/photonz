// S, M and L for a redline mark: an arrow's or a measurement's chip type size and padding, and an arrow's line weight (markup.md section 7).

import CoreGraphics

/// How big a mark is drawn, picked from three rather than typed.
///
/// It is not stored. A chip whose words are at one of the three sizes IS that
/// size, and one typed at any other size is none of them, so an arrow or a
/// measurement from before there was a Size opens reading M without a byte of
/// it changing. The specimen's 10.5, 12 and 14 points are ratios against the
/// size the app has always drawn a chip at (M).
public enum MarkSize: String, CaseIterable, Codable, Sendable {
    case small, medium, large

    /// The segment's own letter.
    public var title: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }

    /// The right-click submenu's name.
    public static let menuTitle = "Chip Size"

    /// The word, for a tip, a menu row and a screen reader.
    public var name: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// The chip's type size in the design system's specimen.
    public var specimenPoints: CGFloat {
        switch self {
        case .small: 10.5
        case .medium: 12
        case .large: 14
        }
    }

    /// The chip's type size against M's. Padding is proportional to the type,
    /// so it scales with it.
    public var typeScale: CGFloat { specimenPoints / MarkSize.medium.specimenPoints }

    /// An arrow's line weight at this size, unless Thickness was set by hand.
    /// M is the weight every arrow has always been drawn at.
    public var arrowThickness: CGFloat {
        switch self {
        case .small: AnnotationContent.defaultStrokeWidth - 1
        case .medium: AnnotationContent.defaultStrokeWidth
        case .large: AnnotationContent.defaultStrokeWidth + 1
        }
    }

    /// The size a chip drawn at `scale` of M's type is, if it is one of the
    /// three.
    public static func matching(scale: CGFloat) -> MarkSize? {
        allCases.first { abs($0.typeScale - scale) < 0.002 }
    }
}

extension AnnotationContent {

    /// The arrow's Size, read off its chip's type; nil at a size typed by hand.
    public var markSize: MarkSize? {
        MarkSize.matching(scale: captionFontSize / Self.captionFontSizeDefault)
    }

    /// Whether the line's weight is still Size's: the weight the lit size
    /// draws, or with no size lit, any of the three.
    public var thicknessFollowsSize: Bool {
        if let size = markSize { return abs(strokeWidth - size.arrowThickness) < 0.01 }
        return MarkSize.allCases.contains { abs(strokeWidth - $0.arrowThickness) < 0.01 }
    }

    /// Whether Head Size was set by hand, away from the head Size draws.
    public var headSizeByHand: Bool {
        abs(arrowheadScale - AnnotationStyles.defaultArrowheadScale) > 0.001
    }

    /// Whether the head was painted apart from the line.
    public var headByHand: Bool { headPaint != paint }

    /// Whether the line wears something the one Color cannot say (a ramp).
    public var lineByHand: Bool { paint.kind != .solid }

    /// The chip's type and padding at `size`, and the line's weight unless it
    /// was set by hand. Head Size is a multiple of the line, so it follows.
    public mutating func applyMarkSize(_ size: MarkSize) {
        let follows = thicknessFollowsSize
        captionFontSize = Self.captionFontSizeDefault * size.typeScale
        if follows { strokeWidth = size.arrowThickness }
    }

    /// Thickness back to what Size draws.
    public mutating func resetThicknessToSize() {
        strokeWidth = (markSize ?? .medium).arrowThickness
    }

    /// Head Size back to what Size draws.
    public mutating func resetHeadSize() {
        arrowheadScale = AnnotationStyles.defaultArrowheadScale
    }

    /// The head back on the line's colour, following it again.
    public mutating func resetHeadToLine() { headPaint = paint }
}

extension MeasureContent {

    /// The measurement's Size, read off its chip's scale; nil at a size typed
    /// by hand.
    public var markSize: MarkSize? { MarkSize.matching(scale: labelScale) }

    /// The chip's type and padding at `size`. The caliper keeps its weight: a
    /// redline's hairline is a measurement of its own and stays one pixel.
    public mutating func applyMarkSize(_ size: MarkSize) {
        labelScale = size.typeScale
    }
}

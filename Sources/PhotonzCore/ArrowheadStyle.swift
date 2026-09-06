import CoreGraphics
import Foundation

/// What an arrow ends in. Every arrow used to end in the same solid triangle;
/// a redline often wants something quieter — a fine open head, a dot marking a
/// point rather than pointing at it, or no ornament at all so the label does
/// the talking.
///
/// Two of these are POINTERS: their tip sits exactly on the point the arrow
/// marks. Two are MARKERS: their centre sits on it, so they reach past it and
/// the layer frame has to make room (`AnnotationContent.renderPadding`). The
/// last one draws nothing.
public enum ArrowheadStyle: String, CaseIterable, Codable, Hashable, Sendable {
    /// The filled triangle every arrow had before there was a choice.
    case triangle
    /// The same triangle's outline, opened up: two fine strokes meeting at the tip.
    case open
    /// A filled circle centred on the point.
    case dot
    /// The same circle as an outline, so what it marks shows through.
    case hollowDot
    /// No ending at all: a leader line, whose caption is the point of it.
    case plain

    /// What a new arrow ends in, and what an arrow saved before endings existed
    /// opens with.
    public static let standard: ArrowheadStyle = .triangle

    /// The picker shows glyphs, not words; this is what the tooltip and
    /// VoiceOver say.
    public var title: String {
        switch self {
        case .triangle: "Solid head"
        case .open: "Open head"
        case .dot: "Solid dot"
        case .hollowDot: "Hollow dot"
        case .plain: "Plain line"
        }
    }

    /// Whether the ending is a circle centred on the point (rather than a
    /// pointer whose tip lands on it).
    public var isRound: Bool { self == .dot || self == .hollowDot }

    /// Whether the ending is drawn as a line rather than filled in. An outline
    /// reaches half its own stroke further than its path does, which is what
    /// the frame has to know.
    public var isOutlined: Bool { self == .open || self == .hollowDot }
}

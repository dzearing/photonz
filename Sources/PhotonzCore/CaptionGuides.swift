import CoreGraphics
import Foundation

// What the captions mock draws round the captions rather than in them
// (`docs/design/mocks/pages/video-captions.html`): the safe-area guides over
// the picture, the AUTO · EN badge at its top, and the bar over the Captions
// track. None of it is ever rendered into the film.

/// **Safe areas**: the broadcast guides that keep words off the crop. Action
/// safe is the outer one, 93% of the picture; title safe is the inner one,
/// 90%, and a fresh Captions layer lands inside it.
public enum SafeAreaGuide: String, CaseIterable, Sendable {
    /// Outer first, the order they are drawn.
    case action
    case title

    /// The share of the picture's width and height the guide holds.
    public var share: CGFloat {
        switch self {
        case .action: 0.93
        case .title: 0.90
        }
    }

    /// The mock's slab on the guide.
    public var label: String {
        switch self {
        case .action: "Action safe · 93%"
        case .title: "Title safe · 90%"
        }
    }

    /// The guide on a picture this size, centred, top-left origin.
    public func rect(in size: CGSize) -> CGRect {
        let width = size.width * share, height = size.height * share
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                      width: width, height: height)
    }
}

/// **AUTO · EN**: the badge on the picture while its captions are the ones
/// the app heard. Written in the mock's case; the badge sets it in capitals.
public enum CaptionBadge {

    /// `Auto · en` for `en-US`.
    public static func text(language: String) -> String {
        let code = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return code.isEmpty ? "Auto" : "Auto · \(code.lowercased())"
    }
}

/// **Lower-third**: the small tag on the top left edge of a lower third's
/// plate (`.l3badge` in the mock), so the style reads at a glance. Canvas
/// chrome sized in screen points, like the mock's 8.5px tag: it never grows
/// with the zoom and is never drawn into the film.
public enum LowerThirdTag {

    public static let label = "Lower-third"

    /// How far the tag's top sits above the plate's top, in screen points
    /// (`top:-11px`), so it rides the plate's edge rather than covering words.
    public static let lift: CGFloat = 11

    /// Only a Captions layer in the Lower third look wears the tag.
    public static func isWorn(by look: CaptionLook?) -> Bool {
        look?.sitsLowLeft == true
    }

    /// The tag's top left corner for a plate drawn at `plate`, both in screen
    /// points: on the plate's left edge, lifted by `lift`.
    public static func origin(onPlate plate: CGRect) -> CGPoint {
        CGPoint(x: plate.minX, y: plate.minY - lift)
    }
}

/// **Caption track**: the bar over the Captions track, with its words and
/// readouts (`.tlbar` in the mock).
public enum CaptionTrackBar {

    public static let title = "Caption track"
    /// Every caption the app writes is timed word by word.
    public static let mode = "auto · word level"
    public static let activeWord = "Active word"

    /// `1.30s / 6.00s`: the playhead over the length.
    public static func time(atMS ms: Int, ofMS length: Int) -> String {
        String(format: "%.2fs / %.2fs", Double(max(0, ms)) / 1000, Double(max(0, length)) / 1000)
    }

    /// The word being said at `ms`, or nil between words.
    public static func word(atMS ms: Int, in words: [TranscribedWord]) -> TranscribedWord? {
        words.first { $0.startMS <= ms && ms < $0.endMS }
    }
}

extension PhotonzDocument {

    /// **Reset**: a Captions layer back in the standard look and the box a
    /// fresh one lands in. The words and their times are not touched.
    public mutating func resetCaptions(_ id: UUID) {
        guard layer(id: id)?.isCaptionsLayer == true else { return }
        applyCaptionLook(.standard, toCaptions: id)
        let size = canvasSize
        let box = CaptionLayers.defaultBox(in: size, fontSize: CaptionLook.standard.resolvedFontSize(in: size))
        updateLayer(id: id) { $0 = $0.reboxingCaptions(to: box) }
    }
}

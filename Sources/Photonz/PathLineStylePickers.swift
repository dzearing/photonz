import AppKit
import PhotonzCore
import SwiftUI

/// The three things a path can say about its line, under the Outline row in
/// Appearance: whether it is solid, dashed or dotted, what its ends look like,
/// and how its corners turn (`PhotonzCore/PathLineStyle.swift`).
///
/// Pictures rather than words, the bargain the arrow's Ending row already
/// makes: three shapes side by side are compared in one glance, where three
/// words have to be read one at a time. The picked one is named in words beside
/// the caption, which is what you read three minutes later to remember which
/// one you are looking at.
///
/// Each picture is DRAWN with the setting it stands for — a round end is a real
/// round end, a dashed line is really dashed — so the control cannot drift away
/// from what the canvas does.

// MARK: - The pictures

/// A short piece of line, drawn exactly as the setting would draw it.
enum PathLineStyleGlyph {

    /// How big each picture is, in points. Wide enough for two dashes and a
    /// gap, short enough that three of them fit a panel row.
    private static let size = CGSize(width: 22, height: 14)

    /// A stub of a thick line with one end shaped. Thick and short on purpose:
    /// the whole difference between the three is what happens in the last half
    /// width, so a hairline would show nothing at all.
    static func end(_ end: PathLineEnd, named: String) -> Image {
        draw(named: named) { context in
            context.setLineCap(end == .flat ? .butt : (end == .round ? .round : .square))
            context.setLineWidth(8)
            context.move(to: CGPoint(x: 3, y: 7))
            context.addLine(to: CGPoint(x: 14, y: 7))
            context.strokePath()
        }
    }

    /// A right-angled corner, turned the way the setting turns it.
    ///
    /// A right angle rather than a sharp V, because the three answers differ by
    /// exactly one line width at the outside of the bend and a right angle is
    /// the widest that difference ever gets on a picture this size: a carried
    /// point is square, a sliced one is chamfered, a round one is an arc.
    static func corner(_ corner: PathLineCorner, named: String) -> Image {
        draw(named: named) { context in
            context.setLineJoin(corner == .sharp ? .miter : (corner == .round ? .round : .bevel))
            context.setMiterLimit(pathMiterLimit)
            context.setLineCap(.butt)
            context.setLineWidth(5)
            context.move(to: CGPoint(x: 5, y: 2))
            context.addLine(to: CGPoint(x: 5, y: 10))
            context.addLine(to: CGPoint(x: 19, y: 10))
            context.strokePath()
        }
    }

    /// The line itself, solid or broken up.
    static func pattern(_ pattern: PathLinePattern, named: String) -> Image {
        draw(named: named) { context in
            context.setLineCap(.round)
            context.setLineWidth(3)
            if let dash = pattern.pattern(forWidth: 3) { context.setLineDash(phase: 0, lengths: dash) }
            context.move(to: CGPoint(x: 2, y: 7))
            context.addLine(to: CGPoint(x: 20, y: 7))
            context.strokePath()
        }
    }

    /// One picture, in the colour the panel's own type is drawn in, carrying
    /// the SETTING's name rather than a symbol's.
    ///
    /// A segment of a segmented picker takes its name from the picture on it,
    /// which is what a screen reader reads out and what a scripted walk presses
    /// it by, so the name is set on the image itself. (A SwiftUI
    /// `.accessibilityLabel` on the Image does not reach the segment.)
    private static func draw(named: String, _ paint: @escaping (CGContext) -> Void) -> Image {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            context.setStrokeColor(NSColor.labelColor.cgColor)
            paint(context)
            return true
        }
        // Follows the panel's own tint the way a symbol does, so the picked
        // segment's picture is legible against its highlight.
        image.isTemplate = true
        image.accessibilityDescription = named
        return Image(nsImage: image)
    }
}

// MARK: - The three rows

/// One picker: a caption, the word for what is picked, and the pictures.
///
/// `selection` is optional so a mixture of picked paths shows nothing chosen
/// rather than lying about one of them; picking then sets all of them, which is
/// what the word Mixed is there to offer.
struct PathLineStyleRow<Value: Hashable & CaseIterable & Sendable>: View
where Value.AllCases: RandomAccessCollection {
    let label: String
    let reading: StyleReading<Value>
    let title: (Value) -> String
    let glyph: (Value) -> Image
    let help: (Value) -> String
    let pick: (Value) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if reading.isMixed {
                    MixedWord()
                } else if let value = reading.value {
                    Text(title(value)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Picker(label, selection: Binding<Value?>(
                get: { reading.isMixed ? nil : reading.value },
                set: { if let value = $0 { pick(value) } })) {
                ForEach(Array(Value.allCases), id: \.self) { value in
                    glyph(value).tag(Value?.some(value))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .segmentToolTips(Array(Value.allCases).map(title),
                             fallback: reading.isMixed
                             ? "The picked shapes differ. Choosing one sets all of them."
                             : (reading.value.map(help) ?? ""))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .playtestField(label)
    }
}

/// All three, in the order a person works through them: what the line is made
/// of, then what its ends look like once there are ends to see, then how it
/// turns a corner.
struct PathLineStyleSettings: View {
    @Environment(EditorState.self) private var editorState
    /// The picked paths this Outline row speaks for.
    let selection: PathLineStyleSelection

    var body: some View {
        // Nothing to say about a line that is not there. A path with its
        // outline switched off shows no colour and no thickness either, and a
        // picker over nothing is a control that cannot act.
        if !selection.isEmpty, selection.hasALine {
            let ids = selection.layerIDs
            PathLineStyleRow(label: "Pattern",
                             reading: selection.reading(\.linePattern),
                             title: \.title,
                             glyph: { PathLineStyleGlyph.pattern($0, named: $0.title) },
                             help: { Self.patternHelp($0) },
                             pick: { editorState.setPathLinePattern(ids: ids, $0) })
            // Only where there are ends to see: an open path has two, and a
            // dashed one has two on every dash. A closed solid shape has none,
            // so it is not asked (`PathContent.showsLineEnds`).
            if selection.showsLineEnds {
                PathLineStyleRow(label: "Ends",
                                 reading: selection.reading(\.lineEnd),
                                 title: \.title,
                                 glyph: { PathLineStyleGlyph.end($0, named: $0.title) },
                                 help: { Self.endHelp($0) },
                                 pick: { editorState.setPathLineEnd(ids: ids, $0) })
            }
            PathLineStyleRow(label: "Corners",
                             reading: selection.reading(\.lineCorner),
                             title: \.title,
                             glyph: { PathLineStyleGlyph.corner($0, named: $0.title) },
                             help: { Self.cornerHelp($0) },
                             pick: { editorState.setPathLineCorner(ids: ids, $0) })
        }
    }

    private static func patternHelp(_ pattern: PathLinePattern) -> String {
        switch pattern {
        case .solid: return "An unbroken line"
        case .dashed: return "Broken into dashes, which grow with the thickness"
        case .dotted: return "Broken into dots, which grow with the thickness"
        }
    }

    private static func endHelp(_ end: PathLineEnd) -> String {
        switch end {
        case .flat: return "The line stops dead on its last point"
        case .round: return "A half circle past the last point"
        case .square: return "A half square past the last point"
        }
    }

    private static func cornerHelp(_ corner: PathLineCorner) -> String {
        switch corner {
        case .sharp: return "Carried out to a point, the way two rulers cross"
        case .round: return "Turned through an arc, which is what makes an icon set look soft"
        case .flat: return "The point sliced straight off"
        }
    }
}



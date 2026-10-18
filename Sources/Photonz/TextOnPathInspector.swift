import PhotonzCore
import SwiftUI

/// Start, in the Text section of words set along a curve: how far along the
/// curve the first letter stands, as a percent of its length. Keyed, it is
/// what makes the words travel along the curve (`TextOnPath.swift`).
///
/// A number box named inside itself like Tracking and Leading above it, with
/// the key diamond before it, because it is one number a person types or
/// steps and may key.
struct TextPathStartRow: View {
    @Environment(EditorState.self) private var editorState
    let start: Double

    private static let title = "Start"
    private var keyed: KeyedProperty { .motion(.pathStart) }
    /// Keys need one picked layer in a document with time, like every other
    /// diamond in the panel (`EditorState.keyLayer`).
    private var keyable: Bool {
        guard let layer = editorState.keyLayer else { return false }
        return editorState.textPathStartLayerID == layer.id
    }

    private static func spelled(_ value: Double) -> String {
        String(MotionProperty.pathStart.format(.number(value)).dropLast())
    }

    var body: some View {
        // The box carries its own name inside it, the way Tracking and
        // Leading above it do; the diamond leads it where Start can be keyed.
        HStack(spacing: 6) {
            if keyable {
                KeyDiamondButton(property: keyed, state: editorState.keyDiamond(keyed), side: 12)
            }
            PanelNumberField(
                showing: .number(Self.spelled(start)),
                label: Self.title,
                identity: "path-start-\(editorState.textPathStartLayerID?.uuidString ?? "")",
                suffix: "%",
                width: .flexible(least: 60),
                floor: CGFloat(TextOnPath.startRange.lowerBound),
                ceiling: CGFloat(TextOnPath.startRange.upperBound),
                help: "Where the words start along the curve",
                playtest: ("Path start", "Text"),
                stepEach: { direction, coarse in
                    editorState.setTextPathStart(start + Double(direction) * (coarse ? 10 : 1))
                },
                spell: { Self.spelled(Double($0)) },
                look: .well,
                land: { typed in
                    editorState.setTextPathStart(Double(typed))
                    return nil
                })
                .frame(maxWidth: .infinity)
                .panelReadout(Self.spelled(start))
                .playtestField("Path start Value")
        }
        // Named for the walks as the Path start, since a panel has other Starts.
        .playtestField("Path start")
    }
}

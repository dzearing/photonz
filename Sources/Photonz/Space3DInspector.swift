import PhotonzCore
import SwiftUI

/// **3D**: how the picked layers are turned and placed in space
/// (Next, `next-turn-in-depth`; `video-depth.html`, `#dpProps`, the 3D section).
///
/// One label and one value per row, each with the key diamond every keyable
/// row has: Rotation X, Rotation Y, Depth, and Pivot depth once a layer is
/// actually turned, because on a flat layer it has nothing to do. The rows
/// speak for every picked layer, and say Mixed where they differ. Up and down
/// step by one, Shift by ten, from each layer's own value.
struct Space3DInspector: View {
    @Environment(EditorState.self) private var editorState

    /// What the section header's question mark says: the mock's own tip.
    static let sectionHelp = "Rotation X tips the top away or toward you. Rotation Y swings the sides. "
        + "Depth moves it away from or toward the camera."

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SpaceValueRow(property: .rotationX)
            SpaceValueRow(property: .rotationY)
            SpaceValueRow(property: .depth)
            if editorState.spaceSelectionIsTurned {
                SpaceValueRow(property: .pivotDepth)
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
    }
}

/// One 3D row: diamond, name, value.
private struct SpaceValueRow: View {
    @Environment(EditorState.self) private var editorState
    let property: MotionProperty

    private var title: String { property.title(effect: 0, of: 1) }
    private var keyed: KeyedProperty { .motion(property) }
    /// Keys need one picked layer in a document with time, the same as every
    /// other diamond in the panel (`EditorState.keyLayer`).
    private var keyable: Bool {
        guard let layer = editorState.keyLayer else { return false }
        return editorState.spaceTargetIDs == [layer.id]
    }

    /// What the box shows, as words a walk reads back.
    private var valueText: String {
        editorState.spaceValue(property).map(SpaceRowText.text) ?? MixedValue.text
    }

    var body: some View {
        HStack(spacing: 4) {
            if keyable {
                KeyDiamondButton(property: keyed, state: editorState.keyDiamond(keyed))
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
            PanelNumberField(
                showing: editorState.spaceValue(property).map { .number(SpaceRowText.text($0)) }
                    ?? .standIn(MixedValue.text),
                label: title,
                identity: "space-\(editorState.spaceTargetIDs.map(\.uuidString).joined())-\(title)",
                suffix: property.isLength ? "px" : "°",
                width: .flexible(least: 60),
                playtest: (title, "3D"),
                stepEach: { direction, coarse in
                    editorState.nudgeSpaceValue(property, by: Double(direction) * (coarse ? 10 : 1))
                },
                spell: { SpaceRowText.text(Double($0)) },
                look: .well,
                land: { typed in
                    editorState.setSpaceValue(property, Double(typed))
                    return nil
                })
                .frame(maxWidth: .infinity)
                .panelReadout(valueText)
                .playtestField("3D \(title) Value")
        }
        .frame(minHeight: 24)
        .playtestField("3D \(title)")
        .contextMenu {
            if keyable {
                Button("Add Key Here") { editorState.addKeyHere(keyed) }
                    .disabled(editorState.keyDiamond(keyed) == .onKey)
                Button("Remove Key Here") { editorState.removeKeyHere(keyed) }
                    .disabled(editorState.keyDiamond(keyed) != .onKey)
                Divider()
            }
            Button("Reset 3D Rotation") { editorState.resetSpaceRotation() }
                .disabled(!editorState.canResetSpaceRotation)
        }
    }
}

/// How a 3D or camera row spells its number: one decimal at most, a whole
/// number staying whole, the way Premiere reads a value between keys.
enum SpaceRowText {
    static func text(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }
}

/// **Camera**: the one camera every frame is seen through, a setting of the
/// frame (decision card `...-where-does-the-camera-live`, option A; mock
/// `video-depth.html`, "Camera A"). Click empty canvas and the panel shows it.
struct CameraInspector: View {
    @Environment(EditorState.self) private var editorState

    static let sectionHelp = "Perspective is how strong the depth looks. Camera depth pushes in, "
        + "Camera X and Y move across. Each can be keyed like any value."

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(MotionProperty.cameraProperties, id: \.self) { property in
                CameraValueRow(property: property)
            }
            // How it travels between two keys: the one Curve row a layer's
            // Between the keys has (`CurveRow`), for every camera value moving
            // at the playhead (`camera-keys-ease-in-and-out-like-every-other-key`).
            if editorState.cameraHasStretch {
                CurveRow(current: editorState.cameraStretchCurve,
                         help: "How fast the camera travels between these two keys") {
                    editorState.curveCameraStretch($0)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .contextMenu {
            Button("Reset Camera") { editorState.resetCamera() }
                .disabled(!editorState.canResetCamera)
        }
    }
}

private struct CameraValueRow: View {
    @Environment(EditorState.self) private var editorState
    let property: MotionProperty
    @State private var isHovering = false

    private var title: String { property.title(effect: 0, of: 1) }

    var body: some View {
        HStack(spacing: 4) {
            if editorState.documentHasTime {
                let state = editorState.cameraKeyDiamond(property)
                Button {
                    editorState.toggleCameraKey(property)
                } label: {
                    VideoKit.KeyDiamond(state: kitState(state), isHovering: isHovering)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .playtestHover("Key \(title)") { isHovering = $0 }
                .panelHelp(help(state))
                .accessibilityLabel(help(state))
                .playtestControl("Key", detail: title)
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
            PanelNumberField(
                showing: editorState.cameraValue(property).map { .number(SpaceRowText.text($0)) } ?? .nothing,
                label: title,
                suffix: property == .cameraPerspective ? "°" : "px",
                width: .flexible(least: 60),
                floor: property == .cameraPerspective ? 0 : nil,
                ceiling: property == .cameraPerspective ? CGFloat(SceneCamera.widestPerspective) : nil,
                playtest: (title, "Camera"),
                spell: { SpaceRowText.text(Double($0)) },
                look: .well,
                land: { typed in
                    editorState.setCameraValue(property, Double(typed))
                    return nil
                })
                .frame(maxWidth: .infinity)
                .panelReadout(editorState.cameraValue(property).map(SpaceRowText.text) ?? "")
                .playtestField("\(title) Value")
        }
        .frame(minHeight: 24)
        .playtestField(title)
    }

    private func kitState(_ state: KeyDiamond) -> VideoKit.KeyState {
        switch state {
        case .dormant: .dormant
        case .betweenKeys: .armed
        case .onKey: .onKey
        }
    }

    private func help(_ state: KeyDiamond) -> String {
        switch state {
        case .dormant: "Animate \(title.lowercased()) from here"
        case .betweenKeys: "Add a \(title.lowercased()) key here"
        case .onKey: "Remove this \(title.lowercased()) key"
        }
    }
}

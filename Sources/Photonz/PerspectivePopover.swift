import AppKit
import PhotonzCore
import SwiftUI

// The camera's perspective, from the picked layer in 3D and from the tool
// bar's Info popover (Next, `next-transform-modes`; the user's approved
// prototype `docs/design/mocks/pages/selection-transform.html`, its pill and
// `.st-pp` popover).
//
// Perspective belongs to the document's one camera (`SceneCamera`), so every
// layer turned in 3D changes with it. In 3D a pill beside the mode chip shows
// it (`CanvasSelectionGrips`); a click hangs this popover under the pill with
// None, Subtle, Normal, Strong and a slider. The Info popover carries the same
// controls. A preset is one undo step; the slider previews while it is held
// and lands in one.

extension EditorState {

    /// A scrub or the slider in the hand: every 3D layer follows, nothing is
    /// recorded.
    func previewCameraPerspective(_ degrees: Double) {
        guard var doc = document else { return }
        doc.setCameraValue(.cameraPerspective, degrees, atDocumentTimeMS: documentTimeMS, ease: newKeyEaseToWrite)
        cameraPerspectivePreview = degrees
        submit(doc)
    }

    /// ...and let go: ONE undo step. Landing where it started is a no-op that
    /// puts the picture back (how Escape cancels a scrub).
    func commitCameraPerspective(from start: Double, to degrees: Double) {
        cameraPerspectivePreview = nil
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        perform { $0.setCameraValue(.cameraPerspective, degrees, atDocumentTimeMS: time, ease: ease) }
    }

    /// A preset: one undo step.
    func setCameraPerspective(_ degrees: Double) {
        commitCameraPerspective(from: shownCameraPerspective, to: degrees)
    }

    /// The camera's perspective at the playhead, following a slider or a
    /// scrub in flight.
    var shownCameraPerspective: Double {
        cameraPerspectivePreview ?? cameraValue(.cameraPerspective) ?? SceneCamera.defaultPerspective
    }

    /// The perspective pill asks its popover open under it (its frame in the
    /// canvas view's points), moved with it, or closed.
    func placePerspectivePopover(_ anchor: CGRect?) {
        guard perspectivePopoverAnchor != anchor else { return }
        perspectivePopoverAnchor = anchor
    }
}

/// None, Subtle, Normal, Strong and a slider, under a header that says it is
/// the camera's: the popover under the pill and the Info popover both.
struct PerspectiveControls: View {
    @Environment(EditorState.self) private var editorState
    /// What a walk knows these controls by (`in` on a `press`).
    let detail: String
    /// The slider's value when the hand took it, so letting go is one step.
    @State private var heldFrom: Double?

    /// The header's words: the camera's, so every 3D layer changes.
    static let title = "Perspective"
    static let scope = "All 3D layers"

    var body: some View {
        let shown = editorState.shownCameraPerspective
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(Self.title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 4)
                Text(Self.scope)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
            .overlay(alignment: .leading) {
                Color.clear.frame(width: 2, height: 2)
                    .panelReadout(PerspectiveControl.label(shown))
                    .playtestField("\(detail) Value")
            }
            HStack(spacing: 3) {
                ForEach(PerspectiveControl.presets, id: \.name) { preset in
                    let on = PerspectiveControl.preset(matching: shown) == preset
                    Button(preset.name) { editorState.setCameraPerspective(preset.degrees) }
                        .buttonStyle(PerspectivePresetStyle(isOn: on))
                        .help(preset.degrees == 0 ? "No perspective" : "\(Int(preset.degrees))°")
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .playtestControl(preset.name, detail: detail)
                }
            }
            Slider(value: Binding(
                get: { min(max(shown, PerspectiveControl.range.lowerBound), PerspectiveControl.range.upperBound) },
                set: { value in
                    let degrees = value.rounded()
                    if heldFrom != nil {
                        editorState.previewCameraPerspective(degrees)
                    } else {
                        editorState.setCameraPerspective(degrees)
                    }
                }),
                in: PerspectiveControl.range,
                onEditingChanged: { editing in
                    if editing {
                        heldFrom = editorState.shownCameraPerspective
                    } else if let from = heldFrom {
                        heldFrom = nil
                        editorState.commitCameraPerspective(from: from, to: editorState.shownCameraPerspective)
                    }
                })
                .controlSize(.small)
                .accessibilityLabel("Perspective")
                .playtestControl("Slider", detail: detail)
        }
    }
}

/// A preset: a small plate, the accent with white words when it is the
/// camera's value (the prototype's `.st-pp .p button`).
private struct PerspectivePresetStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isOn ? AnyShapeStyle(Color.accentColor)
                           : AnyShapeStyle(.primary.opacity(configuration.isPressed ? 0.2 : 0.12))))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The popover under the perspective pill: the tool bar's glass, like the
/// Info popover, hung six points under the pill and kept inside the canvas.
struct PerspectivePopover: View {
    @Environment(EditorState.self) private var editorState

    static let width: CGFloat = 220
    static let detail = "Perspective"

    var body: some View {
        GeometryReader { proxy in
            if let anchor = editorState.perspectivePopoverAnchor {
                let corner = Experiments.shared.toolBar.cornerRadius
                PerspectiveControls(detail: Self.detail)
                    .padding(10)
                    .frame(width: Self.width)
                    .glassEffect(.regular, in: .rect(cornerRadius: corner))
                    .contentShape(.rect(cornerRadius: corner))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Perspective")
                    .fixedSize()
                    .alignmentGuide(.leading) { _ in
                        -min(max(anchor.minX, 8), max(8, proxy.size.width - Self.width - 8))
                    }
                    .alignmentGuide(.top) { popover in
                        let below = anchor.maxY + 6
                        // Above the pill where there is no room under it.
                        let y = below + popover.height <= proxy.size.height - 8 ? below
                            : anchor.minY - 6 - popover.height
                        return -max(8, y)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .transition(.opacity)
            }
        }
        .transaction(value: editorState.perspectivePopoverAnchor == nil) { transaction in
            transaction.animation = editorState.perspectivePopoverAnchor == nil ? nil : .easeOut(duration: 0.12)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            editorState.placePerspectivePopover(nil)
        }
    }
}

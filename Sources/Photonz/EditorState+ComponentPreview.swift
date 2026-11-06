import PhotonzCore
import SwiftUI

// Preview: the window trying the page rather than editing it. The rules are
// `ComponentPreview`, in the core; this is where they meet the pointer, the keys
// and the camera. Nothing here reaches `History`: what the canvas draws is worked
// out in `displayDocument` on a value nothing keeps, so leaving has nothing to
// put back but the window's own state.

/// What the canvas tells the editor while the page is being tried, in document
/// points. Nil is off every part of the page.
enum CanvasPreviewEvent {
    case moved(CGPoint?, zoom: CGFloat)
    case down(CGPoint?, zoom: CGFloat)
    case dragged(CGPoint?, zoom: CGFloat)
    case up(CGPoint?, zoom: CGFloat)
    case key(code: UInt16, shift: Bool, repeated: Bool)
}

/// How the window goes back: your selection, your tool and your zoom are as you
/// left them.
struct PreviewReturn {
    var picked: UUID?
    var multiPicked: Set<UUID>
    var groupContext: UUID?
    var tool: Tool
    var camera: (viewport: Viewport?, placed: Viewport?, fitted: Bool)
}

extension EditorState {

    /// The title bar shows the button for a page it can preview, and while
    /// Preview is up whatever the page became, so the way out never goes.
    var showsPreviewButton: Bool { offersPreview || isPreviewing }

    /// Keeps `offersPreview` true to the document, writing only when it moves.
    func notePreviewOffer(_ document: PhotonzDocument) {
        let offers = Experiments.shared.componentPreviewEnabled && document.canPreviewComponents
        if offers != offersPreview { offersPreview = offers }
    }

    func togglePreview() {
        isPreviewing ? leavePreview() : enterPreview()
    }

    func enterPreview() {
        guard offersPreview, !isPreviewing else { return }
        #if PHOTONZ_PLAYTEST
        if let document {
            playtestDocumentBeforePreview = (document, canUndo, canRedo)
        }
        #endif
        if ask.isComposerShown { ask.closeComposer() }
        beforePreview = PreviewReturn(picked: selectedLayerID, multiPicked: multiSelectedLayerIDs,
                                      groupContext: groupContextID, tool: activeTool,
                                      camera: cameraToReturnTo)
        if activeTool != .select { setTool(.select) }
        if !multiSelectedLayerIDs.isEmpty { multiSelectedLayerIDs = [] }
        if selectedLayerID != nil { selectedLayerID = nil }
        previewSession = ComponentPreview()
        previewNote = nil
        withAnimation(.viewEditMode) {
            isPreviewing = true
            refitForViewEditMode()
        }
    }

    func leavePreview() {
        guard isPreviewing else { return }
        let back = beforePreview
        beforePreview = nil
        previewSession = ComponentPreview()
        previewNote = nil
        withAnimation(.viewEditMode) {
            isPreviewing = false
            if let back { returnCamera(back.camera) } else { refitForViewEditMode() }
        }
        if let back {
            if back.tool != activeTool { setTool(back.tool) }
            groupContextID = back.groupContext
            if let picked = back.picked, document?.layer(id: picked) != nil { selectedLayerID = picked }
            let stillThere = back.multiPicked.filter { document?.layer(id: $0) != nil }
            if !stillThere.isEmpty { multiSelectedLayerIDs = stillThere }
        }
        rerender()
    }

    /// A new document in this window: Preview ends with nothing to hand back.
    func forgetPreview() {
        guard isPreviewing else { return }
        isPreviewing = false
        beforePreview = nil
        previewSession = ComponentPreview()
        previewNote = nil
    }

    /// One thing the hand or the keyboard did on the page.
    func previewEvent(_ event: CanvasPreviewEvent) {
        guard isPreviewing, let document else { return }
        let before = previewSession
        var session = before
        func copy(_ point: CGPoint?, _ zoom: CGFloat) -> UUID? {
            point.flatMap { session.copy(at: $0, in: document, zoom: zoom) }
        }
        switch event {
        case .moved(let point, let zoom):
            session.point(at: copy(point, zoom))
        case .down(let point, let zoom):
            let under = copy(point, zoom)
            session.point(at: under)
            session.press(under, in: document)
        case .dragged(let point, let zoom):
            session.drag(over: copy(point, zoom))
        case .up(let point, let zoom):
            let under = copy(point, zoom)
            session.release(over: under, at: point, in: document)
            session.point(at: under)
        case .key(let code, let shift, let repeated):
            switch code {
            case 53: return leavePreview()
            case 48: session.tab(backwards: shift, in: document)
            case 36, 49, 76: if !repeated { session.activateFocus(in: document) }
            default: break
            }
        }
        guard session != before else { return }
        previewSession = session
        let note = session.note(in: document)
        if note != previewNote { previewNote = note }
        rerender()
    }
}

extension CanvasNSView {

    /// Where an event landed, in document points.
    func previewPoint(_ event: NSEvent, _ viewport: Viewport) -> CGPoint? {
        viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil))
    }

    /// Told every pass; acts only when Preview comes or goes. Going in, the
    /// canvas takes the keyboard, because Tab and Esc are the page's now and a
    /// panel field that had it would be gone with the panel.
    func setPreviewing(_ on: Bool) {
        guard on != isPreviewing else { return }
        isPreviewing = on
        refreshComponentChrome()
        guard on else { return }
        window?.makeFirstResponder(self)
        refreshNameLabelHover(at: nil)
        applyGrabCursor(nil)
    }
}

// MARK: - The button

/// Preview in the title bar, to Ask's left. It stays where it is in Preview and
/// fills with the accent, so the second click lands on the same button and the
/// window says which state it is in.
struct PreviewTitlebarButton: View {
    @Environment(EditorState.self) private var editorState

    private static let wordSize: CGFloat = 12
    private static let symbolSize: CGFloat = 9
    private static let spacing: CGFloat = 5
    private static let padding: CGFloat = 10
    static let height: CGFloat = 24

    /// The widest it is drawn, so the title bar's fixed box always holds it.
    /// Measured from the word, never typed in (`AskTitlebarButton.width`).
    @MainActor static let width: CGFloat = {
        let word = (ComponentPreviewCopy.button as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: wordSize, weight: .medium)]).width
        return ceil(symbolSize + spacing + word + padding * 2) + 3
    }()

    var body: some View {
        let on = editorState.isPreviewing
        Button {
            editorState.togglePreview()
        } label: {
            HStack(spacing: Self.spacing) {
                Image(systemName: "play.fill")
                    .font(.system(size: Self.symbolSize, weight: .semibold))
                Text(ComponentPreviewCopy.button)
                    .font(.system(size: Self.wordSize, weight: .medium))
            }
            .fixedSize()
        }
        .buttonStyle(PreviewButtonStyle(isOn: on))
        .focusEffectDisabled()
        .frame(width: Self.width)
        .toolTip(ComponentPreviewCopy.button, key: ComponentPreviewCopy.key, below: true)
        .playtestControl(ComponentPreviewCopy.button,
                         detail: on ? "the title bar's Preview button, on" : "the title bar's Preview button")
        .frame(height: TitlebarPanelToggle.barHeight)
    }
}

/// The mock's small button: a quiet fill at rest, a stronger one under the
/// pointer, and the system's white on the accent while Preview is up.
private struct PreviewButtonStyle: ButtonStyle {
    var isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, isOn: isOn)
    }

    private struct Face: View {
        let configuration: Configuration
        let isOn: Bool
        @State private var hovering = false

        var body: some View {
            let lit = hovering || configuration.isPressed
            configuration.label
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: PreviewTitlebarButton.height)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(Color.accentColor)
                                   : AnyShapeStyle(Color.primary.opacity(lit ? 0.14 : 0.08)))
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .playtestHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

// MARK: - The pill

/// Says the window is in Preview and how to leave, and, under a component whose
/// looks are named some other way, why it does nothing. The one named exception
/// to no status pills on the canvas, the user's own ask of 2026-11-04, kept off
/// the page by the fit (`EditorState.fitObscuredBottom`). It takes no pointer.
struct PreviewPill: View {
    @Environment(EditorState.self) private var editorState

    private static let height: CGFloat = 30
    private static let inset: CGFloat = 16
    /// The strip at the foot of the canvas a fitted page keeps clear.
    static let covers: CGFloat = height + inset + 8

    var body: some View {
        HStack(spacing: 8) {
            Text(ComponentPreviewCopy.button).fontWeight(.semibold)
            Text(ComponentPreviewCopy.leave).foregroundStyle(.secondary)
            if let note = editorState.previewNote {
                Divider().frame(height: 14)
                Text(note).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, Self.inset)
        .allowsHitTesting(false)
        .playtestControl("Preview pill", detail: editorState.previewNote ?? "")
    }
}

import AppKit
import PhotonzCore
import SwiftUI

// The one quiet line in a video window's title bar: the name in bold, then the
// picture size, the length and saved or edited, faint. The video mocks draw it
// centred in the bar (`docs/design/mocks/pages/video.html`, `data-shell`;
// `.wtitle` in the design system: 12.5px, name in ink, the rest dim).
//
// The editor window is `hiddenTitleBar`, so the system draws no title here. The
// line is drawn by the window's own content instead, level with the traffic
// lights, and takes no clicks: the bar still drags the window and nothing new
// is added to press.

/// Sits over the top of the editor, in the title bar's strip.
struct TitlebarDocumentLine: View {
    @Environment(EditorState.self) private var editorState
    /// Full screen takes the title bar away, and the line with it: drawn
    /// anyway, it would sit over the top of the canvas.
    @State private var isFullScreen = false

    /// The strip the line is centred in. Taller than the chip's 28 because
    /// the chip's accessory does not start at the window's top edge and this
    /// does: at 28 the words sat 3pt above the chip and the traffic lights
    /// (measured on a window capture, 2026-09-27).
    static let barHeight: CGFloat = 33
    /// Kept clear at each end, so the line never runs under the mode chip on
    /// the left or the panel toggle on the right. Equal both sides, so the
    /// line stays centred on the window the way a Mac title is.
    static let endClearance: CGFloat = 250

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) {
                if ($0.object as? NSWindow) === editorState.hostWindow { isFullScreen = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) {
                if ($0.object as? NSWindow) === editorState.hostWindow { isFullScreen = false }
            }
    }

    @ViewBuilder private var content: some View {
        if !isFullScreen, let line = editorState.titleLine {
            // Widest first; a narrow window drops the size and length before it
            // gives up the name, the way the mock's `.meta` goes first.
            ViewThatFits(in: .horizontal) {
                words(line, details: true)
                words(line, details: false)
                Text(line.name).fontWeight(.semibold).foregroundStyle(VideoKit.Palette.ink)
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 12.5, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Self.endClearance)
            .frame(height: Self.barHeight)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.text)
            .playtestControl(TitlebarDocumentLineCopy.control, detail: line.text)
        }
    }

    private func words(_ line: WindowTitleLine, details: Bool) -> some View {
        var rest = ""
        if details, !line.details.isEmpty { rest += WindowTitleLine.separator + line.details }
        return HStack(spacing: 0) {
            Text(line.name)
                .fontWeight(.semibold)
                .foregroundStyle(VideoKit.Palette.ink)
            Text(rest)
                .foregroundStyle(VideoKit.Palette.dim)
            if let state = line.state {
                // Saved is fainter still; edited takes the warning
                // colour, as `video-captions.html` turns it when you change
                // something.
                Text(WindowTitleLine.separator + state.rawValue)
                    .foregroundStyle(state == .edited ? VideoKit.Palette.warn
                                                      : VideoKit.Palette.faint)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// The name a walk asks for.
enum TitlebarDocumentLineCopy {
    static let control = "Window title"
}

import PhotonzCore
import SwiftUI

/// The title-safe and action-safe guides over the picture, and the AUTO · EN
/// badge at its top, as the captions mock draws them (`.vc-safe` and
/// `.autoflag` in `pages/video-captions.html`, `CaptionGuides.swift`). Drawn
/// over the canvas, never into the film, and never in the way of a click.
struct CaptionGuidesOverlay: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if let viewport = editorState.viewport, let size = editorState.document?.canvasSize,
           editorState.showsSafeAreaGuides || editorState.captionBadge != nil {
            let corner = viewport.viewPoint(fromDocument: .zero)
            let picture = CGRect(origin: corner, size: CGSize(width: size.width * viewport.zoom,
                                                              height: size.height * viewport.zoom))
            ZStack(alignment: .topLeading) {
                if editorState.showsSafeAreaGuides {
                    ForEach(SafeAreaGuide.allCases, id: \.self) { guide in
                        let rect = guide.rect(in: size)
                        Self.guide(guide)
                            .frame(width: rect.width * viewport.zoom, height: rect.height * viewport.zoom)
                            .offset(x: picture.minX + rect.minX * viewport.zoom,
                                    y: picture.minY + rect.minY * viewport.zoom)
                    }
                    .transition(.opacity)
                }
                if let badge = editorState.captionBadge {
                    Self.badge(badge)
                        .frame(width: picture.width)
                        .offset(x: picture.minX, y: picture.minY + 10)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: editorState.showsSafeAreaGuides)
            .allowsHitTesting(false)
        }
    }

    /// One guide: a dashed line with its slab, the action slab top left and
    /// the title slab bottom right, so the two never sit on each other.
    private static func guide(_ guide: SafeAreaGuide) -> some View {
        let line = guide == .title ? Color(red: 1, green: 224 / 255, blue: 106 / 255).opacity(0.85)
            : Color.white.opacity(0.55)
        let ink = guide == .title ? Color(red: 1, green: 224 / 255, blue: 106 / 255) : Color.white.opacity(0.9)
        return RoundedRectangle(cornerRadius: 3)
            .strokeBorder(line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .overlay(alignment: guide == .title ? .bottomTrailing : .topLeading) {
                Text(guide.label)
                    .font(.system(size: 8, design: .monospaced))
                    .kerning(0.3)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.42)))
                    .padding(guide == .title ? .trailing : .leading, 4)
                    .padding(guide == .title ? .bottom : .top, 3)
            }
            .playtestField(guide.label)
    }

    /// AUTO · EN: a small gradient pill, centred at the top of the picture.
    private static func badge(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 7, weight: .bold))
            Text(text.uppercased()).font(.system(size: 8, weight: .bold)).kerning(0.64)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(LinearGradient(
            colors: [Color(red: 110 / 255, green: 139 / 255, blue: 1), Color(red: 197 / 255, green: 108 / 255, blue: 1)],
            startPoint: .topLeading, endPoint: .bottomTrailing)))
        .shadow(color: Color(red: 157 / 255, green: 108 / 255, blue: 1).opacity(0.6), radius: 8, y: 6)
        .fixedSize()
        .playtestField("Captions badge")
    }
}

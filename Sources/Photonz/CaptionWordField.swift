import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

/// The field one word of a caption is typed into, on the picture and on the
/// Words lane alike (`EditorState+CaptionWords`).
///
/// An AppKit field rather than a SwiftUI one because Tab has to mean "the next
/// word" rather than "the next control", and the field editor is the only
/// thing that sees Tab before the window does. Return and a click away keep
/// what was typed, Escape throws it away, Tab and Shift-Tab keep it and open
/// the next or previous word.
struct CaptionWordField: NSViewRepresentable {
    @Environment(EditorState.self) private var editorState
    let session: CaptionWordEditSession
    let font: NSFont
    let ink: NSColor

    func makeCoordinator() -> Coordinator { Coordinator(editorState: editorState) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: session.original)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Caption word")
        context.coordinator.opened(session, in: field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.font = font
        field.textColor = ink
        // Tab opened another word in the same field: take its letters and
        // hand the keyboard back to it.
        if context.coordinator.session?.ref != session.ref {
            field.stringValue = session.original
            context.coordinator.opened(session, in: field)
        }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.session = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let editorState: EditorState
        var session: CaptionWordEditSession?
        /// Set while a key has already settled the word, so the end of editing
        /// that follows does not settle it a second time.
        private var settled = false

        init(editorState: EditorState) { self.editorState = editorState }

        func opened(_ session: CaptionWordEditSession, in field: NSTextField) {
            self.session = session
            settled = false
            // The word is offered ready to be replaced, the way double clicking
            // a word does everywhere else.
            // Asked only when the field does not already have the keyboard:
            // after Tab it still does, and asking again ends its editing,
            // which would keep the next word and close the field at once.
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                if field.currentEditor() == nil { window.makeFirstResponder(field) }
                field.currentEditor()?.selectAll(nil)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard session != nil else { return false }
            let typed = textView.string
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                settled = true
                editorState.stepCaptionWordEdit(typed, by: 1)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                settled = true
                editorState.stepCaptionWordEdit(typed, by: -1)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                settled = true
                editorState.cancelCaptionWordEdit()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                settled = true
                editorState.commitCaptionWordEdit(typed)
                return true
            default:
                return false
            }
        }

        /// A click away keeps what was typed.
        func controlTextDidEndEditing(_ notification: Notification) {
            guard !settled, let session, editorState.captionWordEdit?.ref == session.ref,
                  let field = notification.object as? NSTextField else { return }
            editorState.commitCaptionWordEdit(field.stringValue)
        }
    }
}

/// The word's field, dressed: a dark plate with the accent ring round it, as
/// wide as the word needs.
struct CaptionWordFieldPlate: View {
    let session: CaptionWordEditSession
    let font: NSFont
    let ink: NSColor
    let minWidth: CGFloat
    let height: CGFloat
    let radius: CGFloat

    var body: some View {
        let letters = (session.original as NSString).size(withAttributes: [.font: font]).width
        CaptionWordField(session: session, font: font, ink: ink)
            .padding(.horizontal, 4)
            .frame(width: max(minWidth, letters + 22), height: height)
            .background(RoundedRectangle(cornerRadius: radius).fill(Color(red: 0.06, green: 0.07, blue: 0.1).opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(VideoKit.Palette.accent, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .playtestField("Caption word")
    }
}

/// The word's field on the picture, laid over the word it is typing, in the
/// caption's own face at the zoom the picture is shown at, so the fix is made
/// where the mistake is.
struct CaptionWordCanvasOverlay: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if let session = editorState.captionWordEdit, session.place == .canvas,
           let place = editorState.captionWordCanvasPlace, let viewport = editorState.viewport {
            let zoom = viewport.zoom
            let font = Self.font(place.text, zoom: zoom)
            let letters = (session.original as NSString).size(withAttributes: [.font: font]).width
            let width = max(place.rect.width * zoom + 12, letters + 22)
            let height = place.rect.height * zoom + 6
            let corner = viewport.viewPoint(fromDocument: place.rect.origin)
            CaptionWordFieldPlate(session: session, font: font, ink: .white, minWidth: width,
                                  height: height, radius: min(8, height / 4))
                .offset(x: corner.x + place.rect.width * zoom / 2 - width / 2, y: corner.y - 3)
        }
    }

    private static func font(_ text: TextContent, zoom: CGFloat) -> NSFont {
        let face = TextRasterizer.font(for: text)
        return CTFontCreateCopyWithAttributes(face, max(6, text.fontSize * zoom), nil, nil) as NSFont
    }
}

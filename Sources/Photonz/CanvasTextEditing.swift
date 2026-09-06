import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

// Typing on the canvas: the inline text editor, the caption pill editor, and
// the two small views they are drawn with. Split out of CanvasView.swift;
// `CanvasNSView`'s stored properties still live there.

extension CanvasNSView {
    // MARK: Inline text editing

    /// Opens the inline editor at `origin` (document coords). For a re-edit,
    /// the editor takes over the layer's string and style; EditorState hides the
    /// layer underneath via `onTextEditBegin`.
    func beginTextSession(layerID: UUID?, at origin: CGPoint) {
        guard textSession == nil else { return }
        // Nothing typed is ever thrown away: a piece inside a copy takes its
        // words from the original, so the field opens only when there is a
        // wording knob for those words to land on, and otherwise says why.
        if let layerID, componentsEnabled,
           case .refused(let refusal) = document?.wordingEdit(of: layerID) {
            onWordingRefused(refusal)
            return
        }
        var style = textContent ?? TextContent(string: "")
        var string = ""
        if let layerID, let layer = document?.canvasLayer(id: layerID),
           case .text(let existing) = layer.content {
            string = existing.string
            style = existing
            style.string = ""
            // The editor replaces the selection chrome.
            selectedLayerFrame = nil
            onSelectLayer(nil)
        }
        textSession = TextEditSession(layerID: layerID, origin: origin,
                                      alignment: style.alignment,
                                      verticalAlignment: style.verticalAlignment,
                                      staysOnOneLine: style.staysOnOneLine)

        let editor = makeInlineEditor()
        editor.string = string
        addSubview(editor)
        textEditor = editor
        textEditorZoom = 0 // force the style pass below to apply
        styleTextEditor(with: style)
        window?.makeFirstResponder(editor)
        // Words that are already there are offered ready to be replaced, the
        // way double clicking a label does everywhere else. With the caret
        // parked after them instead, a new label came out welded to the old
        // one ("ButtonSave all the changes", reported 2026-09-04). A click
        // inside the field afterwards drops the highlight and takes the caret
        // where it landed, so re-wording one word is still one click away.
        let opening = TextEntry.openingSelection(for: string)
        editor.setSelectedRange(NSRange(location: opening.location, length: opening.length))
        onTextEditBegin(layerID)
        refreshOverlays()
    }

    /// The spot a caption field takes for its whole session: a hand-placed pill
    /// keeps the spot it was dropped at, anything else is picked against the
    /// picture with room for a sentence, so a long caption never has to slide
    /// back or flip sides halfway through typing it.
    private func captionPlacement(for layer: Layer, canvas: CGSize) -> CaptionPlacement {
        guard var probe = layer.annotation,
              let tail = layer.annotationEndpoint(.start),
              let head = layer.annotationEndpoint(.end) else { return CaptionPlacement() }
        if probe.captionPinned, probe.captionOffset != nil {
            return CaptionPlacement(attach: probe.captionOffset, growth: probe.captionGrowth)
        }
        probe.start = tail
        probe.end = head
        // The planner only places a pill that has text; a fresh arrow's field
        // is empty, so it plans against the room a caption will need.
        if !probe.hasCaption { probe.caption = "A" }
        return CaptionPlanner.plan(for: probe, canvas: canvas,
                                   reserving: probe.captionRoomProbeSize)
    }

    /// Opens the inline caption editor on an arrow (Next `next-arrow-captions`):
    /// a single-line field centered where the pill renders, tinted with the
    /// pill's tone so the draft is legible over any image. Return commits, Esc
    /// abandons, clicking elsewhere commits — an empty commit means no caption.
    /// `layer` is passed in whole because the freshly created arrow may not
    /// have reached this view's `document` snapshot yet.
    func beginCaptionSession(layer: Layer) {
        guard textSession == nil, let viewport,
              let a = layer.annotation, a.shape == .arrow else { return }
        let placement = captionPlacement(for: layer, canvas: viewport.documentSize)
        var draft = a
        draft.captionOffset = placement.attach
        draft.captionGrowth = placement.growth
        let anchor = draft.captionAnchor()
        let center = CGPoint(x: layer.frame.minX + anchor.x, y: layer.frame.minY + anchor.y)
        let style = TextContent(string: "", fontName: "SF Pro", fontSize: a.captionFontSize,
                                colorHex: AnnotationContent.captionTextColorHex)
        textSession = TextEditSession(layerID: layer.id, origin: center, captionStyle: style,
                                      captionLayer: layer, captionPlacement: placement)

        let editor = makeInlineEditor()
        editor.isCaptionField = true
        // A fresh (or never captioned) arrow says how to skip. A re-edit of an
        // existing label starts with that label selected instead.
        if a.caption == nil { editor.placeholder = ArrowCaptionEntry.placeholder }
        // The draft sits INSIDE the bubble the caption will render in: a pill
        // view behind the field carries the fill, border, capsule and shadow
        // (a text view's own background is a plain rect and would clip the
        // shadow), and the field's inset is the pill's padding. Typing and
        // committing are then one shape, not two controls.
        editor.drawsBackground = false
        editor.layer?.borderWidth = 0
        editor.layer?.cornerRadius = 0
        // Selecting the label (a re-edit starts that way) tints the words
        // rather than dropping a system-colored slab into the bubble.
        editor.selectedTextAttributes = [.backgroundColor: NSColor(white: 1, alpha: 0.3),
                                         .foregroundColor: NSColor.white]
        editor.string = a.caption ?? ""
        let pill = CaptionPillView()
        addSubview(pill)
        captionPill = pill
        addSubview(editor)
        textEditor = editor
        textEditorZoom = 0 // force the style pass below to apply
        styleTextEditor(with: style)
        window?.makeFirstResponder(editor)
        let opening = TextEntry.openingSelection(for: editor.string)
        editor.setSelectedRange(NSRange(location: opening.location, length: opening.length))
        onCaptionEditBegin(layer.id)
        refreshOverlays()
    }

    /// The inline editor overlay both text and caption sessions share, before
    /// their session-specific styling.
    private func makeInlineEditor() -> InlineTextView {
        let editor = InlineTextView()
        editor.onCommit = { [weak self] in self?.commitTextSession() }
        editor.onCancel = { [weak self] in self?.cancelTextSession() }
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        // The container wraps at an explicit cap (layoutTextEditor) while the
        // editor frame hugs the typed text, so the box grows with content instead
        // of spanning to the canvas edge.
        editor.textContainer?.widthTracksTextView = false
        editor.wantsLayer = true
        editor.layer?.borderColor = NSColor.controlAccentColor.cgColor
        editor.layer?.borderWidth = 1
        editor.layer?.cornerRadius = 2
        editor.delegate = self
        return editor
    }

    /// The face any draft is set in — a caption's or a text block's: the
    /// content's DOCUMENT-size font with a scale transform for the zoom, never
    /// the zoomed point size. SF spaces letters differently at different point
    /// sizes, so a draft set at (size x zoom) is a few percent wider or
    /// narrower than what the rasterizer bakes at the document size and the
    /// canvas then scales. That gap is what made a long caption's far edge jump
    /// on Return, and what made a text block wrap at a different word than the
    /// label it committed to. Scaling the document-size face instead gives the
    /// draft exactly the committed letter spacing.
    ///
    /// Going through the descriptor is also the only way the WEIGHT survives:
    /// the resolved system face has no name AppKit will answer to
    /// (".SFNS-Regular" resolves to nothing), so the old name lookup fell back
    /// to the plain system font and typed a bold label in regular.
    private static func draftFont(_ content: TextContent, zoom: CGFloat) -> NSFont {
        let descriptor = (TextRasterizer.faceDescriptor(for: content) as NSFontDescriptor)
            .withSize(content.fontSize)
        var transform = AffineTransform()
        transform.scale(zoom)
        return NSFont(descriptor: descriptor, textTransform: transform)
            ?? NSFont.systemFont(ofSize: content.fontSize * zoom)
    }

    /// Applies font/color to the editor, scaled to the current zoom so the
    /// draft is the same apparent size as the rasterized layer will be.
    /// `content.string` is ignored.
    private func styleTextEditor(with content: TextContent) {
        guard let editor = textEditor, let viewport else { return }
        var stored = content
        stored.string = ""
        // The font picker's style says nothing about where the words sit, so a
        // re-edit's placement rides on the session and gets stamped back on
        // here. Without it, restyling mid-edit dropped a centred label to the
        // left edge until Return put it back.
        if let session = textSession, session.captionStyle == nil {
            stored.alignment = session.alignment
            stored.verticalAlignment = session.verticalAlignment
            stored.staysOnOneLine = session.staysOnOneLine
        }
        textEditorContent = stored
        textEditorZoom = viewport.zoom

        let font = Self.draftFont(stored, zoom: viewport.zoom)
        let rgba = RGBA(hex: content.colorHex) ?? RGBA(r: 1, g: 1, b: 1)
        let color = NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        editor.font = font
        editor.textColor = color
        editor.insertionPointColor = color
        editor.typingAttributes = [.font: font, .foregroundColor: color]
        if let storage = editor.textStorage, storage.length > 0 {
            storage.addAttributes([.font: font, .foregroundColor: color],
                                  range: NSRange(location: 0, length: storage.length))
        }
        // The draft sits where the committed words will: a centred label is
        // typed centred rather than jumping on Return.
        if textSession?.captionStyle == nil {
            switch stored.usedAlignment {
            case .left: editor.alignment = .left
            case .center: editor.alignment = .center
            case .right: editor.alignment = .right
            }
        }
        layoutTextEditor()
    }

    /// The wrap cap (document points) for a text block placed at `origin`.
    /// `TextBlockMetrics` owns the rule; the committed frame asks it the same
    /// question, so nothing wraps in one place and not the other.
    private func textWrapWidth(origin: CGPoint) -> CGFloat {
        guard let viewport else { return TextRasterizer.minimumTextWidth }
        return TextBlockMetrics.wrapWidth(origin: origin, in: viewport.documentSize)
    }

    /// Positions the editor over the session origin and sizes it.
    ///
    /// The field IS the box it commits to: its frame comes straight from
    /// `TextBlockMetrics` — the same measurement `commitTextEdit` sizes the
    /// layer with — scaled to the zoom, and the text container is that same
    /// box, so AppKit breaks the draft's lines exactly where CoreText will
    /// break the placed label's. Nothing here measures the typed text a second
    /// way, which is what used to make the box drift and the wrap move on
    /// Return.
    ///
    /// A caption session is a different shape and hands off to
    /// `layoutCaptionEditor`.
    private func layoutTextEditor() {
        guard let editor = textEditor, let viewport, let session = textSession else { return }
        if session.captionStyle != nil, let caption = session.captionLayer?.annotation {
            layoutCaptionEditor(editor, caption: caption, session: session, viewport: viewport)
            return
        }
        let zoom = viewport.zoom
        var draft = textEditorContent ?? TextContent(string: "")
        draft.string = editor.string
        // A box bigger than its words — a paragraph, or a label told to stretch
        // across what holds it — keeps the room it has, exactly as the commit
        // does, so re-wording one re-wraps in place.
        let room = roomyBox(session)
        var box = TextBlockMetrics.frameSize(for: draft,
                                             maxWidth: textWrapWidth(origin: session.origin),
                                             roomyWidth: room.width, roomyHeight: room.height,
                                             hugsShortWords: Experiments.shared.placementEnabled)
        // Words that stay on one line are TYPED on one line. The field keeps
        // the room the box has while they fit in it, and grows out to the right
        // once they do not, so what you are looking at while you type is the
        // one line that lands. Wrapping the draft into the bar's room and then
        // snapping it back to one line on Return is the jump this avoids.
        if draft.staysOnOneLine == true {
            box.width = max(box.width, TextRasterizer.naturalSize(draft).width)
        }
        // Words that sit low in a roomy box are typed low in it too.
        editor.textContainerInset = NSSize(width: 0,
                                           height: TextBlockMetrics.topInset(for: draft, in: box) * zoom)
        editor.textContainer?.containerSize = NSSize(width: box.width * zoom,
                                                     height: .greatestFiniteMagnitude)
        let topLeft = viewport.viewPoint(fromDocument: session.origin)
        editor.frame = CGRect(x: topLeft.x, y: topLeft.y,
                              width: box.width * zoom, height: box.height * zoom)
    }

    /// The room the box being re-edited has beyond its words; both nil for a
    /// new block and for a box that hugs what is in it.
    private func roomyBox(_ session: TextEditSession) -> (width: CGFloat?, height: CGFloat?) {
        guard Experiments.shared.placementEnabled,
              session.captionStyle == nil, let layerID = session.layerID,
              let layer = document?.canvasLayer(id: layerID),
              let words = layer.text else { return (nil, nil) }
        return TextBlockMetrics.roomyBox(for: words, frame: layer.frame)
    }

    /// A caption field IS the pill it commits to. Its frame comes straight from
    /// `CaptionMetrics` — the same measurement the rasterizer bakes the
    /// committed pill with — scaled to the zoom, so nothing here measures the
    /// typed text a second way and the bubble does not resize on Return. The
    /// draft lays out inside it at the pill's padding, in the document-size face
    /// (`captionDraftFont`), which is why the words fit the measurement.
    ///
    /// The bubble hangs off the spot the session froze when it opened: its near
    /// edge stays put on the arrow's tail and the words extend away from it, so
    /// what you watch while typing is where the caption lands.
    private func layoutCaptionEditor(_ editor: NSTextView, caption: AnnotationContent,
                                     session: TextEditSession, viewport: Viewport) {
        let zoom = viewport.zoom
        let inset = caption.captionPadding * zoom
        // The words are typed where the committed pill draws them, which is
        // further in than the padding: the pill centres their ink, not the box
        // measured for them. Without this the label slides a couple of points
        // on Return. An empty field is still a hint sitting at the padding —
        // its bubble is stretched to the hint, not to the words.
        let leading = CaptionMetrics.committedText(editor.string).isEmpty
            ? inset : CaptionMetrics.textInset(for: editor.string, in: caption) * zoom
        editor.textContainerInset = NSSize(width: leading, height: inset)
        var pill = CaptionMetrics.pillSize(for: editor.string, in: caption)
        if editor.string.isEmpty, let placeholder = (editor as? InlineTextView)?.placeholder,
           let font = editor.font {
            // An empty field is as wide as its hint, so the hint reads in one
            // line; the bubble shrinks to the text on the first keystroke.
            let hint = (placeholder as NSString).size(withAttributes: [.font: font]).width / zoom
            pill.width = max(pill.width, hint + 2 * caption.captionPadding + 4)
        }
        // A caption never wraps: it breaks where YOU pressed Return and nowhere
        // else, so the container is given room for the longest line as it was
        // measured. One line keeps the whole bubble and sits at the pill's ink
        // inset; several lines are centred on each other the way the committed
        // pill centres them, in the width the rasterizer lays them out in.
        let lines = CaptionMetrics.committedText(editor.string).contains(where: \.isNewline)
        if lines {
            let text = CaptionMetrics.textSize(for: editor.string,
                                               fontSize: caption.captionFontSize)
            editor.alignment = .center
            editor.textContainer?.containerSize = NSSize(
                width: max(1, (text.width - 2 * TextRasterizer.frameInset) * zoom),
                height: .greatestFiniteMagnitude)
        } else {
            editor.alignment = .left
            editor.textContainer?.containerSize = NSSize(width: max(1, pill.width * zoom),
                                                         height: .greatestFiniteMagnitude)
        }
        var center = session.origin
        if var probe = session.captionLayer?.annotation,
           let tail = session.captionLayer?.annotationEndpoint(.start),
           let head = session.captionLayer?.annotationEndpoint(.end) {
            probe.start = tail
            probe.end = head
            probe.captionOffset = session.captionPlacement.attach
            probe.captionGrowth = session.captionPlacement.growth
            // A pill that grew taller than the spot had room for is pulled back
            // onto the picture as it grows, by exactly the rule the commit uses,
            // so the bubble you are watching is the label that lands.
            probe.captionOffset = CaptionPlanner.keepingOnCanvas(
                session.captionPlacement.attach ?? .zero, for: probe,
                canvas: viewport.documentSize, pillSize: pill)
            center = probe.captionPillCenter(forPillSize: pill)
        }
        let pillCenter = viewport.viewPoint(fromDocument: center)
        let width = pill.width * zoom
        let height = pill.height * zoom
        // Not rounded to whole points: the committed pill is drawn at document
        // resolution and scaled, so it lands on fractions too, and snapping the
        // bubble to the screen grid would put its edges up to half a point off
        // the label it is standing in for.
        let frame = CGRect(x: pillCenter.x - width / 2, y: pillCenter.y - height / 2,
                           width: width, height: height)
        editor.frame = frame
        // The rasterizer's border straddles the pill's edge (a centered stroke)
        // while a layer's border is drawn inside its bounds, so the bubble is
        // grown by half a border and its inner stroke lands on the same band.
        // Without this the drawn edge sits half a border in from where the
        // committed one does.
        let straddle = caption.captionBorderWidth * zoom / 2
        captionPill?.frame = frame.insetBy(dx: -straddle, dy: -straddle)
        // Styled with the caption BEING TYPED, not the one the layer still
        // holds: the corner a pill wears depends on how many lines are in it.
        var shown = caption
        shown.caption = CaptionMetrics.committedText(editor.string)
        captionPill?.style(for: shown, zoom: zoom)
    }

    /// Keeps the editor glued to the document while panning/zooming, and
    /// restyles it when the font picker changes the style mid-edit.
    func refreshTextEditorDisplay() {
        guard let session = textSession, let viewport else { return }
        // Caption sessions keep their fixed style; text sessions track the
        // font picker's live style.
        let desired = session.captionStyle ?? textContent
        if let content = desired, content != textEditorContent || viewport.zoom != textEditorZoom {
            styleTextEditor(with: content)
        } else {
            layoutTextEditor()
        }
    }

    /// `keepTool` is the canvas press that closes the fresh arrow's field and
    /// starts the next arrow in the same gesture: the Arrow tool stays in hand.
    func commitTextSession(keepTool: Bool = false) {
        guard let session = textSession, let editor = textEditor else { return }
        let string = editor.string
        if session.captionStyle != nil, let layerID = session.layerID {
            teardownTextSession()
            onCaptionCommit(layerID, string, session.captionPlacement, keepTool)
            return
        }
        // Same wrap cap the live editor used, so layout doesn't shift on commit.
        let maxWidth = textWrapWidth(origin: session.origin)
        teardownTextSession()
        onTextCommit(session.layerID, session.origin, string, maxWidth)
    }

    func cancelTextSession() {
        guard let session = textSession else { return }
        teardownTextSession()
        if session.captionStyle != nil {
            onCaptionCancel()
        } else {
            onTextCancel()
        }
    }

    private func teardownTextSession() {
        textSession = nil
        textEditorContent = nil
        textEditorZoom = 0
        captionPill?.removeFromSuperview()
        captionPill = nil
        guard let editor = textEditor else { return }
        textEditor = nil
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: editor) {
            window?.makeFirstResponder(self)
        }
        editor.removeFromSuperview()
    }
}

extension CanvasNSView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        // A name field on the canvas grows with the name being typed.
        if notification.object as AnyObject? === canvasNameField {
            layoutCanvasNameField()
            return
        }
        layoutTextEditor()
    }

    /// The caption editor losing keyboard focus (most often a click into the
    /// inspector's Caption field) commits its draft, so there is only ever one
    /// caption draft open and whichever field you type in next starts from the
    /// committed text. Deferred a tick: this fires inside AppKit's responder
    /// hand-off, and tearing the editor down there would re-enter
    /// `makeFirstResponder`. Text-tool sessions are exempt on purpose: the font
    /// picker takes focus mid-edit and the block must stay open through it.
    func textDidEndEditing(_ notification: Notification) {
        // A canvas name field losing the keyboard any other way — a click into
        // the Layers list, another window — lands the name rather than dropping
        // it, which is what a rename field does everywhere else on the Mac.
        if notification.object as AnyObject? === canvasNameField {
            DispatchQueue.main.async { [weak self] in self?.commitCanvasRename() }
            return
        }
        guard textSession?.captionStyle != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.commitTextSession() }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // A canvas name field answers Return and Escape itself.
        if textView === canvasNameField { return false }
        // Esc abandons the draft (a re-edited layer reappears unchanged).
        // NSTextView routes Esc to completion in some states, so catch both.
        if commandSelector == #selector(NSResponder.cancelOperation(_:))
            || commandSelector == #selector(NSTextView.complete(_:)) {
            cancelTextSession()
            return true
        }
        return false
    }
}

/// The bubble behind an open arrow caption. Everything it draws — the fill,
/// the border in the arrow's ink, the capsule corner, the drop shadow — comes
/// off `AnnotationContent`, the same values `AnnotationRasterizer` bakes into
/// the committed caption, so typing and committing are one shape.
///
/// It is a view of its own rather than the text field's own background because
/// a text view fills a plain rectangle and clips its layer to it: the capsule
/// and its shadow need to live outside the field's bounds. Clicks pass
/// straight through to the field on top of it.
final class CaptionPillView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { nil }

    func style(for annotation: AnnotationContent, zoom: CGFloat) {
        guard let layer else { return }
        let chip = annotation.captionChipColor
        layer.backgroundColor = CGColor(srgbRed: chip.r, green: chip.g, blue: chip.b,
                                        alpha: AnnotationContent.captionChipOpacity)
        let ink = RGBA(hex: annotation.colorHex) ?? RGBA(r: 1, g: 0.23, b: 0.19)
        layer.borderColor = CGColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: ink.a)
        layer.borderWidth = max(1, annotation.captionBorderWidth * zoom)
        // Asked in DOCUMENT points and scaled back, because the corner rule
        // reads the caption's padding and line count, which are document
        // numbers: handing it a zoomed height would round a zoomed-in bubble
        // by a different rule than the pill it stands in for.
        let documentHeight = bounds.height / max(zoom, 0.0001)
        layer.cornerRadius = annotation.captionCornerRadius(pillHeight: documentHeight) * zoom
        // The rasterizer's shadow: a 4px blur two pixels down, black at 35%.
        // A CALayer's blur radius is half a CGContext's.
        layer.shadowColor = CGColor(gray: 0, alpha: 1)
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 2 * zoom
        layer.shadowOffset = CGSize(width: 0, height: 2 * zoom)
    }
}

/// The inline text editor. A plain `NSTextView` treats Return as a newline; this
/// subclass commits the edit on **⌘Return** (and keypad ⌘Enter) via `onCommit`,
/// leaving plain Return to insert a line break.
private final class InlineTextView: NSTextView {
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}
    /// A caption field routes its keys through `ArrowCaptionEntry`: Return
    /// drops a line, ⌘Return commits, Esc abandons, and a letter always types
    /// even when it is a tool shortcut. A text block handles its own keys
    /// below, with the same Return and ⌘Return rule.
    var isCaptionField = false
    /// Drawn in the text color at reduced opacity while the field is empty
    /// (NSTextView has no placeholder of its own).
    var placeholder: String? {
        didSet { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        if isCaptionField {
            // The caption field's keys are decided in PhotonzCore so the rule
            // (letters always type, even tool shortcuts) is tested there.
            let key: ArrowCaptionEntry.Key
            if event.keyCode == 36 || event.keyCode == 76 {
                key = .return(command: event.modifierFlags.contains(.command))
            } else if event.keyCode == 53 {
                key = .escape
            } else {
                key = .text(event.charactersIgnoringModifiers ?? "")
            }
            switch ArrowCaptionEntry.action(for: key) {
            case .commit: onCommit(); return
            case .cancel: onCancel(); return
            case .type: break
            }
        } else if (event.keyCode == 36 || event.keyCode == 76),
                  event.modifierFlags.contains(.command) {
            onCommit()
            return
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        if placeholder != nil { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let placeholder, string.isEmpty, let font else { return }
        let color = (textColor ?? .white).withAlphaComponent(0.55)
        let origin = textContainerOrigin
        (placeholder as NSString).draw(
            at: NSPoint(x: origin.x + (textContainer?.lineFragmentPadding ?? 0), y: origin.y),
            withAttributes: [.font: font, .foregroundColor: color])
    }
}

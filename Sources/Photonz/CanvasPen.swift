import AppKit
import PhotonzCore
import SwiftUI

// The Pen on the canvas (Next, `next-pen`): the presses that lay a path down,
// and the chrome that shows what you are about to commit.
//
// Everything the gesture DECIDES is in `PenSession` (PhotonzCore) and tested
// there. This file only converts between the view and the document, draws, and
// hands a finished path to the editor.

extension CanvasNSView {

    // MARK: - The chrome

    func setUpPenChrome() {
        penPathLayer.fillColor = nil
        penPathLayer.lineJoin = .miter
        penPathLayer.lineCap = .round
        penPathLayer.isHidden = true
        penPathLayer.zPosition = 96

        penAnchorsLayer.isHidden = true
        penAnchorsLayer.zPosition = 97
        penAnchorsLayer.lineWidth = 1

        penHandlesLayer.fillColor = nil
        penHandlesLayer.isHidden = true
        penHandlesLayer.zPosition = 97
        penHandlesLayer.lineWidth = 1

        penTargetLayer.fillColor = nil
        penTargetLayer.isHidden = true
        penTargetLayer.zPosition = 98
        penTargetLayer.lineWidth = 1.5

        for shape in [penPathLayer, penAnchorsLayer, penHandlesLayer, penTargetLayer] {
            layer?.addSublayer(shape)
        }
    }

    /// Draws the path being laid down: the runs already placed, the run to the
    /// pointer, a dot on every anchor, the handles under the hand, and a ring
    /// on the anchor a click would land on.
    ///
    /// The run to the pointer is drawn the same weight and colour as the rest,
    /// because it is the thing being decided. Everything else here is chrome in
    /// the system accent, so the shape and the scaffolding round it never read
    /// as the same object.
    func refreshPenChrome() {
        guard tool == .pen, let viewport, let content = penSession.previewPath,
              !content.anchors.isEmpty else {
            for shape in [penPathLayer, penAnchorsLayer, penHandlesLayer, penTargetLayer] {
                shape.isHidden = true
                shape.path = nil
            }
            return
        }
        let accent = NSColor.controlAccentColor.cgColor
        let zoom = viewport.zoom

        // The outline, in the ink the finished shape will wear, so what is on
        // screen while you draw is what lands when you stop.
        let outline = CGMutablePath()
        appendPen(content, to: outline, viewport: viewport)
        penPathLayer.path = outline
        let rgba = RGBA(hex: content.paint.hex) ?? RGBA(r: 1, g: 0, b: 0)
        penPathLayer.strokeColor = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b,
                                           alpha: rgba.a)
        penPathLayer.lineWidth = max(1, content.strokeWidth * zoom)
        // A path that would close is shown filled, faintly: the shape you get
        // rather than the line you drew.
        if content.isClosed, let fill = content.fill, let ink = RGBA(hex: fill.hex) {
            penPathLayer.fillColor = CGColor(srgbRed: ink.r, green: ink.g, blue: ink.b,
                                             alpha: ink.a * 0.4)
        } else {
            penPathLayer.fillColor = nil
        }
        penPathLayer.isHidden = false

        // A dot on every anchor placed, so the first click leaves something on
        // screen and you can count what you have put down.
        let dots = CGMutablePath()
        for anchor in penSession.anchors {
            let p = viewport.viewPoint(fromDocument: anchor.point)
            let r: CGFloat = anchor.kind == .smooth ? 3.5 : 3
            dots.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        penAnchorsLayer.path = dots
        penAnchorsLayer.fillColor = NSColor.white.cgColor
        penAnchorsLayer.strokeColor = accent
        penAnchorsLayer.isHidden = dots.isEmpty

        refreshPenHandles(viewport: viewport, accent: accent)
        refreshPenTarget(viewport: viewport, accent: accent)
    }

    /// The two arms of the handle being pulled out, with a dot on each end.
    /// Only while the button is down: handles you cannot drag are decoration,
    /// and editing them is the next slice.
    private func refreshPenHandles(viewport: Viewport, accent: CGColor) {
        guard let live = penSession.livePath, let anchor = live.anchors.last,
              penSession.isPressing, anchor.handleOut != nil || anchor.handleIn != nil else {
            penHandlesLayer.isHidden = true
            penHandlesLayer.path = nil
            return
        }
        let path = CGMutablePath()
        let centre = viewport.viewPoint(fromDocument: anchor.point)
        for end in [anchor.controlIn, anchor.controlOut] where end != anchor.point {
            let p = viewport.viewPoint(fromDocument: end)
            path.move(to: centre)
            path.addLine(to: p)
            path.addEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
        }
        penHandlesLayer.path = path
        penHandlesLayer.strokeColor = accent
        penHandlesLayer.isHidden = path.isEmpty
    }

    /// The ring that says a click lands on an anchor rather than on the pixel
    /// under it: on the first anchor when it would close, on the last when it
    /// would end an open path. Without it, closing is guesswork.
    private func refreshPenTarget(viewport: Viewport, accent: CGColor) {
        guard let pointer = penSession.pointer, !penSession.isPressing else {
            penTargetLayer.isHidden = true
            penTargetLayer.path = nil
            return
        }
        let zoom = viewport.zoom
        let target: CGPoint?
        if penSession.wouldClose(at: pointer, zoom: zoom) {
            target = penSession.anchors.first?.point
        } else if penSession.wouldFinish(at: pointer, zoom: zoom) {
            target = penSession.anchors.last?.point
        } else {
            target = nil
        }
        guard let target else {
            penTargetLayer.isHidden = true
            penTargetLayer.path = nil
            return
        }
        let p = viewport.viewPoint(fromDocument: target)
        let r: CGFloat = 7
        penTargetLayer.path = CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r,
                                                       width: r * 2, height: r * 2),
                                     transform: nil)
        penTargetLayer.strokeColor = accent
        penTargetLayer.isHidden = false
    }

    /// The path content as a view-space CGPath.
    private func appendPen(_ content: PathContent, to path: CGMutablePath, viewport: Viewport) {
        guard let first = content.anchors.first else { return }
        path.move(to: viewport.viewPoint(fromDocument: first.point))
        for run in content.segments {
            if run.isStraight {
                path.addLine(to: viewport.viewPoint(fromDocument: run.end))
            } else {
                path.addCurve(to: viewport.viewPoint(fromDocument: run.end),
                              control1: viewport.viewPoint(fromDocument: run.control1),
                              control2: viewport.viewPoint(fromDocument: run.control2))
            }
        }
        if content.isClosed { path.closeSubpath() }
    }

    // MARK: - The gesture

    /// A press with the Pen in hand. True when the pen took it.
    ///
    /// The first anchor of a NEW path lets go of whatever was picked, which,
    /// now that the Pen stays in hand, is normally the shape it drew a moment
    /// ago. Drawing is not editing: leaving it picked means a ⌫ aimed at the
    /// line under your hand takes a finished shape off the canvas behind it
    /// instead — two clicks into a second triangle, ⌫ deleted the first one
    /// and the chip carried on saying "keep clicking points" (2026-09-13).
    /// Every pen that stays in hand lets go at this same moment.
    func penMouseDown(at p: CGPoint, event: NSEvent) -> Bool {
        guard tool == .pen, let viewport else { return false }
        let startingAPath = !penSession.isDrawing
        penSession.grid = canvasNudgeGrid
        penSession.press(at: p, constrained: event.modifierFlags.contains(.shift),
                         breaking: event.modifierFlags.contains(.option),
                         free: event.modifierFlags.contains(.command),
                         zoom: viewport.zoom)
        if startingAPath, selectedLayerFrame != nil {
            selectedLayerFrame = nil
            onSelectLayer(nil)
        }
        refreshPenChrome()
        return true
    }

    func penMouseDragged(to p: CGPoint, event: NSEvent) {
        guard tool == .pen, let viewport else { return }
        penSession.grid = canvasNudgeGrid
        penSession.drag(to: p, constrained: event.modifierFlags.contains(.shift),
                        zoom: viewport.zoom)
        refreshPenChrome()
    }

    func penMouseUp(at p: CGPoint, event: NSEvent) {
        guard tool == .pen else { return }
        switch penSession.release() {
        case .placed, .retracted, .nothing:
            penSession.pointer = p
            penSession.free = event.modifierFlags.contains(.command)
            refreshPenChrome()
        case .closed(let content), .finished(let content):
            commitPen(content)
        }
        onPenHintChange(PenSession.hint(for: penSession))
    }

    /// The pointer moved with the Pen in hand and no button down: the run to
    /// the pointer follows it, which is the whole reason you can see the curve
    /// before you commit it.
    func penMouseMoved(at p: CGPoint, event: NSEvent) {
        guard tool == .pen, let viewport else { return }
        penSession.pointer = p
        penSession.zoom = viewport.zoom
        penSession.constrained = event.modifierFlags.contains(.shift)
        // The grid is read on every move rather than once at the start of a
        // path: the lines a drag pulls to follow the zoom, so a path drawn
        // across a pinch lands on the lines that are on screen NOW.
        penSession.grid = canvasNudgeGrid
        penSession.free = event.modifierFlags.contains(.command)
        refreshPenChrome()
    }

    /// Return and Escape with the Pen in hand. True when the pen answered the
    /// key, so the canvas stops looking.
    ///
    /// Escape means the same thing twice over, one step at a time: it throws
    /// away the path being drawn, and then, with nothing being drawn, it puts
    /// the Pen down. The Pen no longer hands itself back after every shape
    /// (`EditorState.addPath`), so this is the way out that is not the tool
    /// bar, and it lands on Select with the shape just drawn still picked.
    ///
    /// It is answered HERE rather than at the end of the canvas's own Escape
    /// chain because that chain drops the selection first: from a shape the
    /// Pen just drew, the way out would otherwise cost two presses, and the
    /// first one would silently throw the pick away.
    func penKeyDown(_ event: NSEvent) -> Bool {
        guard tool == .pen, !event.modifierFlags.contains(.command) else { return false }
        guard penSession.isDrawing else {
            guard event.keyCode == 53 else { return false }  // Escape
            onToolChange(.select)
            return true
        }
        switch event.keyCode {
        case 36, 76:  // Return, Enter
            if let content = penSession.finish() {
                commitPen(content)
            } else {
                endPenSession()
            }
            return true
        case 53:  // Escape
            penSession.discard()
            endPenSession()
            return true
        case 51, 117:  // ⌫ and forward delete
            // The same step back one anchor that ⌘Z takes, on the key a pen
            // user reaches for first. It also means ⌫ cannot fall through to
            // the canvas's own delete while a path is being drawn.
            guard penSession.undoLastAnchor() else { return true }
            refreshPenChrome()
            onPenHintChange(PenSession.hint(for: penSession))
            return true
        default:
            return false
        }
    }

    /// Whether a path is being laid down right now, which is what decides
    /// whether ⌘Z steps back an anchor or reaches the document's own undo.
    var penIsDrawing: Bool { tool == .pen && penSession.isDrawing }

    /// Command Z while a path is being laid down steps back ONE anchor rather
    /// than losing the drawing. It is taken here rather than in `keyDown`
    /// because a key equivalent never reaches a view's `keyDown`: the window
    /// offers it to the view hierarchy first and the Edit menu second, so this
    /// is the only place the pen can answer before Undo does.
    ///
    /// Once there is nothing left to step back through the pen stops answering
    /// and the keystroke falls through, so Command Z means what it always means
    /// the moment the path is gone.
    func penUndoKeyEquivalent(_ event: NSEvent) -> Bool {
        guard penIsDrawing, event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.shift),
              event.charactersIgnoringModifiers?.lowercased() == "z",
              penSession.undoLastAnchor() else { return false }
        refreshPenChrome()
        onPenHintChange(PenSession.hint(for: penSession))
        return true
    }

    private func commitPen(_ content: PathContent) {
        penSession.discard()
        refreshPenChrome()
        onPenHintChange(PenSession.hint(for: penSession))
        onPathCommit(content)
    }

    /// Wipes the chrome and puts the hint back to its opening line, without
    /// putting anything in the document.
    func endPenSession() {
        penSession.discard()
        refreshPenChrome()
        onPenHintChange(PenSession.hint(for: penSession))
    }
}

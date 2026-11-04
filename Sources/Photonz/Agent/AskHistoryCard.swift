import CoreGraphics
import Foundation
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI

// One row of the Agent group's history, and the card it shows while the pointer
// rests on it (the user, 2026-11-04: "if i hover over one, there's a popover on
// the left side which shows how it was interpreted and the before/after
// thumbs"). The card is drawn in the window, over the canvas, rather than as a
// popover window: it never takes a key, a walk photographs it with the window,
// and it can sit left of the panel whatever the row's own edge is. What it says
// and where it sits are `AskUnderstanding` and `AskHistoryCardPlacement`.

/// Which row's card is up, and the small pictures on it.
@MainActor
@Observable
final class AskHistoryHover {

    struct Shown: Equatable {
        let id: UUID
        /// The row's frame in the window.
        let row: CGRect
    }

    struct Pictures {
        let before: CGImage?
        let after: CGImage?
    }

    /// How long the pointer rests on a row before its card comes up.
    static let restBeforeShowing: Duration = .milliseconds(350)
    /// How long a card waits to move to another row, so a pointer crossing
    /// rows on its way to the card does not change what it is heading for.
    static let restBeforeSwitching: Duration = .milliseconds(120)
    /// How long a card stays after the pointer leaves, long enough to cross
    /// from the row to the card.
    static let graceBeforeHiding: Duration = .milliseconds(350)
    /// The most rows whose pictures are kept. They are small and drawn again
    /// when next needed.
    static let mostPictures = 12

    private(set) var shown: Shown?
    private(set) var pictures: [UUID: Pictures] = [:]

    @ObservationIgnored private var isOverCard = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var drawing: Set<UUID> = []
    @ObservationIgnored private var drawnOrder: [UUID] = []

    /// The pointer came onto or left a row.
    func pointer(on over: Bool, row id: UUID, frame: CGRect) {
        if over {
            guard shown?.id != id else {
                pending?.cancel()
                return
            }
            after(shown == nil ? Self.restBeforeShowing : Self.restBeforeSwitching) { [weak self] in
                self?.shown = Shown(id: id, row: frame)
            }
        } else if shown == nil {
            pending?.cancel()
        } else if !isOverCard {
            // Off any row with a card up, whichever row it belongs to: what
            // was waiting (a move to the row just left) is overtaken.
            hideSoon()
        }
    }

    /// The pointer came onto or left the card, which holds it up.
    func pointer(onCard over: Bool) {
        isOverCard = over
        if over {
            pending?.cancel()
        } else {
            hideSoon()
        }
    }

    private func hideSoon() {
        after(Self.graceBeforeHiding) { [weak self] in
            guard let self, !self.isOverCard else { return }
            self.shown = nil
        }
    }

    private func after(_ wait: Duration, _ then: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            then()
        }
    }

    /// The history was cleared.
    func forget() {
        pending?.cancel()
        shown = nil
        isOverCard = false
        letGoOfPictures()
    }

    /// Memory is short: they are drawn again when next hovered.
    func letGoOfPictures() {
        pictures = [:]
        drawnOrder = []
    }

    /// Draws a row's before and after off the main thread, once.
    func drawPictures(of row: AskChangeList.Row, in editor: EditorState) {
        guard pictures[row.id] == nil, drawing.insert(row.id).inserted else { return }
        Task { @MainActor [weak self, weak editor] in
            guard let editor else { return }
            let before = await Self.picture(of: row.change.before, in: editor)
            let after = await Self.picture(of: row.change.after, in: editor)
            guard let self else { return }
            self.drawing.remove(row.id)
            self.pictures[row.id] = Pictures(before: before, after: after)
            self.drawnOrder.append(row.id)
            while self.drawnOrder.count > Self.mostPictures {
                self.pictures[self.drawnOrder.removeFirst()] = nil
            }
        }
    }

    /// A picture's whole canvas; a video's frame at the playhead.
    private static func picture(of document: PhotonzDocument, in editor: EditorState) async -> CGImage? {
        let scale = AskHistoryCardPlacement.thumbnailScale(canvas: document.canvasSize)
        let store = editor.store
        if editor.documentHasTime {
            let last = max(0, document.documentDurationMS - 1)
            return await AgentWork.frame(of: document, store: store, atMS: min(editor.documentTimeMS, last), scale: scale)
        }
        let renderer = editor.previewRenderer
        return await Task.detached(priority: .userInitiated) {
            renderer.render(document, store: store, scale: scale)
        }.value
    }
}

/// A row of history: what the request changed, in plain words. A click picks
/// what it made, the mock's Last change click. An undone request stays in the
/// list, quieter, since it was still asked.
struct AgentHistoryRow: View {
    @Environment(EditorState.self) private var editorState
    let row: AskChangeList.Row
    let number: Int
    @State private var frame: CGRect = .zero
    @State private var isOver = false

    var body: some View {
        let ask = editorState.ask
        VStack(alignment: .leading, spacing: 2) {
            Button { ask.pickChange(row.id, in: editorState) } label: {
                Text(row.sentence)
                    .font(.system(size: 11.5))
                    .foregroundStyle(row.isOn ? .primary : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .playtestControl("Agent Change \(number) Words", detail: row.sentence)
            if let leftOut = row.leftOut {
                Text(leftOut)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .playtestControl("Agent Change \(number) Left Out", detail: leftOut)
            }
        }
        .playtestControl("Agent Change \(number) State", detail: row.isOn ? "standing" : "undone")
        .padding(.vertical, 4)
        // In by the field's own inset, so the words line up with what is
        // typed under them, and the light behind a row stays inside the
        // list, which would clip it.
        .padding(.horizontal, 6)
        .background(isLit(ask) ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .playtestHover("Agent Change \(number)") { over in
            isOver = over
            ask.card.pointer(on: over, row: row.id, frame: frame)
        }
        .contextMenu {
            Button(AskCopy.selectMade) { ask.pickChange(row.id, in: editorState) }
                .disabled(!row.isOn)
            Divider()
            Button(AskCopy.clearHistory) { ask.askToClearHistory(in: editorState) }
        }
        .playtestControl("Agent Change \(number)", detail: row.sentence)
    }

    private func isLit(_ ask: AskSession) -> Bool {
        isOver || ask.card.shown?.id == row.id
    }
}

/// The three dots on the Agent group's header.
struct AgentHistoryMenu: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let hasRows = !editorState.ask.changes.rows.isEmpty
        return VideoKit.HeaderMenu(
            label: "Agent Menu", symbol: "ellipsis", help: AskCopy.historyMenuTip,
            choices: [
                .item(AskCopy.clearHistory, isEnabled: hasRows, image: Self.clearImage) { [editorState] in
                    editorState.ask.askToClearHistory(in: editorState)
                },
            ])
            .fixedSize()
            .panelHelp(AskCopy.historyMenuTip)
            .playtestControl("Agent Menu", detail: "the three dots on the Agent header")
    }

    private static let clearImage = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
}

/// The card, over the whole window, left of the panel beside its row. Moved off
/// what the row made when there is room (`AskHistoryCardPlacement`).
struct AskHistoryCardOverlay: View {
    @Environment(EditorState.self) private var editorState
    /// The window's content, in the coordinates rows report in.
    let bounds: CGRect
    let panelLeft: CGFloat
    @State private var height: CGFloat = 220

    private static let corner: CGFloat = 14

    var body: some View {
        let ask = editorState.ask
        if let shown = ask.card.shown, let row = ask.changes.row(shown.id) {
            let box = AskHistoryCardPlacement.frame(
                size: CGSize(width: AskHistoryCardPlacement.width, height: height), row: shown.row,
                panelLeft: panelLeft, bounds: bounds, avoiding: madeFrame(of: row))
            card(row, ask: ask)
                .frame(width: box.width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .offset(x: box.minX - bounds.minX, y: box.minY - bounds.minY)
                .transition(.opacity)
                .task(id: row.id) { ask.card.drawPictures(of: row, in: editorState) }
        }
    }

    private func card(_ row: AskChangeList.Row, ask: AskSession) -> some View {
        let isCommand = row.asked.hasPrefix(AskCopy.commandMark)
        let pictures = ask.card.pictures[row.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isCommand ? row.sentence : row.asked)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .playtestControl("Agent Card Asked", detail: row.asked)
                if !row.isOn {
                    Text(AskCopy.cardUndone)
                        .font(.system(size: 10.5))
                        .playtestControl("Agent Card Undone", detail: AskCopy.cardUndone)
                }
            }
            if !row.understood.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    // The card is glass over whatever the canvas shows, where
                    // a secondary label went grey on grey over a white page:
                    // quieter by size and weight, never by colour.
                    Text(AskCopy.cardUnderstood)
                        .font(.system(size: 10.5, weight: .semibold))
                    ForEach(Array(row.understood.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 11.5))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .playtestControl("Agent Card Line \(index + 1)", detail: line)
                    }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                thumbnail(pictures?.before, label: AskCopy.cardBefore, canvas: row.change.before.canvasSize)
                thumbnail(pictures?.after, label: AskCopy.cardAfter, canvas: row.change.after.canvasSize)
            }
            if !isCommand { votes(row, ask: ask) }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.corner))
        .contentShape(.rect(cornerRadius: Self.corner))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .playtestHover("Agent Card") { ask.card.pointer(onCard: $0) }
        .playtestControl("Agent Card", detail: row.sentence)
    }

    /// The canvas at this size, on white as a page is, so nothing drawn in
    /// black vanishes into dark glass.
    private func thumbnail(_ picture: CGImage?, label: String, canvas: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack {
                Rectangle().fill(.white)
                if let picture {
                    Image(decorative: picture, scale: 1).resizable().interpolation(.high)
                }
            }
            .aspectRatio(canvas.width > 0 && canvas.height > 0 ? canvas.width / canvas.height : 1, contentMode: .fit)
            .frame(maxHeight: 110)
            .clipShape(.rect(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.separator) }
            .playtestControl("Agent Card \(label)", detail: picture == nil ? "drawing" : "drawn")
            Text(label).font(.system(size: 10.5, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A quiet thumbs up and down, faint until picked. A thumbs down keeps
    /// the request as a test case the eval has never seen.
    private func votes(_ row: AskChangeList.Row, ask: AskSession) -> some View {
        HStack(spacing: 0) {
            Spacer()
            ForEach([AskVerdict.up, .down], id: \.self) { verdict in
                let picked = row.verdict == verdict
                let name = verdict == .up ? "Up" : "Down"
                Button { ask.vote(verdict, on: row.id, in: editorState) } label: {
                    Image(systemName: "hand.thumbs\(verdict == .up ? "up" : "down")\(picked ? ".fill" : "")")
                        .font(.system(size: 11))
                }
                .buttonStyle(IconActionButtonStyle(diameter: 22, restingTint: .primary))
                .toolTip(verdict == .up ? AskCopy.goodResult : AskCopy.badResult)
                .playtestControl("Agent Card Thumbs \(name)", detail: picked ? "picked" : "not picked")
            }
        }
    }

    /// What the row made, on screen in this window's coordinates. The canvas
    /// starts at the window's top left, and `Viewport` measures from there.
    private func madeFrame(of row: AskChangeList.Row) -> CGRect? {
        guard let document = editorState.document, let viewport = editorState.viewport else { return nil }
        let boxes = row.change.madeLayerIDs(in: document).compactMap(document.canvasFrame(of:))
        guard let first = boxes.first else { return nil }
        let box = boxes.dropFirst().reduce(first) { $0.union($1) }
        let corner = viewport.viewPoint(fromDocument: box.origin)
        return CGRect(x: bounds.minX + corner.x, y: bounds.minY + corner.y,
                      width: box.width * viewport.zoom, height: box.height * viewport.zoom)
    }
}

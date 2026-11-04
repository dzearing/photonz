import PhotonzCore
import SwiftUI

// The three places Ask shows (`docs/design/ask.md`, the mock
// `agent-generate-wt.html`): the Ask button in the title bar, the composer it
// opens over the canvas, and the Agent group in the right panel, the one place
// a request is followed: the live request, and under it the history.
// No model is chosen anywhere here: that lives in Settings (the user,
// 2026-10-19).

/// The title bar's Ask button, the mock's `.askbtn`: sparkle, Ask, and the
/// key, on the design's hero button (`HeroButtonStyle`), the one control in
/// the title bar that opens the agent rather than running a command.
struct AskTitlebarButton: View {
    @Environment(EditorState.self) private var editorState

    static let height: CGFloat = 24
    private static let sparkleSize: CGFloat = 14
    private static let wordSize: CGFloat = 12
    private static let keySize: CGFloat = 10.5
    private static let spacing: CGFloat = 5
    private static let padding: CGFloat = 12

    /// The widest it is drawn, with the key, so the title bar's box (fixed
    /// between documents, `TitlebarPanelToggle.boxWidth`) always holds it
    /// whole. Measured from the words and the symbol, never typed in: the old
    /// typed-in 76 cut the pill to a width its words did not choose.
    @MainActor static let width: CGFloat = {
        func wide(_ text: String, _ font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let content = sparkleSize
            + wide(AskCopy.button, .systemFont(ofSize: wordSize, weight: .semibold))
            + wide("⌘K", .systemFont(ofSize: keySize, weight: .regular))
            + spacing * 2
        return ceil(content + padding * 2) + 2
    }()

    /// Sparkle, Ask and the key, ⌘K on a picture and on a video alike. The
    /// legibility check draws this same label on the same style.
    static var label: some View {
        HStack(spacing: spacing) {
            AskSparkle()
                .frame(width: sparkleSize, height: sparkleSize)
                .measuredInk()
            Text(AskCopy.button)
                .font(.system(size: wordSize, weight: .semibold))
            // Quieter than the word by size and weight, never by fading: the
            // design's 70% white takes on the pink behind it and reads as one
            // colour with it (`LegibilitySheet`, 2026-10-24).
            Text("⌘K")
                .font(.system(size: keySize, weight: .regular))
        }
        .fixedSize()
    }

    var body: some View {
        let ask = editorState.ask
        Button {
            ask.isComposerShown ? ask.closeComposer() : ask.summon(in: editorState)
        } label: {
            Self.label
        }
        .buttonStyle(HeroButtonStyle(isOpen: ask.isComposerShown, height: Self.height, padding: Self.padding))
        .focusEffectDisabled()
        .toolTip(AskCopy.buttonTooltip, key: "⌘K", below: true)
        .playtestControl("Ask", detail: "the title bar's Ask button")
        // Its own width, not the box's: the box is measured to hold it.
        .frame(height: TitlebarPanelToggle.barHeight)
    }
}

/// The design's sparkle (`ic-sparkle` in the mocks' icon set): one large four
/// pointed star and a small one off its lower right, filled. Drawn from the
/// design's own 24 point outline, scaled to the frame it is given.
struct AskSparkle: Shape {
    func path(in rect: CGRect) -> Path {
        func star(_ center: CGPoint, reach: CGFloat, waist: CGFloat) -> [CGPoint] {
            [CGPoint(x: center.x, y: center.y - reach), CGPoint(x: center.x + waist, y: center.y - waist),
             CGPoint(x: center.x + reach, y: center.y), CGPoint(x: center.x + waist, y: center.y + waist),
             CGPoint(x: center.x, y: center.y + reach), CGPoint(x: center.x - waist, y: center.y + waist),
             CGPoint(x: center.x - reach, y: center.y), CGPoint(x: center.x - waist, y: center.y - waist)]
        }
        let scale = min(rect.width, rect.height) / 24
        var path = Path()
        for points in [star(CGPoint(x: 12, y: 10.75), reach: 7.95, waist: 2.05),
                       star(CGPoint(x: 18.8, y: 18.4), reach: 3.2, waist: 0.85)] {
            path.addLines(points.map { CGPoint(x: rect.minX + $0.x * scale, y: rect.minY + $0.y * scale) })
            path.closeSubpath()
        }
        return path
    }
}

/// The composer over the canvas, the mock's `.askpal`: glass over a dimmed
/// window, one field, and Ask. Return asks; Escape or a click outside closes.
struct AskComposerOverlay: View {
    @Environment(EditorState.self) private var editorState
    @FocusState private var fieldHasFocus: Bool

    var body: some View {
        let ask = editorState.ask
        ZStack(alignment: .top) {
            if ask.isComposerShown {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture { ask.closeComposer() }
                    .transition(.opacity)
                composer(ask)
                    .padding(.top, 72)
                    .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.24, bounce: 0.1), value: ask.isComposerShown)
    }

    private func composer(_ ask: AskSession) -> some View {
        @Bindable var ask = ask
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                Text(AskCopy.composerHeader).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(AskCopy.onDevice).font(.system(size: 11)).foregroundStyle(.secondary)
                Button { ask.closeComposer() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(IconActionButtonStyle(diameter: 20, restingTint: .secondary))
                .toolTip("Close", key: "esc")
            }
            if fieldHasFocus { AskCommandsList() }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(AskCopy.composerPlaceholder, text: $ask.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...4)
                    .focused($fieldHasFocus)
                    .askFieldKeys(ask, in: editorState)
                    .help(AskCopy.composerTip)
                    .playtestControl("Ask Request", detail: "the Ask composer's field")
                Button { ask.submit(in: editorState) } label: {
                    Label(AskCopy.button, systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!ask.canSubmit)
                .playtestControl("Ask Send", detail: "the Ask composer's Ask button")
            }
            // Asked with nothing open, a request it cannot do there: why,
            // with the words still in the field.
            if let refusal = ask.refusal {
                Text(refusal)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .playtestControl("Ask Says", detail: refusal)
            }
        }
        .onChange(of: ask.draft) { ask.refusal = nil }
        .padding(14)
        .frame(width: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        // A beat after it appears, once the field is in the window: asked
        // for any sooner, the canvas keeps the keyboard.
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            fieldHasFocus = true
        }
        .onExitCommand { ask.closeComposer() }
    }
}

/// The Agent group, the one place a request is followed (the user,
/// 2026-11-04): the live request with Stop, and under it the history, one row
/// a request, newest at the top, each saying what changed. A row has no switch
/// and no delete: undo is how a request is taken back, and what it made can be
/// changed by hand, so turning it off would mean nothing plain. Resting on a
/// row shows its card (`AskHistoryCardOverlay`). Requests sent while one works
/// sit above it, newest first, each with a cancel, so a request moves down the
/// list as it goes and never jumps.
struct AgentPanel: View {
    @Environment(EditorState.self) private var editorState
    @FocusState private var fieldHasFocus: Bool

    var body: some View {
        let ask = editorState.ask
        let rows = ask.changes.rows
        let waiting = ask.line.shown
        VStack(alignment: .leading, spacing: 6) {
            if ask.isConfirmingClear { clearQuestion(ask) }
            ForEach(Array(waiting.enumerated()), id: \.element.id) { index, request in
                // Numbered in the order they will run: 1 is next.
                waitingRow(request, number: waiting.count - index, ask: ask)
            }
            switch ask.phase {
            case .planning, .running:
                workingRow(ask)
            case .stopped(let sentence):
                Text(sentence)
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .playtestControl("Ask Says", detail: sentence)
                // Ask's model is set up in Settings: one click there, one to download.
                if AskLocalModel.Trouble.setupSentences.contains(sentence) {
                    Button(AskCopy.setUp) { AppDelegate.coordinator?.showSettings(section: .ask) }
                        .controlSize(.small)
                        .playtestControl("Ask Set Up", detail: AskCopy.setUp)
                }
            case .idle, .ran:
                if ask.phase == .ran, let said = ask.said {
                    Text(said)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .playtestControl("Ask Says", detail: said)
                }
                if rows.isEmpty && waiting.isEmpty {
                    Text(AskCopy.empty).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            if !rows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            AgentHistoryRow(row: row, number: index + 1)
                        }
                    }
                }
                .frame(maxHeight: 240)
                .fixedSize(horizontal: false, vertical: rows.count <= 8)
            }
            chatIn(ask)
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .animation(.spring(duration: 0.24, bounce: 0.1), value: rows.map(\.id))
        .animation(.spring(duration: 0.24, bounce: 0.1), value: waiting.map(\.id))
    }

    /// The request at work: its words and Stop, and under them one live
    /// line saying what Ask is doing now, with the time it has taken once
    /// that passes five seconds. The line is one line high whatever it says
    /// and cross-fades as it changes, so nothing around it moves; it goes
    /// when the request is done (finished rows never list their steps, the
    /// user, 2026-10-20).
    private func workingRow(_ ask: AskSession) -> some View {
        let stage = ask.liveStage
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                    .frame(width: Self.spinnerWidth)
                Text(ask.asked.isEmpty ? AskCopy.workingLine : ask.asked)
                    .font(.system(size: 11.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(AskCopy.stop) { ask.stop() }.controlSize(.small)
                    .toolTip(AskCopy.stopTooltip)
                    .playtestControl("Agent Stop", detail: AskCopy.stop)
            }
            HStack(spacing: 4) {
                Text(stage.line)
                    .lineLimit(1)
                    .id(stage.line)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .playtestControl("Agent Stage", detail: stage.line)
                TimelineView(.periodic(from: ask.stageSince, by: 1)) { context in
                    Text(AskStage.elapsed(context.date.timeIntervalSince(ask.stageSince)) ?? "")
                        .monospacedDigit()
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .frame(height: Self.stageLineHeight)
            .clipped()
            .padding(.leading, Self.spinnerWidth + 6)
            .animation(.easeInOut(duration: 0.2), value: stage.line)
            .help(stage.fullLine)
        }
        .help(ask.asked)
        .playtestControl("Agent Working", detail: ask.asked)
    }

    private static let spinnerWidth: CGFloat = 16
    private static let stageLineHeight: CGFloat = 14

    /// A request waiting its turn: its words, quiet, and a cancel.
    private func waitingRow(_ request: AskRequestLine.Request, number: Int, ask: AskSession) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .toolTip(AskCopy.waiting)
            Text(request.words)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .playtestControl("Agent Waiting \(number) Words", detail: request.words)
            Button { ask.cancelWaiting(request.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(IconActionButtonStyle(diameter: 20, restingTint: .secondary))
            .toolTip(AskCopy.cancelWaitingTooltip)
            .playtestControl("Agent Waiting \(number) Cancel", detail: AskCopy.cancelWaitingTooltip)
        }
        .padding(.vertical, 1)
        .contentShape(.rect)
        .contextMenu {
            Button(AskCopy.cancelWaiting) { ask.cancelWaiting(request.id) }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .playtestControl("Agent Waiting \(number)", detail: "\(request.words), waiting")
    }

    /// Clear History's yes or no, where the group's menu was clicked: no
    /// window to come up, and the keyboard stays with the canvas.
    private func clearQuestion(_ ask: AskSession) -> some View {
        HStack(spacing: 6) {
            Text(AskCopy.clearHistoryQuestion)
                .font(.system(size: 11.5, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(AskCopy.clearHistoryTip)
            Button(AskCopy.clearHistoryCancel) { ask.cancelClearHistory() }
                .controlSize(.small)
                .playtestControl("Agent Clear Cancel", detail: AskCopy.clearHistoryCancel)
            // No destructive role: with one, a click on this button did nothing
            // in a window that was not key (`ask-one-agent-pane-walk`, 2026-11-04).
            Button(AskCopy.clearHistoryYes) { ask.clearHistory() }
                .controlSize(.small)
                .help(AskCopy.clearHistoryTip)
                .playtestControl("Agent Clear Yes", detail: AskCopy.clearHistoryYes)
        }
        .playtestControl("Agent Clear Question", detail: AskCopy.clearHistoryQuestion)
    }

    /// The mock's `.chat-in`: ask again from the panel.
    private func chatIn(_ ask: AskSession) -> some View {
        @Bindable var ask = ask
        return VStack(alignment: .leading, spacing: 6) {
            if fieldHasFocus { AskCommandsList() }
            HStack(spacing: 6) {
                TextField(AskCopy.composerPlaceholder, text: $ask.draft)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($fieldHasFocus)
                    .askFieldKeys(ask, in: editorState)
                    .help(AskCopy.composerTip)
                    .playtestControl("Agent Request", detail: "the Agent group's field")
                Button { ask.submit(in: editorState) } label: {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!ask.canSubmit)
                .toolTip(AskCopy.buttonTooltip)
            }
        }
        .padding(.top, 2)
    }
}

/// What the field does with its keys, in every field Ask has: Return runs the
/// picked command or asks, the arrows move the pick, and every word typed
/// reads the list again.
private struct AskFieldKeys: ViewModifier {
    let ask: AskSession
    let editor: EditorState

    func body(content: Content) -> some View {
        content
            .onSubmit { ask.submit(in: editor) }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                guard ask.isListingCommands else { return .ignored }
                ask.moveCommandPick(by: press.key == .upArrow ? -1 : 1)
                return .handled
            }
            .onChange(of: ask.draft, initial: true) { ask.refreshCommands(in: editor) }
    }
}

extension View {
    fileprivate func askFieldKeys(_ ask: AskSession, in editor: EditorState) -> some View {
        modifier(AskFieldKeys(ask: ask, editor: editor))
    }
}

/// The mock's `.askcmd`: `/` turns the field into this list, directly above
/// it, where the person is already looking. What can run now comes first, and
/// the rest sit dimmed under it, saying in their tip what they need.
struct AskCommandsList: View {
    @Environment(EditorState.self) private var editorState

    private static let maxHeight: CGFloat = 196

    var body: some View {
        let ask = editorState.ask
        if ask.isListingCommands {
            let listing = ask.commands
            VStack(alignment: .leading, spacing: 2) {
                Text(AskCopy.commandsHeader.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                if listing.rows.isEmpty {
                    Text(AskCopy.noCommands)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .playtestControl("Ask Commands Empty", detail: AskCopy.noCommands)
                } else {
                    rows(listing, ask: ask)
                }
            }
            .playtestControl("Ask Commands", detail: "\(listing.rows.count) rows, \(listing.runnableCount) can run")
        }
    }

    private func rows(_ listing: AskCommandList.Listing, ask: AskSession) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(listing.rows.enumerated()), id: \.element.id) { index, entry in
                        row(entry, index: index, listing: listing, ask: ask).id(entry.id)
                    }
                }
            }
            .frame(maxHeight: Self.maxHeight)
            .fixedSize(horizontal: false, vertical: listing.rows.count <= 5)
            .onChange(of: listing.highlight) { _, now in
                guard listing.rows.indices.contains(now) else { return }
                scroller.scrollTo(listing.rows[now].id)
            }
        }
    }

    private func row(_ entry: AskCommandEntry, index: Int, listing: AskCommandList.Listing,
                     ask: AskSession) -> some View {
        let canRun = index < listing.runnableCount
        let picked = canRun && index == listing.highlight
        return Button { ask.runCommand(entry, in: editorState) } label: {
            HStack(spacing: 10) {
                Image(systemName: Self.symbol(entry.area))
                    .font(.system(size: 12))
                    .frame(width: 16)
                // The menu's words win the row: in the panel's narrow column
                // the API name gives way, never the name a person reads.
                Text(entry.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text(entry.apiName)
                    .font(.system(size: 9.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(canRun ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(picked ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canRun)
        .focusEffectDisabled()
        .playtestHover { over in if over, canRun { ask.pickCommand(at: index) } }
        .help(canRun ? entry.menu : AskCopy.commandNeeds(entry))
        .playtestControl("Ask Command \(entry.title)", detail: canRun ? entry.apiName : "can't run now")
    }

    /// The mock gives each row an icon; the table knows a command's area.
    private static func symbol(_ area: AppCommand.Area) -> String {
        switch area {
        case .timeline: "film"
        case .layers: "square.3.layers.3d"
        case .edit: "pencil"
        case .measure: "ruler"
        case .view: "eye"
        case .document: "doc"
        }
    }
}

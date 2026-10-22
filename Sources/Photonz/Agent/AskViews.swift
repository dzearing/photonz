import PhotonzCore
import SwiftUI

// The three places Ask shows (`docs/design/ask.md`, the mock
// `agent-generate-wt.html`): the Ask button in the title bar, the composer it
// opens over the canvas, and the Agent group in the dock that holds a row for
// each change.
// No model is chosen anywhere here: that lives in Settings (the user,
// 2026-10-19).

/// The title bar's Ask button, the mock's `.askbtn`: sparkle, Ask, and the key.
struct AskTitlebarButton: View {
    @Environment(EditorState.self) private var editorState

    static let width: CGFloat = 76

    var body: some View {
        let ask = editorState.ask
        Button {
            ask.isComposerShown ? ask.closeComposer() : ask.summon(in: editorState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text(AskCopy.button)
                    .font(.system(size: 12, weight: .medium))
                // Only where ⌘K is Ask: on a video it is Premiere's Add Edit.
                if !editorState.documentHasTime {
                    Text("⌘K")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .frame(width: Self.width, height: TitlebarPanelToggle.barHeight)
        .toolTip(AskCopy.buttonTooltip, key: editorState.documentHasTime ? nil : "⌘K", below: true)
        .playtestControl("Ask", detail: "the title bar's Ask button")
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
            HStack(alignment: .bottom, spacing: 8) {
                TextField(AskCopy.composerPlaceholder, text: $ask.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...4)
                    .focused($fieldHasFocus)
                    .onSubmit { ask.ask(in: editorState) }
                    .playtestControl("Ask Request", detail: "the Ask composer's field")
                Button { ask.ask(in: editorState) } label: {
                    Label(AskCopy.button, systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(ask.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

/// The Agent group in the dock: one row a request, newest at the top, each
/// saying what changed, with a switch to turn it off and on and a delete. The
/// steps themselves are never shown (the user, 2026-10-20). Requests sent
/// while one works sit above it, newest first, each with a cancel, so a
/// request moves down the list as it goes and never jumps.
struct AgentPanel: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let ask = editorState.ask
        let rows = ask.changes.shown
        let waiting = ask.line.shown
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(waiting.enumerated()), id: \.element.id) { index, request in
                // Numbered in the order they will run: 1 is next.
                waitingRow(request, number: waiting.count - index, ask: ask)
            }
            switch ask.phase {
            case .planning, .running:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(ask.asked.isEmpty ? AskCopy.workingLine : ask.asked)
                        .font(.system(size: 11.5))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(AskCopy.stop) { ask.stop() }.controlSize(.small)
                        .toolTip(AskCopy.stopTooltip)
                        .playtestControl("Agent Stop", detail: AskCopy.stop)
                }
                .help(ask.asked)
                .playtestControl("Agent Working", detail: ask.asked)
            case .stopped(let sentence):
                Text(sentence)
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .playtestControl("Ask Says", detail: sentence)
            case .idle, .ran:
                if rows.isEmpty && waiting.isEmpty {
                    Text(AskCopy.empty).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            if !rows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            changeRow(row, number: index + 1, ask: ask)
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

    private func changeRow(_ row: AskChangeList.Row, number: Int, ask: AskSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // The mock's Last change click: the words pick what it made.
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
                .help(row.asked)
                .playtestControl("Agent Change \(number) Words", detail: row.sentence)
                voteButtons(row, number: number, ask: ask)
                Toggle("", isOn: Binding(get: { row.isOn },
                                         set: { ask.setChange(row.id, on: $0, in: editorState) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help(row.isOn ? AskCopy.turnOff : AskCopy.turnOn)
                    .playtestControl("Agent Change \(number) Switch", detail: row.isOn ? "on" : "off")
                Button { ask.deleteChange(row.id, in: editorState) } label: {
                    Image(systemName: "trash").font(.system(size: 10.5))
                }
                .buttonStyle(IconActionButtonStyle(diameter: 20, restingTint: .secondary))
                .toolTip(AskCopy.deleteTooltip)
                .playtestControl("Agent Change \(number) Delete", detail: AskCopy.deleteTooltip)
            }
            if let note = row.note {
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .playtestControl("Agent Change \(number) Note", detail: note)
            }
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .contextMenu {
            Button(row.isOn ? AskCopy.turnOff : AskCopy.turnOn) {
                ask.setChange(row.id, on: !row.isOn, in: editorState)
            }
            Button(AskCopy.delete) { ask.deleteChange(row.id, in: editorState) }
            Divider()
            Toggle(AskCopy.goodResult, isOn: Binding(get: { row.verdict == .up },
                                                     set: { _ in ask.vote(.up, on: row.id, in: editorState) }))
            Toggle(AskCopy.badResult, isOn: Binding(get: { row.verdict == .down },
                                                    set: { _ in ask.vote(.down, on: row.id, in: editorState) }))
        }
        .playtestControl("Agent Change \(number)", detail: "\(row.sentence), \(row.isOn ? "on" : "off")")
    }

    /// A quiet thumbs up and down, faint until picked. A thumbs down keeps
    /// the request as a test case the eval has never seen.
    private func voteButtons(_ row: AskChangeList.Row, number: Int, ask: AskSession) -> some View {
        HStack(spacing: 0) {
            ForEach([AskVerdict.up, .down], id: \.self) { verdict in
                let picked = row.verdict == verdict
                let name = verdict == .up ? "Up" : "Down"
                Button { ask.vote(verdict, on: row.id, in: editorState) } label: {
                    Image(systemName: "hand.thumbs\(verdict == .up ? "up" : "down")\(picked ? ".fill" : "")")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(IconActionButtonStyle(diameter: 20, restingTint: picked ? .primary : Color.secondary.opacity(0.7)))
                .toolTip(verdict == .up ? AskCopy.goodResult : AskCopy.badResult)
                .playtestControl("Agent Change \(number) Thumbs \(name)", detail: picked ? "picked" : "not picked")
            }
        }
    }

    /// The mock's `.chat-in`: ask again from the dock.
    private func chatIn(_ ask: AskSession) -> some View {
        @Bindable var ask = ask
        return HStack(spacing: 6) {
            TextField(AskCopy.composerPlaceholder, text: $ask.draft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .onSubmit { ask.ask(in: editorState) }
                .playtestControl("Agent Request", detail: "the Agent group's field")
            Button { ask.ask(in: editorState) } label: {
                Image(systemName: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(ask.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .toolTip(AskCopy.buttonTooltip)
        }
        .padding(.top, 2)
    }
}

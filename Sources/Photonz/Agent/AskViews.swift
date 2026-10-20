import PhotonzCore
import SwiftUI

// The three places Ask shows (`docs/design/ask.md`, the mock
// `agent-generate-wt.html`): the Ask button in the title bar, the composer it
// opens over the canvas, and the Agent group in the dock that holds the plan.
// No model is chosen anywhere here: that lives in Settings (the user,
// 2026-10-19).

/// The title bar's Ask button, the mock's `.askbtn`: sparkle, Ask, and the key.
struct AskTitlebarButton: View {
    @Environment(EditorState.self) private var editorState

    static let width: CGFloat = 76

    var body: some View {
        let ask = editorState.ask
        Button {
            ask.isComposerShown ? ask.closeComposer() : ask.openComposer()
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
                .disabled(ask.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ask.isBusy)
                .playtestControl("Ask Send", detail: "the Ask composer's Ask button")
            }
        }
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

/// The Agent group in the dock: what was asked, the plan, and Run Plan.
struct AgentPanel: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let ask = editorState.ask
        VStack(alignment: .leading, spacing: 8) {
            if !ask.asked.isEmpty {
                Text(ask.asked)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(ask.asked)
            }
            switch ask.phase {
            case .idle:
                Text(AskCopy.empty).font(.system(size: 11.5)).foregroundStyle(.secondary)
            case .planning:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(AskCopy.planningLine).font(.system(size: 11.5))
                    Spacer()
                    Button(AskCopy.stop) { ask.stop() }.controlSize(.small)
                }
            case .stopped(let sentence):
                Text(sentence)
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .playtestControl("Ask Says", detail: sentence)
            case .planned, .running, .ran:
                planList(ask)
                runRow(ask)
            }
            chatIn(ask)
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func planList(_ ask: AskSession) -> some View {
        if let plan = ask.plan {
            Text(AskCopy.planHeader)
                .font(.system(size: 11, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                        planRow(index + 1, plan.line(index + 1), done: index < ask.stepsRun,
                                skipped: ask.skipped[index + 1])
                    }
                }
            }
            .frame(maxHeight: 240)
            .fixedSize(horizontal: false, vertical: plan.steps.count <= 10)
        }
    }

    private func planRow(_ number: Int, _ line: AskStep.Line, done: Bool, skipped: String?) -> some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .frame(width: 18, height: 18)
                .background(.quaternary, in: .rect(cornerRadius: 6))
            Text(line.name)
                .font(.system(size: 10.5, design: .monospaced))
                .fixedSize()
            Text(line.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let skipped {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .help("\(AskCopy.skippedTip) \(skipped)")
            } else if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .frame(height: 22)
        .playtestControl("Ask Step \(number)", detail: "\(line.name) \(line.detail)\(skipped != nil ? ", passed over" : done ? ", done" : "")")
    }

    @ViewBuilder
    private func runRow(_ ask: AskSession) -> some View {
        PanelFieldRow("Run") {
            switch ask.phase {
            case .running:
                Button(AskCopy.stop) { ask.stop() }.controlSize(.small)
            case .ran:
                EmptyView()
            default:
                Button { ask.runPlan(in: editorState) } label: {
                    Label(AskCopy.runPlan, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .playtestControl("Run Plan", detail: "the Agent group's Run Plan button")
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
            .disabled(ask.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ask.isBusy)
            .toolTip(AskCopy.buttonTooltip)
        }
        .padding(.top, 2)
    }
}

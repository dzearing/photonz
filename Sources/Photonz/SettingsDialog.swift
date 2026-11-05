import AppKit
import PhotonzCore
import SwiftUI

/// The Settings window's one page: General (opening at login) at the top, then
/// the questions you have told Photonz to stop asking and the way back from
/// each of them, then the sections a Next switch adds.
///
/// One page, so there is no sidebar. The questions list ONLY what was actually
/// silenced: a page of unticked switches would be an invitation to go and turn
/// warnings off, which is the opposite of what this is for (UX-PATTERNS §3,
/// "The question you can silence").
struct SettingsDialog: View {
    /// Where the answers live. Injected so a preview or a render harness can
    /// show a page with rows on it without touching the real defaults.
    private let store: SilencedQuestions
    /// What is silenced right now. Held rather than read every draw so pressing
    /// a button animates the row away instead of the list flickering.
    @State private var rows: [SettingsWindowModel.QuestionRow]
    /// Each capture shortcut's state, asked for fresh.
    private let shortcuts: () -> [CaptureShortcutReport.Row]

    init(store: SilencedQuestions, shortcuts: @escaping () -> [CaptureShortcutReport.Row]) {
        self.store = store
        self.shortcuts = shortcuts
        _rows = State(initialValue: SettingsWindowModel.rows(of: store))
    }

    private var jump: SettingsJump { SettingsJump.shared }

    var body: some View {
        ScrollViewReader { proxy in
            page
                .onAppear { land(proxy) }
                .onChange(of: jump.pass) { land(proxy) }
        }
    }

    /// Brings the section asked for to the top, once the page is laid out.
    private func land(_ proxy: ScrollViewProxy) {
        guard let section = jump.section else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            proxy.scrollTo(section, anchor: .top)
            jump.landed()
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            Form {
                // Whether Photonz opens by itself at login. First, because it
                // is the one setting every copy of the app has.
                GeneralSettingsSection()
                // Which capture shortcuts really reach Photonz. A key macOS
                // keeps never does, and its picture misses the clipboard.
                CaptureShortcutsSettingsSection(rows: shortcuts)
                Section {
                    if rows.isEmpty {
                        emptyRow
                    } else {
                        ForEach(rows) { row in
                            questionRow(row)
                        }
                    }
                } header: {
                    header
                }
                // Which model answers Ask (Next, `next-ask`).
                if Experiments.shared.askEnabled {
                    AskSettingsSection()
                        .id(SettingsSection.ask)
                }
                // Using Photonz from Claude Code and Copilot (Next,
                // `next-agent-channel`): the server and skill ship in the app.
                if Experiments.shared.agentChannelEnabled {
                    AgentsSettingsSection()
                }
            }
            .formStyle(.grouped)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // Sized to what is actually on the page rather than to what a settings
        // window usually looks like: with one question silenced, a window of the
        // usual height is two thirds empty and reads as unfinished. This holds
        // the General switch and both of today's questions without scrolling
        // and grows from there.
        .frame(minWidth: 460, idealWidth: 520, minHeight: 260, idealHeight: 560)
        .animation(.easeOut(duration: 0.18), value: rows)
        // Silencing happens in an editor window while this one is open, so the
        // page re-reads whenever it comes back to the front.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            reload()
        }
    }

    // MARK: - Header

    /// The questions section's heading, styled like every other section's,
    /// with the sentence saying how a question gets here under it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(SettingsWindowModel.questionsTitle)
            Text(SettingsWindowModel.questionsBlurb)
                .font(.callout.weight(.regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rows

    /// One silenced question: the command in the words of its own menu row, the
    /// sentence saying what it was protecting, and the button that hands it
    /// back.
    private func questionRow(_ row: SettingsWindowModel.QuestionRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.command)
                    .font(.body.weight(.medium))
                Text(row.warns)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(SettingsWindowModel.askAgainButton) { askAgain(row) }
                .playtestControl(SettingsWindowModel.askAgainButton, detail: row.command)
        }
        .padding(.vertical, 2)
    }

    /// The normal state. It reads as reassurance rather than as an unfinished
    /// screen, which is the whole reason the page says anything at all when it
    /// has nothing to list.
    private var emptyRow: some View {
        Text(SettingsWindowModel.emptyMessage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            // Marked as a row rather than a control: it is a line of the page,
            // not something to press, and a walk claiming the page went back to
            // normal claims the very words on screen rather than a name
            // invented for it.
            .playtestTarget(SettingsWindowModel.emptyMessage, kind: .row)
    }

    // MARK: - Acting

    private func askAgain(_ row: SettingsWindowModel.QuestionRow) {
        store.askAgain(row.question)
        reload()
    }

    private func reload() {
        rows = SettingsWindowModel.rows(of: store)
    }
}

import AppKit
import PhotonzCore
import SwiftUI

/// The Settings window's one page: the questions you have told Photonz to stop
/// asking, and the way back from each of them.
///
/// The window exists for this and nothing else yet, so there is no sidebar and
/// no second page to pick between. The page lists ONLY what was actually
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

    init(store: SilencedQuestions) {
        self.store = store
        _rows = State(initialValue: SettingsWindowModel.rows(of: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    if rows.isEmpty {
                        emptyRow
                    } else {
                        ForEach(rows) { row in
                            questionRow(row)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        // The header sits outside the Form, which paints its own backdrop, so
        // the whole surface gets the window background explicitly.
        .background(Color(nsColor: .windowBackgroundColor))
        // Sized to what is actually on the page rather than to what a settings
        // window usually looks like: with one question silenced, a window of the
        // usual height is two thirds empty and reads as unfinished. This holds
        // both of today's questions without scrolling and grows from there.
        .frame(minWidth: 460, idealWidth: 520, minHeight: 220, idealHeight: 320)
        .animation(.easeOut(duration: 0.18), value: rows)
        // Silencing happens in an editor window while this one is open, so the
        // page re-reads whenever it comes back to the front.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            reload()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(SettingsWindowModel.questionsTitle)
                .font(.title2.weight(.semibold))
            Text(SettingsWindowModel.questionsBlurb)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
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

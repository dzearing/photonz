import AppKit
import PhotonzCore
import SwiftUI

/// The Tutorials window: every track, the guides on it, how long each takes,
/// and which ones you have finished.
///
/// Everything on screen is read off `TutorialHubModel`, which is read off the
/// catalogue. Nothing here knows the name of any guide, so a guide added to the
/// data turns up here with this file untouched. Same for the words: the row
/// button's title, the status line and the per track count are all generated in
/// PhotonzCore, where a test runs the copy rules over them.
///
/// The look is the Experiments window's: a header outside a grouped `Form`, one
/// `Section` per track. That is the app's existing settings surface rather than
/// a fourth kind of window.
struct TutorialHubView: View {
    let coordinator: AppCoordinator
    /// Starting a guide closes the window, so it is not sitting in front of the
    /// control the first step points at.
    let dismiss: () -> Void

    /// The live progress store. Observed, so finishing a guide in the editor
    /// updates this list behind it without anything being told to refresh.
    @State private var controller = TutorialController.shared
    /// Confirmation before the one action here that loses something.
    @State private var confirmingResetAll = false

    private var model: TutorialHubModel {
        TutorialHubModel(progress: controller.progress)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.isEmpty {
                empty
            } else {
                Form {
                    ForEach(model.tracks) { track in
                        trackSection(track)
                    }
                }
                .formStyle(.grouped)
            }
            if model.anyProgress {
                footer
            }
        }
        // The header sits outside the Form, which paints its own backdrop, so
        // the whole surface gets the window background explicitly.
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 560)
        .confirmationDialog("Reset every tutorial?", isPresented: $confirmingResetAll) {
            Button("Reset Everything", role: .destructive) { controller.forgetAllProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every guide goes back to unfinished. The guides themselves are not changed.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TutorialHubModel.windowTitle)
                .font(.title2.weight(.semibold))
            Text(TutorialHubModel.blurb)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    private var empty: some View {
        Text(TutorialHubModel.emptyLine)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - A track

    private func trackSection(_ track: TutorialHubModel.Track) -> some View {
        Section {
            ForEach(track.rows) { row in
                guideRow(row, in: track)
            }
        } header: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(track.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(track.progressLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(track.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(track.title). \(track.blurb) \(track.progressLine).")
        }
    }

    // MARK: - A guide

    private func guideRow(_ row: TutorialHubModel.Row, in track: TutorialHubModel.Track) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // The finished mark. The width is held whether or not the mark is
            // there, so every title on the track starts on the same line.
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .font(.system(size: 14))
                .opacity(row.state == .finished ? 1 : 0)
                .frame(width: 16)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .fontWeight(.medium)
                    Text(row.length)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(row.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let status = row.statusLine {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowReading(row))
            Spacer(minLength: 8)
            Button(row.actionTitle) { start(row.guide) }
                .accessibilityLabel("\(row.actionTitle) \(row.title)")
                .disabled(!canStart(row.guide))
                .help(canStart(row.guide)
                      ? "\(row.actionTitle) this guide. It takes \(row.length)."
                      : "This guide runs over a picture you have open. Open one first.")
            // Only a guide with something to forget offers to forget it. A list
            // of guides nobody has run is not a list of menus.
            //
            // The SLOT is there either way, so finishing a guide does not shove
            // every button on the track sideways as the menu appears.
            Group {
                if row.hasProgress {
                    Menu {
                        Button(TutorialHubModel.startOverTitle) { startOver(row.guide) }
                        Button(TutorialHubModel.forgetOneTitle) { controller.forgetProgress(row.guide.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("More for \(row.title)")
                }
            }
            .frame(width: 20)
        }
        .padding(.vertical, 2)
    }

    /// One row read out loud, in the order a person needs it: what it is, how
    /// long it takes, and where they got to.
    private func rowReading(_ row: TutorialHubModel.Row) -> String {
        var reading = "\(row.title). \(row.summary) Takes \(row.length)."
        if let status = row.statusLine { reading += " \(status)." }
        return reading
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button(TutorialHubModel.resetAllTitle) { confirmingResetAll = true }
                .help("Every guide goes back to unfinished.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Starting one

    /// A guide that brings its own sample opens its own window, so it can
    /// always run. A guide that teaches something about YOUR picture needs one
    /// to be open.
    private func canStart(_ guide: TutorialGuide) -> Bool {
        guide.sample != nil || TutorialLauncher.frontEditor() != nil
    }

    private func start(_ guide: TutorialGuide) {
        dismiss()
        TutorialLauncher.start(guide, coordinator: coordinator,
                               editor: TutorialLauncher.frontEditor())
    }

    private func startOver(_ guide: TutorialGuide) {
        controller.forgetProgress(guide.id)
        start(guide)
    }
}

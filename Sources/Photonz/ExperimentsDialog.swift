import AppKit
import PhotonzCore
import SwiftUI

/// The Experiments window: pick which Photonz you run, and tune the feature
/// flags for either release.
///
/// Two jobs on one surface, kept visually apart so they can't be confused:
/// the top picks which release you are LOOKING AT (and offers an explicit
/// button to switch to it), the list below edits that release's flags. Nothing
/// switches release by accident, and the bar at the bottom says out loud that a
/// switch waits for a relaunch.
struct ExperimentsDialog: View {
    @Bindable var experiments: Experiments
    /// The release whose flags are on screen. Starts on the running one.
    @State private var browsing: Release
    /// Word wheel over the flag list: type to narrow it down.
    @State private var query = ""
    /// Flags whose parameters are open. Collapsed is the default: most of the
    /// time a flag is just an on/off switch, and its knobs are noise.
    @State private var expandedFlags: Set<String> = []

    /// The defaults are the real entry point: browse the running release, no
    /// search, everything collapsed. The parameters exist so previews and
    /// render harnesses can show a different state.
    init(experiments: Experiments, browsing: Release? = nil,
         expanded: Set<String> = [], query: String = "") {
        self.experiments = experiments
        _browsing = State(initialValue: browsing ?? experiments.release)
        _expandedFlags = State(initialValue: expanded)
        _query = State(initialValue: query)
    }

    private var settings: FeatureFlagSettings { experiments.settings(for: browsing) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                releaseSection
                flagSection
            }
            .formStyle(.grouped)
            if experiments.needsRelaunch {
                relaunchBar
            }
        }
        // The header sits outside the Form, which paints its own backdrop, so
        // give the whole surface the window background explicitly.
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 520, idealWidth: 560, minHeight: 460, idealHeight: 640)
        .animation(.easeOut(duration: 0.18), value: experiments.needsRelaunch)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Experiments")
                .font(.title2.weight(.semibold))
            Text("Two versions of Photonz ship in one app. Public is the one you rely on. Next is where new work lands first.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    // MARK: - Release picker

    private var releaseSection: some View {
        Section("Release") {
            ForEach(Release.allCases) { release in
                releaseRow(release)
            }
        }
    }

    private func releaseRow(_ release: Release) -> some View {
        let isBrowsing = browsing == release
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: isBrowsing ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isBrowsing ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .font(.system(size: 14))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(release.title)
                        .fontWeight(.medium)
                    if release == experiments.release {
                        badge("Running now", tint: .green)
                    }
                    if release == experiments.selectedRelease && experiments.needsRelaunch {
                        badge("Starts next launch", tint: .orange)
                    }
                }
                Text(release.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if release != experiments.selectedRelease {
                Button("Switch to \(release.title)") {
                    experiments.selectedRelease = release
                    browsing = release
                }
                .help("Takes effect the next time Photonz starts.")
            }
        }
        .contentShape(.rect)
        // Selecting a row only changes which flags you're looking at. Switching
        // release is the separate, explicit button.
        .onTapGesture { browsing = release }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: .capsule)
            .foregroundStyle(tint)
    }

    // MARK: - Flags

    private var visibleFlags: [FeatureFlag] { settings.flags(matching: query) }

    private var flagSection: some View {
        Section {
            searchField
            if visibleFlags.isEmpty {
                Text("No flags match what you typed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
            ForEach(visibleFlags) { flag in
                flagRow(flag)
            }
        } header: {
            HStack {
                Text("Flags for \(browsing.title)")
                Spacer()
                Button("Reset") { experiments.resetToDefaults(for: browsing) }
                    .buttonStyle(.link)
                    .help("Puts \(browsing.title) back to the flags it ships with.")
            }
        } footer: {
            Text(flagFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var flagFooter: String {
        browsing == experiments.release
            ? "Changes apply right away."
            : "Photonz is running \(experiments.release.title). These take effect once \(browsing.title) is running."
    }

    private var searchField: some View {
        SearchField(text: $query, placeholder: "Search flags")
            .frame(height: 22)
            .padding(.vertical, 2)
    }

    /// A flag is an on/off switch first. Its parameters live behind a
    /// disclosure, so the list stays readable and you only see knobs when you
    /// went looking for them.
    private func flagRow(_ flag: FeatureFlag) -> some View {
        let isExpanded = expandedFlags.contains(flag.name)
        let hasParameters = !flag.parameters.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Group {
                    if hasParameters {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .frame(width: 10)
                .padding(.top, 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(flag.title)
                    Text(flag.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { flag.isEnabled },
                    set: { experiments.setEnabled($0, flag: flag.name, in: browsing) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .contentShape(.rect)
            .onTapGesture { toggleExpansion(of: flag) }
            .help(hasParameters ? (isExpanded ? "Hide settings" : "Show settings") : "")
            if hasParameters && isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(flag.parameters) { parameter in
                        parameterRow(parameter, of: flag)
                    }
                }
                .padding(.leading, 18)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.15), value: isExpanded)
    }

    private func toggleExpansion(of flag: FeatureFlag) {
        guard !flag.parameters.isEmpty else { return }
        if expandedFlags.contains(flag.name) {
            expandedFlags.remove(flag.name)
        } else {
            expandedFlags.insert(flag.name)
        }
    }

    // MARK: - Parameter controls

    @ViewBuilder
    private func parameterRow(_ parameter: FeatureParameter, of flag: FeatureFlag) -> some View {
        HStack(spacing: 8) {
            Text(parameter.label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            switch parameter.value {
            case .number(let value):
                numberControl(value, parameter: parameter, of: flag)
            case .string(let value):
                TextField("", text: Binding(
                    get: { value },
                    set: { set(.string($0), parameter, of: flag) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            case .boolean(let value):
                Toggle("", isOn: Binding(
                    get: { value },
                    set: { set(.boolean($0), parameter, of: flag) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            case .enumeration(let cases, let selection):
                Picker("", selection: Binding(
                    get: { selection },
                    set: { set(.enumeration(cases: cases, selection: $0), parameter, of: flag) })) {
                    ForEach(cases, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func numberControl(_ value: Double, parameter: FeatureParameter, of flag: FeatureFlag) -> some View {
        let binding = Binding(
            get: { value },
            set: { set(.number($0), parameter, of: flag) })
        HStack(spacing: 4) {
            TextField("", value: binding, format: .number.precision(.fractionLength(0...2)).grouping(.never))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            if let bounds = parameter.bounds {
                Stepper("", value: binding,
                        in: bounds.minimum...bounds.maximum, step: bounds.step)
                    .labelsHidden()
            } else {
                Stepper("", value: binding, step: 1)
                    .labelsHidden()
            }
        }
    }

    private func set(_ value: FeatureParameterValue, _ parameter: FeatureParameter, of flag: FeatureFlag) {
        experiments.setParameter(parameter.name, of: flag.name, to: value, in: browsing)
    }

    // MARK: - Relaunch bar

    private var relaunchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(experiments.selectedRelease.title) starts the next time Photonz opens.")
                    .fontWeight(.medium)
                Text(AppRelauncher.canRelaunch
                     ? "Photonz is still running \(experiments.release.title) until then."
                     : "Quit Photonz and open it again to switch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Stay on \(experiments.release.title)") {
                experiments.selectedRelease = experiments.release
            }
            if AppRelauncher.canRelaunch {
                Button("Relaunch Now") { AppRelauncher.relaunch() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}


/// The system search field, so the word wheel over the flag list looks and
/// behaves like every other macOS search box (rounded, magnifier, clear button,
/// Escape to empty it). SwiftUI has no equivalent style of its own.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.focusRingType = .default
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) { _text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text = field.stringValue
        }
    }
}

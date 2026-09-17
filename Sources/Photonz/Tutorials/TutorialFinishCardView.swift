import PhotonzCore
import SwiftUI

// The card a guide ends on.
//
// Same plate as the step card it replaces (`TutorialCalloutView`), in the
// middle of the window the guide taught in, with no beak and no ring: it is
// not about a control, it is about the guide being over. What it adds is the
// one thing the end of a guide never had, a way on. The rows are the empty
// window's own onboarding rows (`EditorView.onboardingRow`) rather than a new
// kind of button, because "here are the ways to start" is a thing this app
// already knows how to say.
struct TutorialFinishCardView: View {
    let finish: TutorialFinish
    let onChoose: (TutorialFinishChoice) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(nsColor: .white))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(finish.title)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(finish.message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                // The first row is the default one, so Return does the thing
                // somebody who has just been taught most likely wants.
                ForEach(Array(finish.choices.enumerated()), id: \.element) { index, choice in
                    TutorialFinishRow(choice: choice, isDefault: index == 0,
                                      onChoose: onChoose)
                }
            }
            HStack {
                Spacer(minLength: 0)
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: TutorialCalloutView.width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: TutorialCalloutView.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: TutorialCalloutView.cornerRadius,
                                     style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
    }
}

/// One way on.
///
/// `.plain` rather than the onboarding card's `.borderless`, which looks the
/// same in a real window and is the style the step card's own close button
/// already uses, because a borderless button is one of the things SwiftUI
/// refuses to draw into an offscreen render: every row came back as a yellow
/// bar with a no-entry sign through it, which is what the loop would have been
/// handed on any machine that could not photograph the screen. The row brings
/// its own highlight, so nothing is lost by drawing it ourselves.
private struct TutorialFinishRow: View {
    let choice: TutorialFinishChoice
    let isDefault: Bool
    let onChoose: (TutorialFinishChoice) -> Void

    @State private var hovering = false

    var body: some View {
        Button { onChoose(choice) } label: {
            HStack(spacing: 10) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(isDefault ? Color.accentColor : Color.secondary)
                    .frame(width: 22)
                Text(choice.label)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(isDefault ? .defaultAction : nil)
        .playtestHover { hovering = $0 }
        // Named for a walk, and for a screen reader, by what it DOES rather
        // than by the words it currently wears.
        .accessibilityIdentifier("tutorialFinish.\(choice.name)")
    }

    /// The default row is tinted from the start, so which one Return will press
    /// is something you can see rather than something you have to try.
    private var fill: Color {
        if isDefault { return Color.accentColor.opacity(hovering ? 0.22 : 0.12) }
        return Color.primary.opacity(hovering ? 0.08 : 0)
    }
}

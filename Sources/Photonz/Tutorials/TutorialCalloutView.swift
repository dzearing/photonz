import AppKit
import PhotonzCore
import SwiftUI

// What a walkthrough step looks like.
//
// Two surfaces, and keeping them apart is the whole design:
//
//  * The CUE, a ring around the control the step is about. It is the mock's
//    `.wt-cue` (walkthrough.css): an accent ring with a pulse, sitting on the
//    real control wherever it happens to be.
//  * The CARD, the words and the one button. In the mock this is a panel under
//    the app screenshot, because a web page has an under. A real window does
//    not, so the card floats beside the control with a beak, the same shape and
//    the same placement law the app's own tooltip uses (UX-PATTERNS D12, and
//    D14: a callout never covers what it is talking about).
//
// Neither one is modal and neither one dims the app. You are driving the real
// thing the whole time, which is the point of the exercise.

/// The card: step number, what this is, what to do, and the way on.
struct TutorialCalloutView: View {
    let number: Int
    let count: Int
    let title: String
    let message: String
    /// One line the APP adds when the control the step named is not on the bar
    /// in its own right: which button it is inside, and how to reach it. Nil
    /// whenever the ring is on the control the step really named, which is
    /// almost always. Set apart from `message` because it is not the guide
    /// author speaking, it is the app saying where the thing went
    /// (`TutorialConcealment`).
    var note: String? = nil
    /// "Next", "Done", or "Skip This Step" for a step that is waiting on you.
    let buttonTitle: String
    let canGoBack: Bool
    /// Which side of the control the card ended up on, so the beak knows which
    /// edge it lives on.
    let side: TutorialSide
    /// Where the beak's tip goes, measured from the card's leading edge for a
    /// card above or below and from its top edge for one beside. Nil draws no
    /// beak at all, which is what an honest card does when it has been pushed
    /// somewhere that does not line up with the control.
    let beakOffset: CGFloat?

    let onBack: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    /// The card's width is fixed. The overlay measures the height at this width
    /// and hands both to the placement, so the card never resizes itself out
    /// from under the beak.
    static let width: CGFloat = 320
    static let beakHeight: CGFloat = HintTooltipView.beakSize.height
    static let beakWidth: CGFloat = HintTooltipView.beakSize.width
    static let cornerRadius: CGFloat = 12

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(nsColor: .white))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        whereItIs(note)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the guide")
                .help("Close the guide")
            }
            HStack(spacing: 8) {
                // How far along you are. A plain count, not a row of dots you
                // can click: a dot promises you can jump to step five, and step
                // five may depend on something step three made.
                Text("\(number) of \(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Button("Back", action: onBack)
                    .disabled(!canGoBack)
                Button(buttonTitle, action: onNext)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: Self.width, alignment: .leading)
    }

    /// The "it is inside this one" line: a small pointing hand and the
    /// sentence, tinted so it reads as the app helping rather than as more of
    /// the lesson. Never a button: opening the list is the person's move.
    private func whereItIs(_ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(note)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.top, 2)
    }

    var body: some View {
        plate
            .padding(beakEdge, Self.beakHeight)
            .frame(width: Self.width + horizontalBeakRoom, alignment: plateAlignment)
    }

    private var plate: some View {
        card
            .background {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            }
            .overlay(alignment: beakAlignment) { beak }
    }

    // MARK: The beak

    private var beakEdge: Edge.Set {
        switch side {
        case .above: .bottom
        case .below: .top
        case .leading: .trailing
        case .trailing, .automatic: .leading
        }
    }

    private var horizontalBeakRoom: CGFloat {
        (side == .leading || side == .trailing || side == .automatic) ? Self.beakHeight : 0
    }

    private var plateAlignment: Alignment {
        switch side {
        case .leading: .leading
        case .trailing, .automatic: .trailing
        default: .center
        }
    }

    private var beakAlignment: Alignment {
        switch side {
        case .above: .bottomLeading
        case .below: .topLeading
        case .leading: .topTrailing
        case .trailing, .automatic: .topLeading
        }
    }

    /// The tooltip's own beak shape, so the two read as one family. Hung half a
    /// pixel into the plate, so two shapes meant to be one show no hairline.
    @ViewBuilder
    private var beak: some View {
        if let beakOffset {
            let shape = HintBeak()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: Self.beakWidth, height: Self.beakHeight)
            switch side {
            case .above:
                shape
                    .offset(x: beakOffset - Self.beakWidth / 2, y: Self.beakHeight - 0.5)
            case .below:
                shape.rotationEffect(.degrees(180))
                    .offset(x: beakOffset - Self.beakWidth / 2, y: -(Self.beakHeight - 0.5))
            case .leading:
                shape.rotationEffect(.degrees(-90))
                    .offset(x: (Self.beakWidth - Self.beakHeight) / 2 + Self.beakHeight - 0.5,
                            y: beakOffset - Self.beakWidth / 2)
            case .trailing, .automatic:
                shape.rotationEffect(.degrees(90))
                    .offset(x: -((Self.beakWidth - Self.beakHeight) / 2 + Self.beakHeight - 0.5),
                            y: beakOffset - Self.beakWidth / 2)
            }
        }
    }
}

/// The ring on the control itself: the mock's `.wt-cue`, an accent outline with
/// a pulse going out of it. It draws and nothing else. The panel carrying it
/// ignores the mouse, so the control under it is pressed exactly as it would be
/// with no guide running.
struct TutorialCueView: View {
    /// How far the ring sits outside the control.
    static let padding: CGFloat = 5
    /// Room for the pulse to expand into, outside the ring.
    static let pulseRoom: CGFloat = 14

    /// The shape of the CONTROL the ring goes round, taken off the step's
    /// anchor (`TutorialAnchor.cueShape`). The ring pushes it out by `padding`
    /// so the two stay concentric: a pill bar gets a pill, a round tool button
    /// gets a circle, and a run of panel rows keeps its squarer corner.
    let shape: TutorialCueShape

    @State private var pulsing = false

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        ZStack {
            ring(lineWidth: 2, color: .accentColor)
                .background { ring(lineWidth: 5, color: Color.accentColor.opacity(0.22)) }
            if reduceMotion {
                ring(lineWidth: 2, color: Color.accentColor.opacity(0.4))
            } else {
                ring(lineWidth: 2, color: .accentColor)
                    .scaleEffect(pulsing ? 1.28 : 1)
                    .opacity(pulsing ? 0 : 0.75)
                    .animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false),
                               value: pulsing)
            }
        }
        .padding(Self.pulseRoom)
        .allowsHitTesting(false)
        .onAppear { pulsing = true }
    }

    /// One outline, in the control's own shape. Written as a switch over the
    /// two concrete shapes rather than through `AnyShape`, because
    /// `strokeBorder` — the stroke that stays INSIDE the outline, so the ring
    /// never creeps over the control — is only offered by an insettable shape
    /// and `AnyShape` is not one.
    @ViewBuilder
    private func ring(lineWidth: CGFloat, color: Color) -> some View {
        switch shape.outset(by: Self.padding) {
        case .pill:
            // Plain `Capsule()`, which is `.circular`: the same curve the tool
            // bar's own glass and the round tool buttons are drawn with. A
            // continuous capsule here would miss them by a hair, which is the
            // whole complaint this shape exists to answer.
            Capsule().strokeBorder(color, lineWidth: lineWidth)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: lineWidth)
        }
    }
}

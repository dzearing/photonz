import PhotonzCore
import SwiftUI

/// **Transition**: what happens at the cut you have picked
/// (`docs/design/video-transitions.md`).
///
/// The section is about a CUT, not about a clip, which is the whole thesis said
/// in the panel: it names the two pieces either side, says what spare media
/// each of them has, and shows the bill for whatever is on it. Nothing here
/// moves anything on the timeline, and the copy says so, because the first
/// question anybody has about a dissolve is whether it just pushed the rest of
/// their edit along.
///
/// What the study drew and this does not: the six behaviours are three (the
/// study's own open question asks whether to ship the honest few), "the overlap
/// sits before / across / after" is gone because a dissolve means across, and
/// "hold on black" is gone because inserting real black is inserting a PIECE,
/// not putting something on a cut.
struct TransitionInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cut = editorState.clipCutInHand {
                where_(cut)
                kinds(cut)
                if cut.transition != nil { length(cut) }
                bill(cut)
            } else {
                Text("No cut is picked. Click a join on a clip's bar in the timeline, "
                     + "or stand the playhead on one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        // The panel decides how wide this is, never the words in it: a section
        // that asked for the width of its longest sentence pushed its own
        // numbers off both edges of the dock (seen on the first walk).
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Which cut, and what it has to spend

    @ViewBuilder
    private func where_(_ cut: ClipCut) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("At the cut")
                    .font(.system(size: 11))
                Spacer()
                Text(cutTimecode(cut))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .playtestField("Cut reading")
            }
            Text("Piece \(cut.index) goes out, piece \(cut.index + 1) comes in.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ClipTransitionCopy.spare(cut))
                .font(.caption)
                .foregroundStyle(.secondary)
            if cut.isContinuous {
                // The one case where a dissolve would do nothing at all, said
                // before it is chosen rather than after it looks broken.
                Text(ClipTransitionCopy.continuousCut)
                    .font(.caption)
                    .foregroundStyle(.orange)
                        .playtestField("Cut warning")
            }
        }
    }

    /// Where the cut is on the DOCUMENT's own clock, which is the number the
    /// transport and the ruler are showing: the panel and the playhead say the
    /// same thing about the same moment.
    private func cutTimecode(_ cut: ClipCut) -> String {
        let start = editorState.clipInHandID
            .flatMap { editorState.document?.layer(id: $0)?.time?.inMS } ?? 0
        return EditorState.timecode(ms: start + cut.atMS)
    }

    // MARK: What can go on it

    @ViewBuilder
    private func kinds(_ cut: ClipCut) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Type")
                .font(.system(size: 11))
            // A row of choices rather than a menu: there are four answers
            // including the hard cut, each with a reason it is or is not on
            // offer, and a menu would hide both the reason and the fact that
            // one of them is unavailable until it was opened.
            VStack(alignment: .leading, spacing: 3) {
                choice(title: "Hard cut", isOn: cut.transition == nil, canAfford: true) {
                    editorState.setClipTransitionInHand(nil)
                }
                ForEach(ClipTransitionKind.allCases, id: \.self) { kind in
                    let afford = cut.canAfford(kind)
                    choice(title: kind.title, isOn: cut.transition?.kind == kind,
                           canAfford: afford) {
                        editorState.setClipTransitionInHand(kind)
                    }
                    .panelHelp(afford
                               ? "\(kind.title): \(kind.needsOverlap ? "both pieces on screen together, paid for with spare frames either side" : "each piece fades inside the time it already has")"
                               : ClipTransitionCopy.cannotAfford(kind, at: cut))
                }
            }
            // The distinction said ONCE, under the list, rather than as a tag
            // on every row. Four tags down the right hand edge is four things
            // to read to learn one thing.
            Text("Cross dissolve puts both pieces on screen together, so it spends spare media. "
                 + "The dips do not: each piece fades inside the time it already has.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func choice(title: String, isOn: Bool, canAfford: Bool,
                        pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                Text(title)
                    .font(.system(size: 11))
                Spacer(minLength: 4)
                // Only the refusal is written down the edge: a row that says
                // nothing is a row this cut can take.
                if !canAfford {
                    Text("no spare")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canAfford)
        .playtestField(title)
    }

    // MARK: How long

    @ViewBuilder
    private func length(_ cut: ClipCut) -> some View {
        let kind = cut.transition?.kind ?? .dissolve
        let longest = cut.longestMS(of: kind)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Length")
                    .font(.system(size: 11))
                Spacer()
                Text(ClipTransitionCopy.length(cut.drawnTransition?.lengthMS ?? 0))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .playtestField("Length reading")
            }
            Slider(value: Binding(
                get: { Double(cut.drawnTransition?.lengthMS ?? ClipTransition.shortestMS) },
                set: { editorState.setClipTransitionLength(Int($0.rounded())) }
            ), in: Double(ClipTransition.shortestMS)...Double(max(longest, ClipTransition.shortestMS + 1)))
            .controlSize(.small)
            .playtestField("Length")
            .panelHelp("How long the transition takes, measured across the cut. "
                       + "The band on the bar in the timeline is the same number: drag either "
                       + "end of it and this follows.")
            Text("The longest this cut can take is \(ClipTransitionCopy.length(longest)).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: What it costs

    @ViewBuilder
    private func bill(_ cut: ClipCut) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ClipTransitionCopy.bill(cut))
                .font(.caption)
                .foregroundStyle(.secondary)
                .playtestField("Transition bill")
            if let shortened = ClipTransitionCopy.shortened(cut) {
                Text(shortened)
                    .font(.caption)
                    .foregroundStyle(.orange)
                        .playtestField("Transition shortened")
            }
        }
    }
}

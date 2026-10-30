import PhotonzCore
import SwiftUI

/// **At this cut**: the transitions, as tiles, opened right on the cut you
/// clicked (`video-transition-wt.html`, `#transPick`).
///
/// It already knows what this cut can pay for, so it says the spare along its
/// top and every tile says whether it needs an overlap. A tile the cut cannot
/// afford is dimmed rather than hidden, so Cross dissolve never goes missing
/// without a reason: it says "no spare" instead.
///
/// The tiles are YOUR two clips (the user, 2026-10-29): each turns the last
/// frame of the clip going out into the first frame of the one coming in,
/// holding half way at rest and playing its motion while the pointer is on
/// it, and its tip says what happens between the two by name.
struct TransitionPicker: View {
    @Environment(EditorState.self) private var editorState
    let place: TimelineCutPlace

    /// The two frames either side of the cut, once read.
    @State private var pictures = CutPictures()
    /// The tile the pointer is on, which plays.
    @State private var hovered: ClipTransitionKind?

    /// `#transPick{width:248px}`.
    static let width: CGFloat = 248

    var body: some View {
        let documentCut = editorState.document?.documentCut(at: place)
        let cut = documentCut?.cut
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("At this cut")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(VideoKit.Palette.faint)
                    // The mock's closing line (`#pickNote`), in the tip of
                    // the heading it is about: longer than chrome may say.
                    .panelHelp(TransitionInspector.sectionHelp)
                Spacer(minLength: 4)
                if let cut {
                    Text(ClipTransitionCopy.spareShort(cut))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(VideoKit.Palette.faint)
                        .playtestField("Spare at this cut")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Which two clips meet here, so no tile reads as one clip's.
            if let documentCut {
                Text(ClipTransitionCopy.sides(documentCut))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VideoKit.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.top, 3)
                    // A control rather than a field, because a walk reads a
                    // popover's controls and not its fields; nothing presses it.
                    .playtestControl("Clips at this cut: \(ClipTransitionCopy.sides(documentCut))",
                                     detail: "At this cut")
            }

            VideoKit.TileGrid(columns: 2, spacing: 8) {
                ForEach(ClipTransitionKind.allCases, id: \.self) { kind in
                    tile(kind, cut: documentCut)
                }
            }
            .padding(8)
            .playtestField("At this cut")
        }
        .frame(width: Self.width)
        .task(id: editorState.document?.cutShots(at: place)) {
            pictures = await CutPictures.read(editorState.document?.cutShots(at: place))
        }
    }

    @ViewBuilder
    private func tile(_ kind: ClipTransitionKind, cut documentCut: DocumentCut?) -> some View {
        let cut = documentCut?.cut
        let afford = cut?.canAfford(kind) ?? false
        let isOn = cut?.transition?.kind == kind
        let isDefault = editorState.defaultTransitionKind == kind
        Button {
            // The cut wears it in the click's frame, and the pick of the
            // cut, the timeline's tracks, the panel's sections and the menu
            // bar catch up in the next: in one pass the click held the window
            // 47 to 63 ms (`an-editing-session-walk`, 2026-10-18).
            let later = Experiments.shared.panelBuildsWhatYouSeeEnabled
            if later { editorState.catchUpOnTheNextPass() }
            editorState.setTransition(kind, at: place, picksLater: later)
            editorState.closeTransitionPicker()
        } label: {
            VideoKit.Tile(name: kind.title,
                          // One the cut cannot pay for is greyed, and its
                          // tip says why: never a "no spare" caption. A dip
                          // says nothing under its name, but keeps the line
                          // so the grid's rows stay one height.
                          detail: kind.note ?? " ",
                          isSelected: isOn, isDisabled: !afford, emphasis: .cut,
                          thumbnailHeight: 26) {
                CutTransitionFace(style: Self.style(kind), pictures: pictures, plays: hovered == kind)
            }
            .overlay(alignment: .topTrailing) {
                if isDefault { Self.defaultKeycap(kind, in: "At this cut") }
            }
        }
        .buttonStyle(.plain)
        .disabled(!afford)
        // Premiere's right click on a transition in the Effects panel. On the
        // tile, not in a panel row, because it is a verb you do once.
        .contextMenu {
            // The mock's Apply to every cut (`#efxMenu`): twenty cuts in a
            // screen recording take a dissolve in one go, not twenty.
            Button("Apply to Every Cut") { editorState.putTransitionOnEveryCut(kind) }
            Button("Set as Default Transition") { editorState.setDefaultTransition(kind) }
                .disabled(isDefault)
        }
        .playtestHover("\(kind.title) tile") { inside in
            if inside { hovered = kind } else if hovered == kind { hovered = nil }
        }
        .playtestControl(kind.title, detail: "At this cut")
        .panelHelp(afford ? Self.tip(kind, at: documentCut, isDefault: isDefault)
                          : "Not enough spare frames either side of this cut")
    }

    /// What happens between the two clips, by name, and the key where it is
    /// the one ⌘T puts on.
    static func tip(_ kind: ClipTransitionKind, at cut: DocumentCut?, isDefault: Bool) -> String {
        let words = cut.map { ClipTransitionCopy.between(kind, at: $0) } ?? kind.title
        return isDefault ? "\(words), \u{2318}T" : words
    }

    /// ⌘T on the corner of the tile the key puts on a cut: the key and which
    /// one is the default, said at once where the tiles already are.
    static func defaultKeycap(_ kind: ClipTransitionKind, in place: String) -> some View {
        Text("\u{2318}T")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(VideoKit.Palette.ink)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(VideoKit.Palette.glassChrome))
            .overlay(Capsule().strokeBorder(VideoKit.Palette.edgeLo, lineWidth: 1))
            .padding(4)
            .allowsHitTesting(false)
            // Named as a control rather than a field because the walk reads a
            // popover's controls and not its fields; nothing presses it.
            .playtestControl("Default transition \(kind.title)", detail: place)
    }

    static func style(_ kind: ClipTransitionKind) -> VideoKit.TransitionThumbnail.Style {
        switch kind {
        case .dissolve: .dissolve
        case .dipToBlack: .dipToBlack
        case .dipToWhite: .dipToWhite
        case .push: .push
        case .wipe: .wipe
        case .blurThrough: .blurThrough
        case .flip: .flip
        case .cube: .cube
        case .swing: .swing
        case .doorway: .doorway
        case .revolve: .revolve
        case .pushInDepth: .pushInDepth
        }
    }
}

extension View {
    /// Hangs the transition picker off this view, open while `place` is the
    /// cut whose picker is up.
    func transitionPicker(at place: TimelineCutPlace, fromPanel: Bool = false,
                          editorState: EditorState) -> some View {
        popover(isPresented: Binding(
            get: { editorState.transitionPickerPlace == place && editorState.transitionPickerFromPanel == fromPanel },
            set: { if !$0, editorState.transitionPickerPlace == place { editorState.transitionPickerPlace = nil } }),
                arrowEdge: fromPanel ? .leading : .top) {
            TransitionPicker(place: place)
                .environment(editorState)
        }
    }
}

// MARK: - A tile at a cut: the two clips, played on hover

/// The two frames a cut's tiles play between, once read off their files. A
/// side with no recording, or one not read yet, is drawn with the kit's
/// stand-in colour.
struct CutPictures: Equatable {
    var outgoing: CGImage?
    var incoming: CGImage?

    @MainActor
    static func read(_ shots: CutShots?) async -> CutPictures {
        guard shots != nil else { return CutPictures() }
        func picture(_ shot: CutShots.Shot?) async -> CGImage? {
            guard let shot else { return nil }
            return await ClipFilmstripFrames.shared.picture(of: shot.movie, atSourceMS: shot.sourceMS)
        }
        return CutPictures(outgoing: await picture(shots?.outgoing), incoming: await picture(shots?.incoming))
    }
}

/// One tile's picture at a cut: still on the moment that shows the most of
/// both clips, and playing the transition's lap while the pointer is on it.
/// Still for anyone who has asked the system to reduce motion.
struct CutTransitionFace: View {
    let style: VideoKit.TransitionThumbnail.Style
    let pictures: CutPictures
    let plays: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where a tile rests: half way, where both clips are on screen, but a
    /// dip a quarter of the way down, since half way it is only black, and a
    /// turn a third of the way round, since half way a flip is edge on.
    static func restingProgress(_ style: VideoKit.TransitionThumbnail.Style) -> Double {
        switch style {
        case .dipToBlack, .dipToWhite: 0.25
        case .flip, .cube, .swing, .doorway, .revolve, .pushInDepth: 0.3
        default: 0.5
        }
    }

    var body: some View {
        if plays, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let seconds = context.date.timeIntervalSinceReferenceDate
                movie(TransitionTileLoop.progress(atSeconds: seconds))
            }
        } else {
            movie(Self.restingProgress(style))
        }
    }

    private func movie(_ progress: Double) -> some View {
        VideoKit.TransitionMovie(style: style, progress: progress,
                                 outgoing: pictures.outgoing, incoming: pictures.incoming)
    }
}

// MARK: - Every transition tile plays on the one loop

extension VideoKit.ProgressLoop {
    /// `TransitionTileLoop`, the way the kit takes it.
    static let transitionTile: VideoKit.ProgressLoop = {
        let reel = TransitionTileLoop.reel
        return VideoKit.ProgressLoop(progress: reel.shots.map(\.frame), keyTimes: reel.keyTimes,
                                     lapSeconds: Double(reel.lapMS) / 1000)
    }()
}

extension VideoKit.AnimatedTransitionThumbnail {
    init(style: VideoKit.TransitionThumbnail.Style) {
        self.init(style: style, loop: .transitionTile)
    }
}

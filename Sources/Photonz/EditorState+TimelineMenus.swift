import AppKit
import Foundation
import PhotonzCore

// What a right click offers on the timeline: on a clip, on a cut, on the ruler
// and the transport's scrub bar.
//
// A Premiere editor does not hunt for a tool or a panel button to act on a
// clip: they right click it. So every verb the timeline has lives here, on the
// thing it acts on, under Premiere's own names, with the key printed beside
// every row the app answers to. A row never prints a key the app does not
// honour: M, I and O are Photoshop's tool keys on the canvas, and the
// timeline's marks while it has the keyboard, which a right click in the dock
// has just handed it (`EditorState+TimelineKeys`).
//
// The rows are plain `MenuRow`s, the same list type the layer menus use, so a
// row reads the same wherever it is drawn. Each one picks what it was opened
// on before it acts, because a SwiftUI context menu cannot pick on the right
// click itself, and a command must never land on whatever happened to be
// picked before.
extension EditorState {

    // MARK: The keys the rows print

    enum TimelineMenuKeys {
        /// Final Cut's Blade, ⌘B: Premiere's ⌘K is Ask, on a video as on a
        /// picture (the user, 2026-10-24). B alone picks up the Blade tool.
        static let split = MenuShortcut.command("b")
        static let delete = MenuShortcut(key: DeleteKeyCharacters.backwards, modifiers: [])
        /// ⇧⌫, the key the timeline answers for it (`TimelineKeys`), on the
        /// pro menu bar: ⌥⌫ is Photoshop's Fill with Foreground, and one key
        /// printed on two rows is a key that lies on one of them.
        @MainActor static var rippleDelete: MenuShortcut {
            MenuShortcut(key: DeleteKeyCharacters.backwards,
                         modifiers: Experiments.shared.proMenuBarEnabled ? .shift : .option)
        }
        static let detachAudio = MenuShortcut(key: "d", modifiers: [.control, .shift])
        static let duplicate = MenuShortcut.command("j")
        static let clearInOut = MenuShortcut(key: "x", modifiers: .option)
        /// The mock's ⌥E for Expand the cut (`video-transition-wt.html`).
        /// Neither Photoshop nor Premiere gives ⌥E anything, so the mock's
        /// key stands (UX-PATTERNS §7).
        static let expandCut = MenuShortcut(key: "e", modifiers: .option)
        static let splitEverything = MenuShortcut.commandShift("k")
        /// Freeze Frame…. Premiere gives frame holds no key, so it takes a
        /// free one beside ⌥F (UX-PATTERNS §7: no grown-up tool claims it).
        static let freezeFrame = MenuShortcut(key: "f", modifiers: [.option, .shift])
        /// Premiere's marks. Plain letters, which the timeline answers while
        /// it has the keyboard (`EditorState+TimelineKeys`).
        static let addMarker = MenuShortcut(key: "m", modifiers: [])
        static let markIn = MenuShortcut(key: "i", modifiers: [])
        static let markOut = MenuShortcut(key: "o", modifiers: [])
        /// Premiere's Extract and Lift, on the same two keys.
        static let extract = MenuShortcut(key: "'", modifiers: [])
        static let lift = MenuShortcut(key: ";", modifiers: [])
        /// Premiere's Ripple Trim Previous and Next Edit to Playhead.
        static let rippleTrimStart = MenuShortcut(key: "q", modifiers: [])
        static let rippleTrimEnd = MenuShortcut(key: "w", modifiers: [])
        /// Final Cut's Add Cross Dissolve. Premiere's ⌘D is Photoshop's
        /// Deselect here, which the canvas keeps.
        static let applyDefaultTransition = MenuShortcut.command("t")
        /// Final Cut's Break Apart Clip Items, which is Photoshop's Ungroup
        /// too: the one key that takes a thing made of things apart.
        static let breakApart = MenuShortcut.commandShift("g")
        /// Premiere's Zoom to Sequence. ⇧Z, Final Cut's, is Punch In here,
        /// the key its mock prints, so one key never means two things.
        static let zoomToFit = MenuShortcut(key: "\\", modifiers: [])
        /// Premiere's Play In to Out, ⌃⇧Space on Windows, with ⌘ for ⌃
        /// (`TimelineKeys`).
        static let playInToOut = MenuShortcut.commandShift(" ")
    }

    // MARK: A clip

    /// The menu on one piece of a clip (the whole clip, when it is uncut).
    /// `onTheSound` is a click on the clip's linked sound, drawn on the Audio
    /// track under it, which answers like the audio clip it looks like
    /// (`ClipMenuPlan`).
    ///
    /// Which rows, in which groups, and what is one level down under More is
    /// `TimelineMenuTable`, one table per kind of thing (the user, 2026-10-17:
    /// "I right click on a clip, and i get this enormous right click menu
    /// which makes nearly no sense to me"). Here each row is only drawn, and
    /// left OUT where it cannot act on this clip at this moment.
    func timelineClipMenuRows(layerID: UUID, piece index: Int, onTheSound: Bool = false) -> [MenuRow] {
        // A caption's verbs are the words and the track they are on. A caption
        // is cut into no pieces, so it is answered before the clip's are read.
        if document?.layer(id: layerID)?.isCaption == true, !isClipLocked(layerID) {
            return captionCueMenuRows(layerID: layerID)
        }
        guard let document, let layer = document.layer(id: layerID),
              let time = layer.time, let pieces = layer.clipPieces else { return [] }
        var rows: [MenuRow] = []
        // A clip on a locked track is not edited, and the menu says why by
        // offering the one thing that would change that.
        if isClipLocked(layerID) {
            if let track = document.trackID(ofClip: layerID) {
                rows.append(.command("Unlock Track") { self.toggleTrackLocked(track) })
                rows.append(.separator)
            }
            rows.append(.command("Rename…") { self.beginRenamingClip(layerID) })
            if let url = mediaURL(ofLayer: layerID) {
                rows.append(.command("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
            }
            return rows
        }
        // One of the pieces a box picked: what the picked pieces do leads
        // (`EditorState+TrackRange`).
        if pieces.count > 1, isPiecePickedByBox(layerID: layerID, index: index) {
            rows += trackThingMenuRows() + [.separator]
        }
        // Picked under a range in hand and right clicked on the range: what
        // the range does to it leads (`EditorState+RangeSection`). On a part
        // of the clip outside the range the click is about the clip.
        if let section = rangeSection, section.ids.contains(layerID),
           SectionOperation.leadsTheMenu(rightClickAtMS: timelineLastRightPressMS, range: section.range) {
            rows += rangeSectionMenuRows() + [.separator]
        }
        // Clips merged into one answer as the clips they were made of.
        let thing: TimelineMenuThing = onTheSound ? .linkedSound
            : layer.movie != nil || (layer.isMergedClip && !layer.isSoundOnly) ? .videoClip
            : layer.sound != nil || layer.isMergedClip ? .soundClip
            : document.titleRecipe(layerID: layerID) != nil ? .title
            : .picture
        let clip = ClipMenuContext(layerID: layerID, index: index, piece: pieces.piece(at: index),
                                   underPlayhead: time.contains(ms: documentTimeMS),
                                   playheadPiece: pieces.pieceIndex(atMS: documentTimeMS - time.inMS),
                                   onePiece: pieces.count <= 1, onTheSound: onTheSound,
                                   targets: clipMenuTargets(layerID),
                                   plan: ClipMenuPlan(hasPicture: layer.movie != nil,
                                                      hasSound: layer.sound != nil, onTheSound: onTheSound))
        return rows + timelineMenu(thing) { self.clipMenuRows($0, clip: clip, layer: layer) }
    }

    /// What one clip menu is about, worked out once for all its rows.
    struct ClipMenuContext {
        let layerID: UUID
        let index: Int
        let piece: ClipPiece?
        /// The playhead runs through the clip.
        let underPlayhead: Bool
        /// The piece the playhead stands in, which Q and W reach.
        let playheadPiece: Int?
        let onePiece: Bool
        /// Opened on the clip's linked sound, under its picture.
        let onTheSound: Bool
        /// Right clicked inside a pick of several clips, the cut and the
        /// deletes act on the whole pick (`EditorState+TimelinePointing`).
        let targets: [UUID]
        let plan: ClipMenuPlan
    }

    /// A timeline menu laid out by `TimelineMenuTable`: each group's rows as
    /// `build` draws them, a group with none left out, a separator between
    /// the rest, and the long tail one level down under More (or Track).
    func timelineMenu(_ thing: TimelineMenuThing, build: (TimelineMenuRow) -> [MenuRow]) -> [MenuRow] {
        func laid(_ groups: [[TimelineMenuRow]]) -> [MenuRow] {
            groups.map { $0.flatMap(build) }
                .map { Self.trimmedSeparators($0) }
                .filter { !$0.isEmpty }
                .enumerated()
                .flatMap { $0.offset == 0 ? $0.element : [.separator] + $0.element }
        }
        let holder = TimelineMenuTable.moreRow(for: thing)
        var rows = laid(TimelineMenuTable.groups(for: thing).map { $0.filter { $0 != holder } })
        let more = laid(TimelineMenuTable.moreGroups(for: thing))
        if !more.isEmpty, let title = TimelineMenuTable.title(holder, playheadMS: 0) {
            if !rows.isEmpty { rows.append(.separator) }
            rows.append(.submenu(title, more))
        }
        return rows
    }

    /// Add Speed Stop, Delete Speed Stop and Reset Ramp, under the speeds in a
    /// clip's Speed submenu (`EditorState+SpeedStops`). On a picture only: a
    /// ramped stretch plays silent, so a sound has nothing to gain from one.
    func speedStopMenuRows(layerID: UUID, piece index: Int, picture: Bool) -> [MenuRow] {
        guard picture else { return [] }
        var rows: [MenuRow] = []
        if canAddSpeedStop(layerID) {
            rows.append(.command(TimelinePointing.atPlayhead(SpeedStopNames.add, ms: documentTimeMS)) {
                self.addSpeedStop(layerID)
            })
        }
        let ramped = document?.layer(id: layerID)?.clipPieces?.piece(at: index)?.speedRamp != nil
        if ramped {
            rows.append(.command(SpeedStopNames.delete) {
                self.selectClipPiece(layerID: layerID, index: index)
                self.run(.deleteSpeedStop)
            })
            rows.append(.command(SpeedStopNames.reset) {
                self.selectClipPiece(layerID: layerID, index: index)
                self.run(.resetRamp)
            })
        }
        return rows.isEmpty ? [] : [.separator] + rows
    }

    /// A list without a separator at either end or two in a row.
    static func trimmedSeparators(_ rows: [MenuRow]) -> [MenuRow] {
        var out: [MenuRow] = []
        for row in rows {
            if case .separator = row.kind {
                if let last = out.last, case .separator = last.kind { continue }
                if out.isEmpty { continue }
            }
            out.append(row)
        }
        if let last = out.last, case .separator = last.kind { out.removeLast() }
        return out
    }

    /// One row of a clip's menu, drawn, or none where it cannot act here.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func clipMenuRows(_ row: TimelineMenuRow, clip: ClipMenuContext, layer: Layer) -> [MenuRow] {
        let layerID = clip.layerID, index = clip.index, targets = clip.targets
        let at = documentTimeMS
        func titled(_ row: TimelineMenuRow) -> String { TimelineMenuTable.title(row, playheadMS: at) ?? "" }
        let picture = clip.plan.offersPictureRows
        let drawnOnTheTimeline = Experiments.shared.drawnOnTheTimelineEnabled && !layer.isSoundOnly
        switch row {
        // At the playhead
        case .split:
            if targets.count > 1 {
                guard targets.contains(where: { canSplitClip($0) }) else { return [] }
                return [.command(titled(.split), TimelineMenuKeys.split) { self.splitClipsAtPlayhead(targets) }]
            }
            guard canSplitClip(layerID) else { return [] }
            return [.command(titled(.split), TimelineMenuKeys.split) {
                self.selectLayer(layerID)
                self.run(.splitAtPlayhead)
            }]
        case .freezeFrame:
            guard picture, let piece = clip.piece else { return [] }
            // On a freeze, the popover changes THAT freeze, wherever the
            // playhead is.
            if piece.isHeld { return [freezeFrameMenuRow(layerID: layerID, piece: index, enabled: true)] }
            guard clip.underPlayhead else { return [] }
            return [.command(titled(.freezeFrame), TimelineMenuKeys.freezeFrame) {
                self.selectLayer(layerID)
                self.openFreezeFrame()
            }]
        case .speed:
            guard let piece = clip.piece, !piece.isHeld, layer.hasMediaBehindIt else { return [] }
            let speeds: [MenuRow] = EditorState.clipSpeeds.map { percent in
                .toggle(ClipSpeed.title(percent), isOn: piece.speedRamp == nil && piece.speedPercent == percent) {
                    self.selectClipPiece(layerID: layerID, index: index)
                    self.run(.setSpeed, ["percent": .number(Double(percent))])
                }
            }
            return [.submenu("Speed", speeds + speedStopMenuRows(layerID: layerID, piece: index, picture: picture))]
        case .startAtPlayhead, .endAtPlayhead:
            let start = row == .startAtPlayhead
            guard start ? canStartPlacedLayerHere(layerID) : canEndPlacedLayerHere(layerID) else { return [] }
            return [.command(titled(row)) {
                if start { self.startPlacedLayerHere(layerID) } else { self.endPlacedLayerHere(layerID) }
            }]

        // What it does
        case .addTransition:
            return clip.onTheSound ? [] : clipTransitionMenuRows(layerID: layerID, piece: index)
        case .detachAudio:
            if document?.canDetachSound(ofLayer: layerID) == true, clip.plan.offersDetachAudio {
                return [.command("Detach Audio", TimelineMenuKeys.detachAudio) {
                    self.selectLayer(layerID)
                    self.run(.detachAudio)
                }]
            }
            // Once the sound is a layer of its own, the same row on the
            // picture and on that sound reads Re-attach Audio, on the same key.
            if document?.canReattachSound(ofLayer: layerID) == true {
                return [.command("Re-attach Audio", TimelineMenuKeys.detachAudio) {
                    self.selectLayer(layerID)
                    self.run(.reattachAudio)
                }]
            }
            return []
        case .audio:
            // A video's sound, folded into one Audio menu: how loud it is at
            // the source (Premiere's Audio Gain) and captions from what is
            // said in it.
            guard picture, clip.plan.sound == .submenu else { return [] }
            var sound = soundGainRows(layerID: layerID)
            if let captions = addCaptionsMenuRow() { sound += (sound.isEmpty ? [] : [.separator]) + [captions] }
            return sound.isEmpty ? [] : [.submenu(ClipMenuPlan.soundSubmenuTitle, sound)]
        case .normalize:
            return Array(soundGainRows(layerID: layerID).prefix(1))
        case .cleanNoise:
            return Array(soundGainRows(layerID: layerID).dropFirst().prefix(1))
        case .resetGain:
            return Array(soundGainRows(layerID: layerID).dropFirst(2))
        case .addCaptions:
            guard layer.movie != nil || layer.sound != nil, let captions = addCaptionsMenuRow() else { return [] }
            return [captions]
        case .animateIn:
            return Array(titleAnimationMenuRows(layerID: layerID).prefix(1))
        case .animateOut:
            return Array(titleAnimationMenuRows(layerID: layerID).dropFirst())

        // The clipboard and the deletes
        case .cut, .copy:
            // The clipboard holds one clip, so these are offered on one.
            guard targets.count <= 1, document?.canDeleteLayers(ids: [layerID]) == true else { return [] }
            if row == .copy {
                return [.command(titled(.copy), KeyClipboardKeys.copy) { _ = self.copyClip(layerID) }]
            }
            return [.command(titled(.cut), MenuShortcut.command("x")) { self.cutClip(layerID) }]
        case .delete:
            // Under a range ⌫ and ⇧⌫ take the section, and its rows above say
            // so; the whole clip's rows stay, without a key that does
            // something else.
            let keys = !sectionTakesTheDelete
            return [.command("Delete", keys ? TimelineMenuKeys.delete : nil, destructive: true) {
                // A box's pick takes the zooms and keys beside its clips too.
                if self.boxExtrasHeld != nil, targets.contains(layerID), self.deleteBoxPick() { return }
                if targets.count > 1 { return self.deleteLayers(ids: targets) }
                self.deleteFromTimeline(layerID: layerID, piece: clip.onePiece ? nil : index)
            }]
        case .rippleDelete:
            let keys = !sectionTakesTheDelete
            return [.command("Ripple Delete", keys ? TimelineMenuKeys.rippleDelete : nil, destructive: true) {
                if self.boxExtrasHeld != nil, targets.contains(layerID), self.extractBoxPick() { return }
                if targets.count > 1 { return self.rippleDeleteClips(targets) }
                self.rippleDelete(layerID: layerID, piece: clip.onePiece ? nil : index)
            }]

        // One level down
        case .showPicture:
            // A stretch whose picture a range took off (Hide Picture for
            // Section) gets it back where the hand is.
            guard picture, clip.piece?.pictureHidden == true else { return [] }
            return [.command("Show Picture") { self.showPicture(layerID: layerID, piece: index) }]
        case .rippleTrimStart, .rippleTrimEnd:
            // Q and W reach the piece the playhead is standing in, so the rows
            // are offered only on that piece.
            let end: RippleTrimEnd = row == .rippleTrimStart ? .start : .end
            guard layer.movie != nil || layer.sound != nil, clip.underPlayhead, clip.playheadPiece == index,
                  canRippleTrimToPlayhead(end, clip: layerID) else { return [] }
            return [.command(end == .start ? "Ripple Trim Start to Playhead" : "Ripple Trim End to Playhead",
                             end == .start ? TimelineMenuKeys.rippleTrimStart : TimelineMenuKeys.rippleTrimEnd) {
                self.rippleTrimToPlayhead(end, clip: layerID)
            }]
        case .fadeIn, .fadeOut:
            // How the picture comes up at the start and goes down at the end.
            return clip.onTheSound ? [] : fadeRows(row == .fadeIn ? .in : .out, layer: layer)
        case .fadeInAndOut:
            // Both ends at once, on every pick it was opened among.
            guard !clip.onTheSound, Experiments.shared.pictureFadesEnabled else { return [] }
            return fadeInAndOutMenuRow(layerID: layerID)
        case .punchIn:
            return picture ? punchInMenuRows(layerID: layerID, around: nil) : []
        case .addZoom, .suggestZooms:
            // A spot of the recording filling the frame for a while, at the
            // playhead, and zooms round every run of clicks (`EditorState+Zoom`).
            guard picture else { return [] }
            let zooms = addZoomMenuRows(layerID: layerID, atMS: at).filter(\.isEnabled)
            return zooms.filter { ($0.title == "Add Zoom") == (row == .addZoom) }
        case .addClick:
            // A click the recording missed: the playhead says when, the next
            // click on the picture says where (`EditorState+Clicks`).
            guard picture, canAddClick(toClip: layerID) else { return [] }
            let title = TimelinePointing.atPlayhead("Add Click", ms: at) + "…"
            return [.command(title) {
                self.beginPlacingClick(onClip: layerID)
            }]
        case .animate:
            guard drawnOnTheTimeline, !clip.onTheSound, let animate = animateMenuRow(layerID: layerID) else { return [] }
            return [animate]
        case .addKey:
            // Where it is, its size, its angle and its opacity, keyed at the
            // playhead: the header diamond's verb, where the hand already is.
            guard drawnOnTheTimeline, !clip.onTheSound, clip.underPlayhead else { return [] }
            let onKey = document?.keyMomentDiamond(layerID: layerID, atDocumentTimeMS: at) == .onKey
            return [.command(TimelinePointing.atPlayhead(onKey ? "Remove Key" : "Add Key", ms: at)) {
                self.selectLayer(layerID)
                self.toggleHeaderKey(layerID)
            }]
        case .pasteKeys:
            guard !clip.onTheSound, keysOnClipboard != nil, canPasteKeys(onto: layerID) else { return [] }
            return [pasteKeysRow(layerID: layerID)]
        case .breakApart:
            // Clips merged into one open back into their parts.
            guard layer.isMergedClip, document?.canBreakApart(layerID) == true else { return [] }
            return [.command("Break Apart",
                             Experiments.shared.layerGroupsEnabled || Experiments.shared.proMenuBarEnabled
                                 ? TimelineMenuKeys.breakApart : nil) {
                self.breakApartClip(layerID)
            }]
        case .replayTitle:
            return titlePresetSaveMenuRows(layerID: layerID).filter { $0.title == "Replay Title" }
        case .saveAsPreset:
            return titlePresetSaveMenuRows(layerID: layerID).filter { $0.title != "Replay Title" }
        case .selectForward:
            // The Track Select Forward tool's pick (A), where the hand already is.
            return [.command("Select Forward") { self.selectClipsForward(from: layerID, onItsTrackOnly: false) }]
        case .duplicate:
            return [.command("Duplicate", TimelineMenuKeys.duplicate) { self.duplicateLayer(id: layerID) }]
        case .rename:
            return [.command("Rename…") { self.beginRenamingClip(layerID) }]
        case .revealInFinder:
            guard let url = mediaURL(ofLayer: layerID) else { return [] }
            return [.command("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }]
        default:
            return []
        }
    }

    /// Normalize ▸, Clean Noise and Reset Gain on a sound, where sound is on
    /// the timeline.
    private func soundGainRows(layerID: UUID) -> [MenuRow] {
        guard Experiments.shared.soundOnTheTimelineEnabled, document?.layer(id: layerID)?.sound != nil
        else { return [] }
        return soundGainMenuRows(layerID: layerID)
    }

    /// Fade In ▸ or Fade Out ▸: one fade for everything on the timeline. A
    /// title's single Fade ▸ where picture fades are off.
    private func fadeRows(_ end: FadeEnd, layer: Layer) -> [MenuRow] {
        if layer.isPlacedInTime, !Experiments.shared.pictureFadesEnabled {
            return end == .in ? placedLayerFadeRows(layerID: layer.id) : []
        }
        return pictureFadeMenuRows(layerID: layer.id).filter { $0.title == end.title }
    }

    /// **Normalize ▸**, with Clean Noise checked inside it (remembered, on
    /// until somebody unchecks it); **Clean Noise** or **Remove Noise
    /// Cleaning**; and, once a sound has gain, **Reset Gain**. Every picked
    /// sound when the clicked one is among the picks.
    func soundGainMenuRows(layerID: UUID) -> [MenuRow] {
        let ids = soundLayers(actingOn: layerID)
        guard !ids.isEmpty else { return [] }
        var normalize: [MenuRow] = [
            .command("Peaks to -1 dB") { Task { await self.normalizeSound(layers: ids) } },
            .separator,
        ]
        normalize += AudioNormalize.Target.allCases.map { target in
            .command(target.title) { Task { await self.normalizeSoundLoudness(layers: ids, to: target) } }
        }
        normalize += [
            .separator,
            .toggle("Clean Noise", isOn: normalizeCleansNoise) {
                self.normalizeCleansNoise.toggle()
            },
        ]
        var rows: [MenuRow] = [.submenu("Normalize", normalize)]
        let cleaned = ids.contains {
            document?.layer(id: $0)?.soundLevel?.noiseReduction != nil
                || document?.layer(id: $0)?.hasSectionNoiseCleaning == true
        }
        if cleaned {
            rows.append(.command("Remove Noise Cleaning") {
                self.removeNoiseCleaning(layers: ids)
            })
        } else {
            rows.append(.command("Clean Noise") {
                self.setSoundNoiseReduction(.standard, layers: ids)
            })
        }
        let gained = ids.contains { (document?.layer(id: $0)?.soundLevel?.clipGainDB ?? 0) != 0 }
        if gained {
            rows.append(.command("Reset Gain") {
                self.setSoundClipGain(Dictionary(uniqueKeysWithValues: ids.map { ($0, 0.0) }))
            })
        }
        return rows
    }

    /// **Freeze Frame…** on a clip that is not cut there yet asks how long
    /// for a new freeze at the playhead; on a freeze already there it is
    /// **Change Freeze…**, the same popover changing THAT freeze
    /// (`EditorState+FreezeAsk`).
    func freezeFrameMenuRow(layerID: UUID, piece index: Int, enabled: Bool) -> MenuRow {
        let piece = document?.layer(id: layerID)?.clipPieces?.piece(at: index)
        if piece?.isHeld == true {
            return .command("Change Freeze\u{2026}", enabled: enabled) {
                self.openFreezeFrame(layerID: layerID, heldPiece: index)
            }
        }
        return .command("Freeze Frame\u{2026}", TimelineMenuKeys.freezeFrame, enabled: enabled) {
            self.selectLayer(layerID)
            self.openFreezeFrame()
        }
    }

    /// Show Picture: a piece whose picture a range took off drawn again, as
    /// one step to undo.
    func showPicture(layerID: UUID, piece index: Int) {
        guard document?.layer(id: layerID)?.clipPieces?.piece(at: index)?.pictureHidden == true else { return }
        perform { _ = $0.setPictureHidden(layerID, ofPiece: index, false) }
        documentMomentChanged()
    }

    /// The hidden piece Clip ▸ Show Picture would bring back: the picked
    /// piece of the clip in hand, else the one under the playhead.
    var hiddenPictureInHand: (layerID: UUID, piece: Int)? {
        guard let id = clipInHandID, let layer = document?.layer(id: id), let time = layer.time,
              let pieces = layer.clipPieces,
              let index = selectedClipPieceIndex ?? pieces.pieceIndex(atMS: documentTimeMS - time.inMS),
              pieces.piece(at: index)?.pictureHidden == true else { return nil }
        return (id, index)
    }

    /// Whether the playhead runs through this clip somewhere a cut would
    /// mean anything, whichever clip is picked.
    func canSplitClip(_ id: UUID) -> Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime, !isClipLocked(id),
              let layer = document?.layer(id: id), let time = layer.time,
              var pieces = layer.clipPieces,
              documentTimeMS > time.inMS, documentTimeMS < time.outMS else { return false }
        return pieces.split(atMS: documentTimeMS - time.inMS)
    }

    /// Delete from the timeline: the piece, when the clip is cut, and the whole
    /// clip when it is not. A piece takes its stretch out of everything with it
    /// (`deleteClipPieceInHand`); a whole clip leaves a gap where it was, which
    /// is Premiere's Delete.
    func deleteFromTimeline(layerID: UUID, piece index: Int?) {
        if let index {
            selectClipPiece(layerID: layerID, index: index)
            deleteClipPieceInHand()
        } else {
            selectLayer(layerID)
            deleteSelectedLayers()
        }
    }

    /// Ripple Delete: the same, and everything after it pulls back to close the
    /// gap (`TimelineMenuEdits.swift`).
    func rippleDelete(layerID: UUID, piece index: Int?) {
        guard documentHasTime, !isClipLocked(layerID),
              let time = document?.layer(id: layerID)?.time else { return }
        endTrimBeforeCutting()
        pauseDocument()
        if let index {
            let landing = time.inMS + (document?.layer(id: layerID)?.clipPieces?.startMS(ofPiece: index) ?? 0)
            perform { $0.rippleDeleteClipPiece(layerID, at: index) }
            selectClipPiece(layerID: layerID, index: nil)
            documentTimeMS = min(max(0, landing), lastDocumentTimeMS)
        } else {
            perform { $0.rippleDeleteLayer(layerID) }
            selectLayer(nil)
            documentTimeMS = min(max(0, time.inMS), lastDocumentTimeMS)
        }
        documentMomentChanged()
    }

    /// Whether ⌥⌫ has something to ripple delete: a picked piece of a cut
    /// clip, else the picked clip itself.
    var canRippleDeleteInHand: Bool {
        if rulerRangeHeld != nil { return canTakeOutMarkedStretch }
        if boxExtrasHeld != nil { return true }
        if trackRangeHeld != nil || timelinePicksHeld != nil { return canTakeOutTrackThing }
        if timelineGapHeld != nil { return canCloseGapInHand }
        if sectionTakesTheDelete { return true }
        guard documentHasTime, let id = selectedLayerID, document?.layer(id: id)?.time != nil else { return false }
        return !isClipLocked(id)
    }

    /// Split at Playhead from a right click inside a pick of several clips:
    /// each one the playhead runs through is cut there, as one undo step, and
    /// the pick stays as it was.
    func splitClipsAtPlayhead(_ ids: [UUID]) {
        endTrimBeforeCutting()
        guard documentHasTime, ids.contains(where: { canSplitClip($0) }) else { return }
        pauseDocument()
        switchToEditForAnEdit()
        let atMS = documentTimeMS
        perform { $0.splitClips(ids, atMS: atMS) }
        documentMomentChanged()
    }

    /// Ripple Delete from a right click inside a pick of several clips: each
    /// goes and the gap closes on its own track, as one undo step.
    func rippleDeleteClips(_ ids: [UUID]) {
        guard documentHasTime else { return }
        endTrimBeforeCutting()
        pauseDocument()
        perform { $0.rippleDeletePicks(ids.map { TimelinePick(layerID: $0, piece: nil) }) }
        selectLayer(nil)
    }

    /// ⌥⌫: ripple delete what is picked.
    func rippleDeleteInHand() {
        // A range drawn on the ruler comes out and the gap closes.
        if rulerRangeHeld != nil {
            extractMarkedStretch()
            return
        }
        // A range on some tracks, or pieces a box picked: the gap closes on
        // their own tracks (`EditorState+TrackRange`).
        if extractTrackThing() { return }
        // A gap a click picked closes (`EditorState+TimelineGap`).
        if timelineGapHeld != nil {
            closeGapInHand()
            return
        }
        // A clip picked under a range: its part of the range comes out and
        // the gap closes on its track (`EditorState+RangeSection`).
        if rippleDeleteRangeSection() { return }
        guard canRippleDeleteInHand, let id = selectedLayerID else { return }
        let count = document?.layer(id: id)?.clipPieces?.count ?? 1
        rippleDelete(layerID: id, piece: count > 1 ? selectedClipPieceIndex : nil)
    }

    /// The file a clip plays, where it is still on disk to be shown.
    func mediaURL(ofLayer id: UUID) -> URL? {
        guard let layer = document?.layer(id: id) else { return nil }
        let url = layer.movie.flatMap { MovieLibrary.shared.url(for: $0) }
            ?? layer.sound.flatMap { SoundLibrary.shared.url(for: $0) }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The menu on one caption on the Captions track: its words, and what
    /// the Captions track does as a whole one level down.
    func captionCueMenuRows(layerID: UUID) -> [MenuRow] {
        timelineMenu(.caption) { row in
            switch row {
            case .editWords:
                return [.command("Edit Words") { self.beginRenamingClip(layerID) }]
            case .joinWithNextLine:
                guard self.canJoinCaptionWithNextLine(layerID) else { return [] }
                return [.command("Join with Next Line") { self.joinCaptionWithNextLine(layerID) }]
            case .startHere:
                return [.command("Start Here") {
                    self.selectLayer(layerID)
                    self.moveDocumentPlayhead(toMS: self.document?.layer(id: layerID)?.time?.inMS ?? 0)
                }]
            case .delete:
                return [.command("Delete", TimelineMenuKeys.delete, destructive: true) {
                    self.deleteFromTimeline(layerID: layerID, piece: nil)
                }]
            case .captionsTrack:
                return self.captionTrackMenuRows()
            default:
                return []
            }
        }
    }

    /// **Add Captions**, or Rewrite Captions once there are some, or Cancel
    /// Captions while it listens. Nil where captions are switched off.
    func addCaptionsMenuRow() -> MenuRow? {
        guard Experiments.shared.captionsFromTheSoundEnabled, documentHasTime else { return nil }
        if isWritingCaptions {
            return .command("Cancel Captions") { self.stopWritingCaptions() }
        }
        return .command(hasCaptions ? "Rewrite Captions" : "Add Captions",
                        enabled: canWriteCaptions) { self.writeCaptions() }
    }

    /// What every place that is about captions as a whole offers: write them
    /// again, move the lot, write them out, take them off.
    func captionTrackMenuRows() -> [MenuRow] {
        [
            addCaptionsMenuRow() ?? .separator,
            .submenu("Timing", [
                .command("Earlier", enabled: canNudgeCaptions) { self.nudgeCaptions(byMS: -Self.captionNudgeMS) },
                .command("Later", enabled: canNudgeCaptions) { self.nudgeCaptions(byMS: Self.captionNudgeMS) },
            ]),
            .submenu("Export Subtitles", CaptionFileFormat.allCases.map { format in
                .command(format.title + "…", enabled: canExportCaptions) { self.exportCaptions(as: format) }
            }),
            .toggle("Safe Areas", isOn: Self.showsSafeAreas) { self.toggleSafeAreas() },
            .command("Reset Captions", enabled: canResetCaptions) { self.resetCaptions() },
            .command("Clear Captions", enabled: canClearCaptions, destructive: true) { self.clearCaptions() },
        ]
    }

    /// Start typing a clip's name over its bar.
    func beginRenamingClip(_ id: UUID) {
        selectLayer(id)
        renamingClipID = id
    }

    // MARK: A cut

    /// The menu on one join of a clip.
    func timelineCutMenuRows(layerID: UUID, cut index: Int) -> [MenuRow] {
        guard let document, let layer = document.layer(id: layerID), layer.time != nil,
              let cut = layer.clipPieces?.cut(at: index), !isClipLocked(layerID) else { return [] }
        return cutMenuRows(at: .join(clip: layerID, index: index), cut: cut)
    }

    /// The menu on the edit point between two clips, or on the transition
    /// drawn over one. The cut between two clips looks just like a join on
    /// the timeline, so it answers just like one, as any edit point does in
    /// Premiere.
    func timelineEditPointMenuRows(_ point: TimelineEditPoint) -> [MenuRow] {
        let place = TimelineCutPlace.edit(outgoing: point.outgoing, incoming: point.incoming)
        guard let cut = document?.documentCut(at: place)?.cut, !isCutLocked(place) else { return [] }
        return cutMenuRows(at: place, cut: cut)
    }

    /// A cut's menu (`TimelineMenuTable`, a join): its transition, the
    /// transition clipboard, and the edits a cut takes. A row that cannot act
    /// on this cut is left out.
    private func cutMenuRows(at place: TimelineCutPlace, cut: ClipCut) -> [MenuRow] {
        let transitions = Experiments.shared.transitionsAtACutEnabled
            ? cutTransitionMenuRows(at: place, cut: cut) : [:]
        return timelineMenu(.join) { row in
            switch row {
            case .applyDefaultTransition, .addTransition, .transitionLength, .transitionCurve,
                 .removeTransition:
                return transitions[row].map { [$0] } ?? []
            case .copyTransition:
                guard transitions.isEmpty == false, cut.transition != nil else { return [] }
                return self.transitionClipboardMenuRows(at: place, hasTransition: true).prefix(1).map { $0 }
            case .pasteTransition:
                guard transitions.isEmpty == false, self.transitionOnClipboard != nil else { return [] }
                return Array(self.transitionClipboardMenuRows(at: place, hasTransition: true).dropFirst())
            case .rollEdit:
                guard self.canRollCut(at: place) else { return [] }
                return [.command(TimelineMenuTable.title(.rollEdit, playheadMS: self.documentTimeMS) ?? "") {
                    self.rollCutToPlayhead(at: place)
                }]
            case .expandCut:
                // A view of the cut, not an edit: its two clips on rows of
                // their own under the track (`EditorState+ExpandedCut`).
                guard Experiments.shared.transitionsAtACutEnabled else { return [] }
                return [.toggle(TimelineMenuTable.title(.expandCut, playheadMS: 0) ?? "",
                                isOn: self.expandedCutPlace == place,
                                shortcut: TimelineMenuKeys.expandCut) {
                    self.pickCut(place)
                    self.toggleExpandedCut(at: place)
                }]
            case .joinThroughEdit:
                // A cut with nothing removed, put back into one piece
                // (`ThroughEdit.swift`). No key, as Premiere gives it none
                // (UX-PATTERNS §7).
                guard self.canJoinThroughEdit(at: place) else { return [] }
                return [.command("Join Through Edit") { self.joinThroughEdit(at: place) }]
            default:
                return []
            }
        }
    }

    /// What a cut's right-click says about its transition. A bare cut offers
    /// one: the default on ⌘T, or any from the list. A cut that has one is
    /// about THAT one, the way Premiere's right-click on a transition is:
    /// change it to another kind, how long it takes, the curve it runs on, or
    /// take it off for a straight cut (the user, 2026-10-17: "right click to
    /// change the transition or press delete to delete the transition").
    private func cutTransitionMenuRows(at place: TimelineCutPlace, cut: ClipCut) -> [TimelineMenuRow: MenuRow] {
        guard let transition = cut.transition else {
            return [
                .applyDefaultTransition: .command("Apply Default Transition",
                                                  TimelineMenuKeys.applyDefaultTransition) {
                    self.applyDefaultTransition(at: place)
                },
                .addTransition: addTransitionMenuRow([.cut(place)]),
            ]
        }
        let kind = cut.drawnTransition?.kind ?? transition.kind
        let now = cut.drawnTransition?.lengthMS ?? transition.lengthMS
        let longest = cut.longestMS(for: transition)
        var lengths = Set(ClipTransition.lengthStopsMS.filter { $0 <= longest })
        lengths.insert(now)
        let curves = EasingCurve.named.prefix(EasingCurve.standardCount)
        return [
            .addTransition: addTransitionMenuRow([.cut(place)], current: transition.kind,
                                                 title: "Change Transition"),
            .transitionLength: .submenu("Length", lengths.sorted().map { ms in
                .toggle(ClipTransitionCopy.lengthChoice(ms, of: kind), isOn: ms == now) {
                    self.pickCut(place)
                    self.run(.setTransitionLength, ["milliseconds": .number(Double(ms))])
                }
            }),
            .transitionCurve: .submenu("Curve", curves.map { curve in
                .toggle(curve.title, isOn: curve == transition.curve) {
                    self.pickCut(place)
                    self.run(.setTransitionCurve, ["curve": .string(curve.title)])
                }
            }),
            .removeTransition: .command("Remove Transition") {
                self.pickCut(place)
                self.setTransition(nil, at: place)
            },
        ]
    }

    /// Whether the cut at `place` reads straight on across, so joining it
    /// gives back the one piece it was.
    func canJoinThroughEdit(at place: TimelineCutPlace) -> Bool {
        guard documentHasTime, !isCutLocked(place), let document else { return false }
        return document.canJoinThroughEdit(at: place)
    }

    /// Join the through edit at `place`, as one undo step. You are left
    /// holding the piece the cut was in; a transition that was on the cut goes
    /// with it, and the canvas says so, since nothing else would.
    func joinThroughEdit(at place: TimelineCutPlace) {
        endTrimBeforeCutting()
        guard canJoinThroughEdit(at: place), let document else { return }
        let removed = document.documentCut(at: place)?.cut.transition?.kind
        pauseDocument()
        switchToEditForAnEdit()
        perform { $0.joinThroughEdit(at: place) }
        switch place {
        case let .join(clip, index):
            selectClipPiece(layerID: clip, index: index - 1)
        case let .edit(outgoing, _):
            selectLayer(outgoing)
        }
        if let removed { raiseCanvasNotice(.throughEditJoined(removed: removed)) }
        documentMomentChanged()
    }

    /// Whether a cut can roll to the playhead: there is time, neither side is
    /// on a locked track, and both sides have the recording the roll needs.
    func canRollCut(at place: TimelineCutPlace) -> Bool {
        guard documentHasTime, !isCutLocked(place), let document else { return false }
        return document.canRollCut(at: place, toMS: documentTimeMS)
    }

    /// Whether either clip a cut belongs to is on a locked track.
    func isCutLocked(_ place: TimelineCutPlace) -> Bool {
        switch place {
        case let .join(clip, _): isClipLocked(clip)
        case let .edit(outgoing, incoming): isClipLocked(outgoing) || isClipLocked(incoming)
        }
    }

    /// Roll a cut to where the playhead is: the side before it grows by what
    /// the side after it gives up. A join keeps its clip the length it was;
    /// between two clips, the outgoing one ends and the incoming one starts on
    /// the playhead, and nothing after them moves. One step for undo.
    func rollCutToPlayhead(at place: TimelineCutPlace) {
        endTrimBeforeCutting()
        guard canRollCut(at: place) else { return }
        pauseDocument()
        perform { $0.rollCut(at: place, toMS: self.documentTimeMS) }
        pickCut(place)
        documentMomentChanged()
    }

    // MARK: The ruler and the scrub bar

    /// The menu on the ruler and the transport's scrub bar. Every row acts
    /// HERE, at the moment the pointer was over when the right click landed,
    /// and takes the playhead there first so what it did is in view.
    func timelineRulerMenuRows(atMS ms: Int, markerHere: UUID?) -> [MenuRow] {
        guard let document, documentHasTime else { return [] }
        var rows: [MenuRow] = []
        // What the marks are for: the stretch they enclose, out in one key.
        // A click ON the marked stretch is about that stretch, so the two
        // lead; the ruler sits at the foot of the screen, where a long menu
        // scrolls and its last rows are out of sight.
        let takesOut = canTakeOutMarkedStretch
        let onTheStretch = document.markedRangeMS.map { ($0.lowerBound...$0.upperBound).contains(ms) } == true
        let extractAndLift: [MenuRow] = [
            .command("Extract", TimelineMenuKeys.extract) { self.extractMarkedStretch() },
            .command("Lift", TimelineMenuKeys.lift) { self.liftMarkedStretch() },
        ]
        // A click on the stretch is about the stretch: what a range acts on
        // leads (`EditorState+RulerRange`), Delete and Ripple Delete being
        // Lift and Extract by the names a range is deleted by.
        // With things picked under the range, what it does to them leads,
        // and what it does to every track is one row further in
        // (`EditorState+RangeSection`).
        if onTheStretch, rulerRangeKept != nil, rangeSection != nil {
            rows += rangeSectionMenuRows() + [.submenu("All Tracks", rulerRangeMenuRows()), .separator]
        } else if onTheStretch {
            rows += rulerRangeMenuRows() + [.separator]
        }
        if let markerHere {
            rows.append(.command("Remove Marker") { self.removeMarker(markerHere) })
        } else {
            rows.append(.command("Add Marker", TimelineMenuKeys.addMarker) { self.addMarker(atMS: ms) })
        }
        rows.append(.separator)
        rows.append(.command("Set In", TimelineMenuKeys.markIn) { self.setMarkIn(atMS: ms) })
        rows.append(.command("Set Out", TimelineMenuKeys.markOut) { self.setMarkOut(atMS: ms) })
        if document.markInMS != nil || document.markOutMS != nil {
            // On the stretch its own rows above carry Clear Range.
            if !onTheStretch {
                rows.append(.command("Clear In and Out", TimelineMenuKeys.clearInOut) { self.clearMarkInOut() })
            }
            rows.append(.command("Play In to Out", TimelineMenuKeys.playInToOut, enabled: canPlayInToOut) {
                self.playInToOut()
            })
        }
        if takesOut, !onTheStretch { rows += [.separator] + extractAndLift }
        rows.append(.separator)
        var trial = document
        rows.append(.command("Split Everything Here", TimelineMenuKeys.splitEverything,
                             enabled: trial.splitEveryClip(atMS: ms) > 0) {
            self.splitEverything(atMS: ms)
        })
        if let paste = pasteRangeRow(atMS: ms) { rows.append(paste) }
        // A transition on the cut the click was at, where two clips meet.
        rows.append(contentsOf: rulerTransitionMenuRows(atMS: ms))
        // A zoom on the recording playing here, starting here.
        if canWorkWithZooms, let clip = clipToAddZoom(atMS: ms) {
            rows.append(.command("Add Zoom") {
                self.moveDocumentPlayhead(toMS: ms)
                self.addZoom(toClip: clip, atMS: ms)
            })
        }
        if !document.markers.isEmpty {
            rows.append(.separator)
            rows.append(.command("Clear All Markers") { self.removeAllMarkers() })
        }
        rows.append(.separator)
        rows += timelineViewMenuRows()
        return rows
    }

    /// How the timeline is being looked at, at the foot of its right-click
    /// menus: the whole recording back across the width, and the rows back
    /// to compact. The zoom itself is a pinch (user 2026-09-28).
    func timelineViewMenuRows() -> [MenuRow] {
        var rows: [MenuRow] = [
            .command("Zoom to Fit", TimelineMenuKeys.zoomToFit, enabled: isTimelineOpenedOut) {
                self.fitTimeline()
            },
        ]
        if !timelineRowZoom.isCompact {
            rows.append(.command("Compact Tracks") { self.resetTimelineRows() })
        }
        return rows
    }

    private func movePlayhead(toMS ms: Int) {
        pauseDocument()
        documentTimeMS = min(max(0, ms), lastDocumentTimeMS)
        documentMomentChanged()
    }

    func addMarker(atMS ms: Int) {
        guard documentHasTime else { return }
        movePlayhead(toMS: ms)
        perform { $0.addMarker(atMS: ms) }
    }

    func removeMarker(_ id: UUID) {
        perform { $0.removeMarker(id) }
    }

    func removeAllMarkers() {
        guard document?.markers.isEmpty == false else { return }
        perform { $0.removeAllMarkers() }
    }

    func setMarkIn(atMS ms: Int) {
        guard documentHasTime else { return }
        movePlayhead(toMS: ms)
        perform { $0.setMarkIn(atMS: ms) }
    }

    func setMarkOut(atMS ms: Int) {
        guard documentHasTime else { return }
        movePlayhead(toMS: ms)
        perform { $0.setMarkOut(atMS: ms) }
    }

    var canClearMarkInOut: Bool {
        documentHasTime && (document?.markInMS != nil || document?.markOutMS != nil)
    }

    /// ⌥X, Premiere's Clear In and Out.
    func clearMarkInOut() {
        guard canClearMarkInOut else { return }
        perform { $0.clearMarkInOut() }
        rulerRangeInHand = nil
    }

    /// Whether Extract and Lift have anything to take: an In or an Out is
    /// set and something unlocked runs into the stretch they enclose.
    var canTakeOutMarkedStretch: Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime, let document else { return false }
        return document.canTakeOutMarkedStretch
    }

    /// ', Premiere's Extract: what the In and the Out enclose comes out of
    /// every unlocked track and the gap closes, captions and titles and all
    /// (`MarkedStretch.swift`). One undo step. The playhead lands on the join.
    @discardableResult
    func extractMarkedStretch() -> Bool {
        takeOutMarkedStretch { $0.extractMarkedStretch() }
    }

    /// ;, Premiere's Lift: the same stretch out, and the gap left where it
    /// was, so nothing after it moves.
    @discardableResult
    func liftMarkedStretch() -> Bool {
        takeOutMarkedStretch { $0.liftMarkedStretch() }
    }

    private func takeOutMarkedStretch(_ edit: @escaping (inout PhotonzDocument) -> Bool) -> Bool {
        guard canTakeOutMarkedStretch, var trial = document,
              let range = trial.markedRangeMS, edit(&trial) else { return false }
        endTrimBeforeCutting()
        pauseDocument()
        perform { _ = edit(&$0) }
        selectedClipPieceIndex = nil
        documentTimeMS = min(max(0, range.lowerBound), lastDocumentTimeMS)
        documentMomentChanged()
        return true
    }

    // MARK: Q and W

    /// The clip Q and W would trim: the picked one where the playhead is on
    /// it, else the topmost clip under the playhead (`RippleTrim.swift`).
    var rippleTrimClipID: UUID? {
        document?.rippleTrimClip(pickedLayerID: selectedLayerID, atMS: documentTimeMS)
    }

    func canRippleTrimToPlayhead(_ end: RippleTrimEnd, clip: UUID? = nil) -> Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime,
              let id = clip ?? rippleTrimClipID else { return false }
        return document?.rippleTrimStretch(clip: id, atMS: documentTimeMS, end) != nil
    }

    /// Q and W, Premiere's Ripple Trim Previous and Next Edit to Playhead:
    /// the piece under the playhead loses everything from its start up to the
    /// playhead, or from the playhead to its end, and the gap closes on every
    /// unlocked track. One undo step. The playhead lands on the join, which is
    /// where the next Q or W, or a look at what now plays, starts from.
    @discardableResult
    func rippleTrimToPlayhead(_ end: RippleTrimEnd, clip: UUID? = nil) -> Bool {
        endTrimBeforeCutting()
        let at = documentTimeMS
        guard canRippleTrimToPlayhead(end, clip: clip), let id = clip ?? rippleTrimClipID,
              let stretch = document?.rippleTrimStretch(clip: id, atMS: at, end) else { return false }
        pauseDocument()
        perform { _ = $0.rippleTrim(clip: id, atMS: at, end) }
        selectedClipPieceIndex = nil
        documentTimeMS = min(max(0, stretch.lowerBound), lastDocumentTimeMS)
        documentMomentChanged()
        return true
    }

    var canSplitEverythingAtPlayhead: Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime, let document else { return false }
        return document.canSplitEveryClip(atMS: documentTimeMS)
    }

    /// ⇧⌘K, Premiere's Add Edit to All Tracks: every clip the moment runs
    /// through is cut there.
    func splitEverything(atMS ms: Int) {
        endTrimBeforeCutting()
        movePlayhead(toMS: ms)
        guard var trial = document, trial.splitEveryClip(atMS: documentTimeMS) > 0 else { return }
        perform { $0.splitEveryClip(atMS: self.documentTimeMS) }
        selectedClipPieceIndex = nil
        documentMomentChanged()
    }
}

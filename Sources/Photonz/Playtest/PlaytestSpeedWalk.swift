// The speed walk's hands and eyes (task
// `a-speed-walk-measures-the-long-reference-edit-th`): plays, scrubs, edits,
// scrolls and exports the reference edit the way a person does, takes a look
// at every display refresh, and hands the looks to `SpeedWalk` (PhotonzCore)
// to count. Every measure adds to one `SpeedRun`, written as `speed.json`
// beside the walk's pictures after each step, so a walk that stops part way
// still leaves what it measured.
//
// Probe builds only, like the rest of the harness.
#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore
import PhotonzRender
import QuartzCore

@MainActor
final class SpeedWalkProbe {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private let out: URL
    private let scriptURL: URL
    private(set) var run: SpeedRun

    init(out: URL, scriptURL: URL) {
        self.out = out
        self.scriptURL = scriptURL
        let day = ISO8601DateFormatter()
        run = SpeedRun(minutes: nil, form: "short", head: Self.head, date: day.string(from: Date()),
                       machine: Self.machine, frameStepMS: MovieRef.frameStepMS)
    }

    /// Does one measure and says in a line what it found.
    func measure(_ step: PlaytestSpeedMeasure, editor: EditorState) async throws -> String {
        if let form = step.form { run.form = form }
        if run.minutes == nil, editor.documentLengthMS > 0 {
            run.minutes = Int((Double(editor.documentLengthMS) / 60_000).rounded())
        }
        defer { write() }
        switch step.measure {
        case .play: return try await play(editor, fromMS: step.fromMS ?? 0, seconds: step.seconds ?? 60)
        case .scrub: return try await scrub(editor, speeds: step.speeds)
        case .edits: return try await edits(editor, step.edits, fromMS: step.fromMS)
        case .idleBuilds: return try await idleBuilds(editor, seconds: step.seconds ?? 3, fromMS: step.fromMS)
        case .timeline: return try await timeline(editor)
        case .memory: return try await memory(editor, step)
        case .export: return try await export(editor, step)
        case .compare: return try compare(step)
        case nil: throw Failure(description: "\(step.rawMeasure) is not a measure")
        }
    }

    // MARK: - Playing

    private func frames(_ editor: EditorState) throws -> DisplayFrames {
        guard let view = editor.hostWindow?.contentView else {
            throw Failure(description: "the editor has no window to take display refreshes from")
        }
        return DisplayFrames(view: view)
    }

    private func play(_ editor: EditorState, fromMS: Int, seconds: Double) async throws -> String {
        guard let document = editor.document, document.hasTime else {
            throw Failure(description: "there is no video in this window to play")
        }
        let frames = try frames(editor)
        defer { frames.invalidate() }
        editor.pauseDocument()
        editor.scrubDocument(toMS: fromMS)
        await settle(editor, frames: frames)
        let picturesBefore = editor.canvasFrameCount
        editor.playDocument(rate: 1)
        let start = CACurrentMediaTime()
        // The moment Space went down is a look too, and so is the moment the
        // stretch ends: on an hour-long edit one tick of the clock held the
        // main thread for over a minute, and a run of one look read as no
        // time at all (2026-11-13).
        var samples: [SpeedWalk.PlaySample] = [
            SpeedWalk.PlaySample(wallMS: 0, playheadMS: editor.documentTimeMS, shownMS: editor.shownMomentMS),
        ]
        var looks = 0, silent = 0
        var nextSoundLook = 1.0
        let audible = editor.audioMix.filter(\.isAudible)
        var firstQuietMS: Int?
        // A half second of what actually comes out, at every whole minute
        // the playhead passes: heard in the room, not just scheduled.
        var heardAtMinute: [Int: Double] = [:]
        var listening: Task<Void, Never>?
        var nextListenMinute = fromMS / 60_000 + (fromMS % 60_000 == 0 ? 0 : 1)
        var worstClockApartMS = 0
        var clockAheadMS: [Int] = []
        var soundBehindMS: [Double] = []
        var outputLatencyMS = 0.0
        while CACurrentMediaTime() - start < seconds, editor.isDocumentPlaying {
            await frames.next()
            let now = CACurrentMediaTime() - start
            samples.append(SpeedWalk.PlaySample(wallMS: now * 1000, playheadMS: editor.documentTimeMS,
                                                shownMS: editor.shownMomentMS))
            if now >= nextSoundLook {
                // Silent when the engine has stopped, or when a piece the
                // plan has sounding at the playhead is not on it: the sound
                // of a long edit going quiet part way while the picture goes
                // on (task `find-out-whether-a-long-edit-goes-quiet-after-it`).
                looks += 1
                let at = editor.documentTimeMS
                let held = Set(editor.audioPlayer.scheduledSegments)
                let missing = audible.filter { $0.contains(ms: at) && !held.contains($0) }
                if !editor.audioPlayer.isPlaying || !missing.isEmpty { silent += 1 }
                if !missing.isEmpty, firstQuietMS == nil { firstQuietMS = at }
                if at >= nextListenMinute * 60_000, listening == nil {
                    let minute = nextListenMinute
                    nextListenMinute = at / 60_000 + 1
                    let player = editor.audioPlayer
                    listening = Task { @MainActor in
                        heardAtMinute[minute] = await player.listenForLevel(seconds: 0.5) ?? 0
                        listening = nil
                    }
                }
                if let clockMS = editor.audioPlayer.engineClockMS {
                    worstClockApartMS = max(worstClockApartMS, abs(clockMS - at))
                    clockAheadMS.append(clockMS - at)
                }
                // The sound against the picture a person sees: the picture
                // handed to the canvas by now goes up at the next refresh,
                // and what the speaker is putting out at that same instant,
                // its own latency counted, is set beside it.
                if let shown = editor.shownMomentMS,
                   let onGlass = frames.refresh(atOrAfter: CACurrentMediaTime()),
                   let heard = editor.audioPlayer.heard(atHostSeconds: onGlass) {
                    soundBehindMS.append(SpeedWalk.SyncTally.soundBehindMS(shownMS: shown, heardMS: heard.ms,
                                                                            frameStepMS: MovieRef.frameStepMS))
                    outputLatencyMS = heard.outputLatencyMS
                }
                nextSoundLook += 1
            }
        }
        samples.append(SpeedWalk.PlaySample(wallMS: (CACurrentMediaTime() - start) * 1000,
                                            playheadMS: editor.documentTimeMS, shownMS: editor.shownMomentMS))
        await listening?.value
        let leftOut = editor.audioPlayer.droppedSegments
        let heard = heardAtMinute.keys.sorted()
            .map { String(format: "%d:%.3f", $0, heardAtMinute[$0] ?? 0) }.joined(separator: " ")
        let lateSkewMS = editor.audioPlayer.worstLateSkewMS
        let reachedMS = editor.documentTimeMS
        editor.pauseDocument()
        // The renderer's own account of the pictures it drew meanwhile. It
        // keeps the last few hundred, which a minute of play at the clock's
        // pace can outrun, so it speaks for the end of the stretch.
        let pictures = editor.canvasFrameCount - picturesBefore
        let times = editor.recentCompositeTimes.suffix(max(0, pictures))
        run.composites = SpeedWalk.CompositeTally(pictures: pictures, drawMS: times.map(\.drawMS),
                                                  askedToShownMS: times.map(\.sinceAskedMS))

        let step = MovieRef.frameStepMS
        let whole = SpeedWalk.tally(samples, frameStepMS: step)
        let spans = SpeedWalk.transitionSpans(of: document)
            .filter { $0.range.lowerBound >= fromMS && $0.range.upperBound <= reachedMS }
        let cuts = spans.map { SpeedWalk.tally(samples, over: $0, frameStepMS: step) }
        run.plays.removeAll()
        run.plays = [whole] + cuts
        let sync = soundBehindMS.isEmpty ? nil
            : SpeedWalk.SyncTally(soundBehindMS: soundBehindMS, outputLatencyMS: outputLatencyMS)
        run.sound = SpeedWalk.SoundTally(piecesLeftOut: leftOut, silentLooks: silent, looks: looks, sync: sync)
        let worstCut = cuts.max { $0.worstGapMS < $1.worstGapMS }
        let droppedAt = SpeedWalk.droppedMoments(samples, frameStepMS: step)
        return String(format: "played %.1fs from %@ to %@: %d of %d frames shown, %d dropped, worst gap %.0fms",
                      whole.seconds, SpeedWalk.clock(fromMS), SpeedWalk.clock(reachedMS),
                      whole.framesShown, whole.framesDue, whole.dropped, whole.worstGapMS)
            + (droppedAt.isEmpty ? "" : " (due at " + droppedAt.prefix(8).map(SpeedWalk.clock).joined(separator: ", ")
                + (droppedAt.count > 8 ? ", ..." : "") + ")")
            + (whole.firstPictureMS.map { String(format: ", first new picture %.0fms after Space", $0) } ?? "")
            + "; \(cuts.count) transitions crossed, \(cuts.filter { $0.dropped > 0 }.count) of them dropped frames"
            + (worstCut.map { String(format: ", the worst %@ (%d of %d dropped, gap %.0fms)", $0.label,
                                     $0.dropped, $0.framesDue, $0.worstGapMS) } ?? "")
            + "; sound: \(leftOut) piece(s) left out, silent at \(silent) of \(looks) one-second looks"
            + (firstQuietMS.map { " (first at \(SpeedWalk.clock($0)))" } ?? "")
            + (heard.isEmpty ? "" : ", level heard at each minute \(heard)")
            + String(format: ", pieces put on while playing landed within %.0fms of the press's clock, "
                     + "which was within %dms of the playhead (%dms ahead of it at the median)",
                     lateSkewMS, worstClockApartMS, clockAheadMS.sorted().dropFirst(clockAheadMS.count / 2).first ?? 0)
            + (sync.map {
                String(format: "; against the picture on screen the sound came out %.0fms behind it at the median "
                       + "(%.0fms to %.0fms over %d looks, the output's own %.0fms counted): %@",
                       $0.medianBehindMS, $0.earliestBehindMS, $0.latestBehindMS, $0.looks, $0.outputLatencyMS,
                       $0.withinTightLimit ? "in step" : $0.inStep ? "in step, but more than 45ms off" : "OUT OF STEP")
            } ?? "")
            + String(format: "; the renderer handed the canvas %d pictures, drawn in %.0fms (median) to %.0fms, "
                     + "%.0fms (median) to %.0fms from asked to arrived", pictures,
                     run.composites?.drawMedianMS ?? 0, run.composites?.drawWorstMS ?? 0,
                     run.composites?.askedToShownMedianMS ?? 0, run.composites?.askedToShownWorstMS ?? 0)
    }

    /// Waits for the picture at the playhead to come in (at most three
    /// seconds) so a measure starts from a settled window.
    private func settle(_ editor: EditorState, frames: DisplayFrames) async {
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < 3 {
            await frames.next()
            if editor.shownMomentMS == editor.documentTimeMS, CACurrentMediaTime() - start > 0.5 { break }
        }
    }

    // MARK: - Scrubbing

    private func scrub(_ editor: EditorState, speeds: [String]) async throws -> String {
        let frames = try frames(editor)
        defer { frames.invalidate() }
        let length = editor.documentLengthMS
        guard length > 0 else { throw Failure(description: "there is nothing to scrub") }
        var lines: [String] = []
        for speed in speeds {
            let span = PlaytestSpeedMeasure.scrubSpan(speed, lengthMS: length)
            let low = span.lowerBound, high = min(span.upperBound, length)
            let count = PlaytestSpeedMeasure.scrubFrames(speed)
            editor.pauseDocument()
            editor.scrubDocument(toMS: low)
            await settle(editor, frames: frames)
            editor.beginPlayheadDrag()
            var hand: [Int] = [], handAt: [Double] = [], shown: [Int?] = [], at: [Double] = []
            var exact: [Int?] = []
            var needed: [[UUID]] = [], neededAt: [Double] = [], drawn: [Set<UUID>?] = []
            editor.playtestRecordsDrawnFrames = true
            editor.playtestShownFrameIDs = nil
            defer { editor.playtestRecordsDrawnFrames = false }
            // The hand moves by the clock, as a person's does: it takes
            // `count` refreshes of the display to cross, and where it is at
            // each look is where the time says, however long the app took to
            // take the last move. A drag the app cannot keep up with is given
            // up at six times its length (fifteen seconds at least), and how
            // many of the display's refreshes the app answered is recorded.
            let refreshMS = frames.refreshInterval * 1000
            let duration = Double(count) * refreshMS / 1000
            let allowed = max(15, duration * 6)
            let start = CACurrentMediaTime()
            var looks = 0
            while true {
                let elapsed = CACurrentMediaTime() - start
                if elapsed > allowed { break }
                let along = min(1, elapsed / duration)
                editor.dragPlayhead(toMS: low + Int(Double(high - low) * along))
                hand.append(editor.documentTimeMS)
                handAt.append((CACurrentMediaTime() - start) * 1000)
                await frames.next()
                looks += 1
                at.append((CACurrentMediaTime() - start) * 1000)
                shown.append(editor.shownMomentMS)
                exact.append(editor.playtestShownExactMomentMS)
                drawn.append(editor.playtestShownFrameIDs)
                // Past the end, it waits for the picture to arrive where the
                // hand stopped.
                if along >= 1, editor.shownMomentMS == editor.documentTimeMS,
                   editor.playtestShownExactMomentMS == editor.documentTimeMS { break }
            }
            editor.endPlayheadDrag()
            let refresh = frames.refreshInterval * 1000
            let lags = SpeedWalk.scrubLags(hand: hand, handAtMS: handAt, shown: shown, atMS: at,
                                                refreshMS: refresh)
            let stats = SpeedWalk.lagStats(lags)
            let frameStats = SpeedWalk.lagStats(SpeedWalk.scrubLags(hand: hand, handAtMS: handAt, shown: exact,
                                                                    atMS: at, refreshMS: refresh))
            let times = SpeedWalk.frameTimes(speed, refreshesAtMS: at, refreshMS: refresh)
            run.scrubs.removeAll { $0.speed == speed }
            let made = looks
            let took = (at.last ?? 0) / 1000
            var tally = SpeedWalk.ScrubTally(speed: speed, frames: count, lagMedianFrames: stats.median,
                                             lagWorstFrames: stats.worst, worstFrameMS: times.worstMS,
                                             movesMade: made, seconds: took)
            tally.frameLagMedianFrames = frameStats.median
            tally.frameLagWorstFrames = frameStats.worst
            // Every frame the hand crossed, not only where it was at each
            // look: going fast it crosses a second of film between two
            // refreshes, and a key frame shown from inside that second was
            // under it less than a refresh ago (`MovieKeyFrames`).
            if let document = editor.document {
                for (moment, time) in SpeedWalk.handPath(hand: hand, handAtMS: handAt, stepMS: MovieRef.frameStepMS) {
                    needed.append(document.movieFrames(atTimeMS: moment).map(\.ref.id))
                    neededAt.append(time)
                }
            }
            let sightStats = SpeedWalk.lagStats(SpeedWalk.sightLags(needed: needed, handAtMS: neededAt, drawn: drawn,
                                                                    atMS: at, refreshMS: refresh))
            tally.sightLagMedianFrames = sightStats.median
            tally.sightLagWorstFrames = sightStats.worst
            run.scrubs.append(tally)
            lines.append(String(format: "%@ (%d looks against %d refreshes, %.1fs against %.1fs at the display's pace): the picture "
                                + "trailed the hand by %d display frames in the middle, %d at worst, and the frame under "
                                + "the hand by %d in the middle, %d at worst, and what it shows of the recording by %d "
                                + "in the middle, %d at worst; longest refresh %.0fms",
                                speed, made, count, took, Double(count) * refresh / 1000, stats.median, stats.worst,
                                frameStats.median, frameStats.worst, sightStats.median, sightStats.worst, times.worstMS))
        }
        return "scrubbed end to end: " + lines.joined(separator: "; ")
    }

    // MARK: - Editing while it plays

    private func edits(_ editor: EditorState, _ edits: [String], fromMS: Int?) async throws -> String {
        guard editor.document?.hasTime == true else { throw Failure(description: "there is no video to edit") }
        let frames = try frames(editor)
        defer { frames.invalidate() }
        editor.pauseDocument()
        editor.scrubDocument(toMS: fromMS ?? 20_000)
        await settle(editor, frames: frames)
        editor.playDocument(rate: 1)
        try? await Task.sleep(for: .seconds(1))
        var lines: [String] = []
        for named in edits {
            // A blade stops play. Starting it again is not part of the next
            // edit: a person presses Space, watches, then edits, so play has
            // a second to get going before the edit is counted. Until
            // 2026-11-15 the edit after a blade was made in the same turn as
            // the restart, and an undo of a blade was charged for both.
            if !editor.isDocumentPlaying {
                editor.playDocument(rate: 1)
                try? await Task.sleep(for: .seconds(1))
            }
            // B cuts the clip in hand, so a person clicks the clip and then
            // presses B. The click is a pick, timed as one when the walk
            // names it, and never charged to the blade: until 2026-11-21 a
            // blade with nothing picked was timed with the pick that filled
            // the panel, and read 45 ms where the cut itself was 27 to 33.
            if named == "blade", try handTheBladeItsClip(editor) {
                try? await Task.sleep(for: .seconds(1.5))
            }
            // Every edit is counted under the state the window is really in
            // when it is made (`PlaytestSpeedMeasure.tallyName`): with a clip
            // picked the panel's sections answer the edit too and it costs
            // more. Until 2026-11-21 the walk kept its own idea of the pick,
            // and an undo after a blade, made with the blade's piece picked,
            // was counted as an undo with nothing picked: 25 ms where one
            // with nothing picked is 12.
            let picked = editor.selectedLayerID != nil
            let edit = PlaytestSpeedMeasure.tallyName(named, picked: picked, fromNothing: named == "pick" && !picked)
            MainThreadMeter.shared.reset()
            ViewBuildMeter.shared.reset()
            let began = CACurrentMediaTime()
            let did: String
            do {
                did = try perform(named, on: editor)
            } catch let refused as Failure {
                // One edit that finds nothing to act on does not cost the
                // others their numbers: it is written down as not made.
                SpeedWalk.EditTally.keepWorse(SpeedWalk.EditTally(edit: edit, did: "not made: \(refused.description)",
                                                                  callMS: 0, longestPassMS: 0, made: false),
                                              in: &run.edits)
                lines.append("\(edit) not made: \(refused.description)")
                continue
            }
            let call = (CACurrentMediaTime() - began) * 1000
            try? await Task.sleep(for: .seconds(1.5))
            let longest = max(MainThreadMeter.shared.longestMS, call)
            let stillPlaying = editor.isDocumentPlaying
            SpeedWalk.EditTally.keepWorse(SpeedWalk.EditTally(edit: edit, did: did, callMS: call, longestPassMS: longest),
                                          in: &run.edits)
            // Which counted views the edit built again, so a slow edit names
            // where its time went rather than leaving it to a profile.
            let built = ViewBuildMeter.shared.countsReport
            // And every long pass after it, in order, so the edit's own pass
            // and the ones that follow it can be told apart.
            lines.append(String(format: "%@ (%@): %.0fms in the call, longest pass %.0fms%@ (%@); passes: %@", edit, did,
                                call, longest, stillPlaying ? "" : ", and it stopped playing", built,
                                MainThreadMeter.shared.longPassesReport))
        }
        editor.pauseDocument()
        return "edited while it played: " + lines.joined(separator: "; ")
    }

    /// One edit a person makes while the video plays, on something just
    /// ahead of the playhead so what they are watching is what changes next.
    /// The recordings on each picture track, earliest first, and the main
    /// ones: those on the picture track that holds the most.
    private func recordings(in document: PhotonzDocument) -> (byTrack: [[Layer]], main: [Layer]) {
        let pictureTracks = document.timelineTracks.filter { $0.kind == .video }
        let byTrack = pictureTracks.map { track in
            document.clipIDs(onTrack: track.id).compactMap { document.layer(id: $0) }
                .filter { $0.movie != nil }
                .sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
        }
        return (byTrack, byTrack.max { $0.count < $1.count } ?? [])
    }

    /// Picks the clip a blade will cut, the click a person makes before
    /// pressing B, when it is not already the one picked: the picked clip if
    /// the playhead runs through it with time to spare, else the first
    /// recording under the playhead, else the next main recording, parked in.
    /// True when it picked or parked anything, so the walk lets the window
    /// settle before the blade is timed.
    private func handTheBladeItsClip(_ editor: EditorState) throws -> Bool {
        guard let document = editor.document else { throw Failure(description: "no document") }
        let playhead = editor.documentTimeMS
        let (byTrack, main) = recordings(in: document)
        // Three seconds to spare, so the playhead is still inside it after
        // the window settles.
        func runsUnder(_ layer: Layer) -> Bool {
            (layer.time?.inMS ?? 0) + 100 < playhead && playhead < (layer.time?.outMS ?? 0) - 3000
        }
        let held = editor.selectedLayerID.flatMap { document.layer(id: $0) }.flatMap { runsUnder($0) ? $0 : nil }
        if held != nil { return false }
        var under = (main + byTrack.flatMap { $0 }).first(where: runsUnder)
        // Over a title page or a gap there is nothing to cut: a person
        // parks on the next recording and plays on from there.
        if under == nil, let next = main.first(where: { ($0.time?.inMS ?? 0) > playhead }), let time = next.time {
            editor.moveDocumentPlayhead(toMS: time.inMS + time.lengthMS / 2)
            editor.playDocument(rate: 1)
            under = next
        }
        guard let clip = under else {
            throw Failure(description: "no recording under or after the playhead at \(SpeedWalk.clock(playhead)) to cut")
        }
        if editor.selectedLayerID != clip.id { editor.selectLayer(clip.id) }
        return true
    }

    private func perform(_ edit: String, on editor: EditorState) throws -> String {
        guard let document = editor.document else { throw Failure(description: "no document") }
        let playhead = editor.documentTimeMS
        let (byTrack, main) = recordings(in: document)
        switch edit {
        case "nothing":
            return "nothing done"
        case "trim":
            guard let clip = main.first(where: { ($0.time?.inMS ?? 0) > playhead + 2000 }),
                  let session = ClipTrimSession(layer: clip) else {
                throw Failure(description: "no clip ahead of the playhead to trim")
            }
            var refusal: String?
            editor.perform { refusal = $0.agentTrim(clip.id, keepFromMS: nil, keepToMS: session.keepOutMS - 500,
                                                     ripple: false) }
            if let refusal { throw Failure(description: "the trim was refused: \(refusal)") }
            return "half a second off the end of \(clip.name)"
        case "move":
            let broll = byTrack.filter { $0 != main }.flatMap { $0 }
                .filter { ($0.time?.inMS ?? 0) > playhead + 2000 }
            for clip in broll + main {
                guard let time = clip.time, let track = document.trackID(ofClip: clip.id) else { continue }
                for delta in [500, -500] {
                    let to = time.inMS + delta
                    guard to > playhead,
                          document.agentClipInTheWay(of: clip.id, span: to..<(to + time.lengthMS), onTrack: track) == nil
                    else { continue }
                    var moved = false
                    editor.perform { moved = $0.moveClip(clip.id, toInMS: to) }
                    if moved { return "\(clip.name) \(delta > 0 ? "later" : "earlier") by half a second" }
                }
            }
            throw Failure(description: "no clip ahead of the playhead had room to move")
        case "pick":
            // The recording under the playhead with time left in it to be
            // cut and trimmed while it plays on, else the next one, parked in.
            var under = main.first {
                ($0.time?.inMS ?? 0) + 100 < playhead && playhead < ($0.time?.outMS ?? 0) - 6000
            }
            // With a clip picked, a pick is a click on ANOTHER clip: the
            // panel moves from one clip to the next. Picking the one already
            // picked changes nothing and read 5 ms, so a walk that happened
            // to land on it timed nothing (2026-11-21).
            if let held = editor.selectedLayerID, under?.id == held || under == nil,
               let other = main.first(where: { $0.id != held && ($0.time?.inMS ?? 0) > playhead }) {
                editor.selectLayer(other.id)
                return "\(other.name) picked, from \(document.layer(id: held)?.name ?? "another clip")"
            }
            if under == nil, let next = main.first(where: { ($0.time?.inMS ?? 0) > playhead }), let time = next.time {
                editor.moveDocumentPlayhead(toMS: time.inMS + 300)
                editor.playDocument(rate: 1)
                under = next
            }
            guard let clip = under else {
                throw Failure(description: "no recording under or after the playhead at \(SpeedWalk.clock(playhead)) to pick")
            }
            editor.selectLayer(clip.id)
            return "\(clip.name) picked"
        case "blade":
            // B cuts the clip in hand, picked untimed before this
            // (`handTheBladeItsClip`), the way a person clicks it first.
            guard let clip = editor.selectedLayerID.flatMap({ document.layer(id: $0) }) else {
                throw Failure(description: "no clip in hand to cut at \(SpeedWalk.clock(playhead))")
            }
            guard editor.canSplitClipAtPlayhead else { throw Failure(description: "\(clip.name) cannot be cut there") }
            editor.splitClipAtPlayhead()
            return "\(clip.name) cut at \(SpeedWalk.clock(editor.documentTimeMS))"
        case "unpick":
            editor.selectLayer(nil)
            return "nothing picked"
        case "undo":
            guard editor.canUndo else { throw Failure(description: "there was nothing to undo") }
            editor.undo()
            return "the last edit taken back"
        case "transition":
            let ahead = document.transitionCuts().filter { $0.atMS > playhead + 2000 }
            guard let cut = ahead.first(where: { $0.cut.transition == nil && $0.cut.fitted(.dissolve) != nil })
                    ?? ahead.first(where: { $0.cut.fitted(.wipe) != nil }) else {
                throw Failure(description: "no cut ahead of the playhead takes a transition")
            }
            let kind: ClipTransitionKind = cut.cut.transition == nil ? .dissolve : .wipe
            editor.setTransition(kind, at: cut.place)
            return "\(kind.title.lowercased()) at \(SpeedWalk.clock(cut.atMS))"
        case "title":
            let titles = document.timelineClipLayers
                .filter { $0.group?.titleRecipe != nil && ($0.time?.inMS ?? 0) > playhead }
                .sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
            guard let title = titles.first, let words = title.selfAndDescendants.first(where: { $0.text != nil }) else {
                throw Failure(description: "no title ahead of the playhead to reword")
            }
            AgentVideoWork.reword(words.id, to: "Speed walk \(Int.random(in: 10...99))", in: editor)
            return "the words of \(title.name)"
        default:
            throw Failure(description: "\(edit) is not an edit")
        }
    }

    // MARK: - What a frame builds

    private func idleBuilds(_ editor: EditorState, seconds: Double, fromMS: Int?) async throws -> String {
        let frames = try frames(editor)
        defer { frames.invalidate() }
        editor.pauseDocument()
        editor.scrubDocument(toMS: fromMS ?? 30_000)
        await settle(editor, frames: frames)
        editor.playDocument(rate: 1)
        try? await Task.sleep(for: .seconds(0.5))
        ViewBuildMeter.shared.reset()
        let before = editor.canvasFrameCount
        try? await Task.sleep(for: .seconds(seconds))
        let pictures = max(1, editor.canvasFrameCount - before)
        editor.pauseDocument()
        var perFrame: [String: Double] = [:]
        for subject in ViewBuildMeter.Subject.allCases {
            let count = ViewBuildMeter.shared.count(subject)
            if count > 0 { perFrame[subject.rawValue] = (Double(count) / Double(pictures) * 100).rounded() / 100 }
        }
        run.bodiesPerFrame = perFrame
        let listed = perFrame.sorted { $0.value > $1.value }
            .map { String(format: "%@ %.2f", $0.key, $0.value) }.joined(separator: ", ")
        return "playing with nothing edited, \(pictures) new pictures in \(seconds)s; view bodies built per picture: "
            + (listed.isEmpty ? "none" : listed)
    }

    // MARK: - The timeline

    private func timeline(_ editor: EditorState) async throws -> String {
        guard editor.canOpenOutTheTimeline else {
            throw Failure(description: "the timeline cannot be zoomed in this window")
        }
        let frames = try frames(editor)
        defer { frames.invalidate() }
        editor.pauseDocument()
        let length = Double(editor.documentLengthMS)
        editor.fitTimeline()
        await settle(editor, frames: frames)
        let viewsAtFit = Self.viewCensus(editor)

        // How many clip bars each frame built, per measure, for the line.
        var barsPerFrame: [String] = []
        // How many lane paintings each frame laid into a
        // picture (`TimelinePaintedPicture`), per measure.
        var picturesPerFrame: [String] = []
        // A zoom's frames by how far in it was, so a slow stretch says where
        // it is: the median frame at each doubling of the zoom.
        var byZoom: [String] = []
        // The mean frame, beside the median: frames come in whole refreshes,
        // so a median sits on 16.7 ms until a change takes a whole refresh
        // off, and the mean shows a change smaller than that.
        var means: [String] = []
        // Near Fit, frames whose lanes stretched the painting they held
        // against frames whose lanes painted afresh
        // (`EditorState.timelineHeldPainting`), for the line.
        var heldSplit = ""
        // Along it, frames that moved the drawn stretch (every lane painted
        // again) against frames that only slid it (`timelineDrawnMS`).
        var movedSplit = ""
        func film(_ label: String, moves: Int, _ move: () -> Bool) async -> SpeedWalk.FrameTimes {
            ViewBuildMeter.shared.reset()
            TimelinePaintedPicture.laidMS = 0
            var at: [Double] = []
            var octaves: [Int: [Double]] = [:]
            defer {
                let built = ViewBuildMeter.shared.count(.clipBar)
                barsPerFrame.append(String(format: "%@ %.0f", label, Double(built) / Double(max(1, at.count - 1))))
                let laid = ViewBuildMeter.shared.count(.paintedPicture)
                picturesPerFrame.append(String(format: "%@ %.1f (%.2fms each)", label, Double(laid) / Double(max(1, at.count - 1)),
                                               TimelinePaintedPicture.laidMS / Double(max(1, laid))))
                if octaves.count > 1 {
                    byZoom.append(label + " " + octaves.keys.sorted().map { octave in
                        let times = (octaves[octave] ?? []).sorted()
                        return String(format: "%dx %.0fms", 1 << octave, times[times.count / 2])
                    }.joined(separator: " "))
                }
            }
            let start = CACurrentMediaTime()
            await frames.next()
            at.append(0)
            var held: [Double] = []
            var fresh: [Double] = []
            var slid: [Double] = []
            var moved: [Double] = []
            for _ in 0..<moves {
                let drawnBefore = editor.timelineDrawnMS
                // A timeline that cannot keep up is stopped at twenty seconds.
                guard CACurrentMediaTime() - start < 20, move() else { break }
                let stretchMoved = editor.timelineDrawnMS != drawnBefore
                let octave = max(0, Int(log2(max(1, editor.timelineZoom.scale)).rounded(.down)))
                let isHeld = editor.timelineHeldPainting != nil
                await frames.next()
                let now = (CACurrentMediaTime() - start) * 1000
                octaves[octave, default: []].append(now - (at.last ?? 0))
                if isHeld { held.append(now - (at.last ?? 0)) } else { fresh.append(now - (at.last ?? 0)) }
                if stretchMoved { moved.append(now - (at.last ?? 0)) } else { slid.append(now - (at.last ?? 0)) }
                at.append(now)
            }
            func worst(_ v: [Double]) -> Double { v.max() ?? 0 }
            if label == "near fit" {
                func mean(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count) }
                heldSplit = String(format: "; near fit held %d frames mean %.2fms, painted afresh %d mean %.2fms",
                                   held.count, mean(held), fresh.count, mean(fresh))
            }
            if label == "scroll" {
                func mean(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count) }
                movedSplit = String(format: "; scroll slid %d frames mean %.2fms worst %.0fms, stretch moved %d mean %.2fms worst %.0fms",
                                    slid.count, mean(slid), worst(slid), moved.count, mean(moved), worst(moved))
            }
            if at.count > 1, let last = at.last {
                means.append(String(format: "%@ %.2fms", label, last / Double(at.count - 1)))
            }
            return SpeedWalk.frameTimes(label, refreshesAtMS: at, refreshMS: frames.refreshInterval * 1000)
        }
        // In from the whole edit to as close as it goes, and back out.
        let zoomIn = await film("zoom in", moves: 240) {
            guard editor.canZoomTimelineIn else { return false }
            editor.zoomTimeline(by: 1.04, anchorMS: length / 2)
            return true
        }
        let zoomOut = await film("zoom out", moves: max(1, zoomIn.frames)) {
            guard editor.isTimelineOpenedOut else { return false }
            editor.zoomTimeline(by: 1 / 1.04, anchorMS: length / 2)
            return true
        }
        // Near the whole edit, where every clip is on screen at once and the
        // frames are the slowest: Fit to 8x and back, six times over. Said in
        // the line, not kept as a bar of the run (2026-11-17).
        editor.fitTimeline()
        await settle(editor, frames: frames)
        var nearFitIn = true
        let nearFit = await film("near fit", moves: 6 * 2 * 54) {
            let scale = editor.timelineZoom.scale
            if nearFitIn, scale >= 8 { nearFitIn = false }
            if !nearFitIn, scale <= 1.0001 { nearFitIn = true }
            editor.zoomTimeline(by: nearFitIn ? 1.04 : 1 / 1.04, anchorMS: length / 2)
            return true
        }
        // Along it, end to end, half a minute on screen, in three seconds.
        editor.fitTimeline()
        editor.zoomTimeline(by: max(1, length / 30_000), anchorMS: 0)
        editor.centreTimeline(onMS: 0)
        await settle(editor, frames: frames)
        let scrollable = max(1, editor.timelineScrollableMS)
        let moves = 360
        let scroll = await film("scroll", moves: moves) {
            guard editor.canScrollTimeline, editor.timelineWindow.startMS < scrollable - 1 else { return false }
            editor.panTimeline(byMS: scrollable / Double(moves))
            return true
        }
        let viewsZoomed = Self.viewCensus(editor)
        editor.fitTimeline()
        run.timeline = [zoomIn, zoomOut, scroll]
        return "views at fit: \(viewsAtFit); views zoomed in: \(viewsZoomed); clip bars built a frame: "
            + barsPerFrame.joined(separator: ", ") + "; paintings laid a frame: " + picturesPerFrame.joined(separator: ", ")
            + "; by zoom: " + byZoom.joined(separator: "; ") + "; mean frame: " + means.joined(separator: ", ") + heldSplit + movedSplit + "; "
            + [zoomIn, zoomOut, nearFit, scroll].map {
            String(format: "%@: %d frames, median %.1fms, p95 %.1fms, worst %.0fms, %d late against %.1fms",
                   $0.label, $0.frames, $0.medianMS, $0.p95MS, $0.worstMS, $0.late, $0.refreshMS)
        }.joined(separator: "; ")
    }

    /// How many AppKit views the window holds, by class, most first: a
    /// timeline that hangs a view per clip shows here first (2026-11-14).
    static func viewCensus(_ editor: EditorState) -> String {
        guard let root = editor.hostWindow?.contentView else { return "no window" }
        var counts: [String: Int] = [:]
        var total = 0
        func walk(_ v: NSView) {
            total += 1
            counts[String(describing: type(of: v)), default: 0] += 1
            v.subviews.forEach(walk)
        }
        walk(root)
        return "\(total) views: " + counts.sorted { $0.value > $1.value }.prefix(8)
            .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }

    // MARK: - Memory

    private func memory(_ editor: EditorState, _ step: PlaytestSpeedMeasure) async throws -> String {
        let seconds = step.seconds ?? 600
        let frames = try frames(editor)
        defer { frames.invalidate() }
        let length = editor.documentLengthMS
        var places = SpeedWalk.memoryScrubPlaces(count: Int(seconds / 30) + 1, lengthMS: length)[...]
        editor.pauseDocument()
        editor.scrubDocument(toMS: 0)
        await settle(editor, frames: frames)
        // Read on a timer of its own, off the main thread: reading the
        // footprint needs nothing of the app, and on the hour-long edit the
        // main thread let a reading through once every five minutes
        // (2026-11-13).
        let readings = MemoryReadings()
        readings.start()
        defer { readings.stop() }
        editor.playDocument(rate: 1)
        let start = CACurrentMediaTime()
        var nextScrub = 25.0
        while CACurrentMediaTime() - start < seconds {
            try? await Task.sleep(for: .seconds(1))
            // Every half minute a hand takes the playhead somewhere else
            // across two seconds, and it plays on from there.
            if CACurrentMediaTime() - start >= nextScrub {
                nextScrub += 30
                editor.pauseDocument()
                editor.beginPlayheadDrag()
                let from = editor.documentTimeMS
                let to = places.popFirst() ?? 0
                let scrubStart = CACurrentMediaTime()
                for index in 0...240 where CACurrentMediaTime() - scrubStart < 10 {
                    editor.dragPlayhead(toMS: from + (to - from) * index / 240)
                    await frames.next()
                }
                editor.endPlayheadDrag()
                editor.playDocument(rate: 1)
            }
            if !editor.isDocumentPlaying { editor.playDocument(rate: 1) }
        }
        editor.pauseDocument()
        readings.stop()
        let taken = readings.taken
        let minutes = run.minutes.map { "the \($0) minute edit" } ?? "the edit"
        let tally = SpeedWalk.MemoryTally(during: "playing and scrubbing \(minutes) for \(Int(seconds))s",
                                          footprintMB: taken.map(\.footprint), residentMB: taken.map(\.resident),
                                          atSeconds: taken.map(\.at))
        run.memory = tally
        var said = String(format: "%@: %d readings, footprint from %.0fMB to %.0fMB, peak %.0fMB; resident peak %.0fMB",
                          tally.during, taken.count, taken.first?.footprint ?? 0, taken.last?.footprint ?? 0,
                          tally.peakFootprintMB, tally.peakResidentMB)
        if let grew = tally.growthPercent, let from = tally.levelMB(minute: 2),
           let to = tally.levelMB(minute: tally.wholeMinutes) {
            said += String(format: "; sat at %.0fMB in minute 2 and %.0fMB in minute %d (%+.0f%%)",
                           from, to, tally.wholeMinutes, grew)
        }
        let problems = SpeedWalk.memoryProblems(tally, ceilingMB: step.ceilingMB, growthPercent: step.growthPercent)
        guard problems.isEmpty else {
            write()
            throw Failure(description: said + ". " + problems.joined(separator: "; "))
        }
        if let ceiling = step.ceilingMB { said += String(format: ", under its %.0fMB ceiling", ceiling) }
        return said
    }

    /// Memory read ten times a second on a queue of its own, and kept as one
    /// reading a second: the most that second reached, so a spike that comes
    /// and goes inside a second is still counted.
    private final class MemoryReadings: @unchecked Sendable {
        struct Reading { let at: Double; let footprint: Double; let resident: Double }
        private let lock = NSLock()
        private var kept: [Reading] = []
        private var second: Reading?
        private var ticks = 0
        private var timer: DispatchSourceTimer?
        private let began = CACurrentMediaTime()

        var taken: [Reading] { lock.withLock { kept } }

        func start() {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let reading = SpeedWalkProbe.memoryReading()
                let now = CACurrentMediaTime() - self.began
                self.lock.withLock {
                    let last = self.second
                    self.second = Reading(at: now, footprint: max(last?.footprint ?? 0, reading.footprint),
                                          resident: max(last?.resident ?? 0, reading.resident))
                    self.ticks += 1
                    if self.ticks % 10 == 0, let full = self.second {
                        self.kept.append(full)
                        self.second = nil
                    }
                }
            }
            timer.resume()
            lock.withLock { self.timer = timer }
        }

        func stop() {
            lock.withLock {
                timer?.cancel()
                timer = nil
            }
        }
    }

    /// The most memory the app has used since it was launched, the way
    /// Activity Monitor counts it: a walk launches the probe afresh, so this
    /// is the walk's own peak, spikes between readings included.
    nonisolated static func lifetimePeakMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS, info.ledger_phys_footprint_peak > 0 else { return nil }
        return Double(info.ledger_phys_footprint_peak) / (1024 * 1024)
    }

    nonisolated static func memoryReading() -> (footprint: Double, resident: Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let mb = 1024.0 * 1024
        return (Double(info.phys_footprint) / mb, Double(info.resident_size) / mb)
    }

    // MARK: - Export

    /// The export sheet's defaults (MP4, Standard, Full) written out and
    /// timed. The whole video, unless `seconds` names a stretch from `fromMS`
    /// (nought when left out): what a short walk times, as the sheet's In to
    /// Out writes it.
    /// `keep` keeps the file in the walk's folder under that name, and
    /// `throughPictures` draws it the way exports did before 2026-11-16, so
    /// the pictures the two make can be compared.
    private func export(_ editor: EditorState, _ step: PlaytestSpeedMeasure) async throws -> String {
        let fromMS = step.fromMS, seconds = step.seconds
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("photonz-speed-walk-export.mp4")
        try? FileManager.default.removeItem(at: url)
        defer {
            if let keep = step.keep {
                let kept = out.appendingPathComponent(keep)
                try? FileManager.default.removeItem(at: kept)
                try? FileManager.default.moveItem(at: url, to: kept)
            }
            try? FileManager.default.removeItem(at: url)
        }
        editor.pauseDocument()
        guard var document = editor.document else { throw Failure(description: "no document to export") }
        if let seconds {
            let start = max(0, fromMS ?? 0)
            document.setMarkIn(atMS: start)
            document.setMarkOut(atMS: min(document.documentDurationMS, start + Int(seconds * 1000)))
        }
        let length = Double(document.exportRangeMS(.marked).count) / 1000
        MainThreadMeter.shared.reset()
        let start = CACurrentMediaTime()
        let route = try await EditorState.writeVideo(of: document, pictures: editor.store, format: .mp4,
                                                     quality: .standard, size: .full, to: url,
                                                     range: seconds == nil ? .whole : .marked,
                                                     throughPictures: step.throughPictures)
        let taken = CACurrentMediaTime() - start
        let longest = MainThreadMeter.shared.longestMS
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        var tally = SpeedWalk.ExportTally(settings: "MP4, Standard, Full", seconds: taken,
                                          megabytes: Double(bytes) / 1_048_576, route: "\(route)",
                                          videoSeconds: length, longestMainPassMS: longest)
        tally.peakFootprintMB = Self.lifetimePeakMB()
        run.export = tally
        return String(format: "exported %.0fs of video at the sheet's defaults in %.1fs (%.2fx real time), %.0fMB, %@, longest main thread pass %.0fms, memory peak %.0fMB",
                      length, taken, taken / max(0.001, length), tally.megabytes, tally.route, longest,
                      tally.peakFootprintMB ?? 0)
    }

    // MARK: - Against a baseline

    private func compare(_ step: PlaytestSpeedMeasure) throws -> String {
        guard let name = step.baseline else { throw Failure(description: "no baseline named") }
        let url = name.hasPrefix("/") ? URL(fileURLWithPath: name)
            : scriptURL.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
        guard let data = try? Data(contentsOf: url) else {
            throw Failure(description: "no baseline at \(url.path)")
        }
        let baseline: SpeedRun
        do { baseline = try JSONDecoder().decode(SpeedRun.self, from: data) } catch {
            throw Failure(description: "the baseline at \(url.path) does not read: \(error)")
        }
        if run.export == nil { run.walkPeakFootprintMB = Self.lifetimePeakMB() }
        let worse = SpeedCompare.regressions(baseline: baseline, run: run, marginPercent: step.marginPercent)
        write()
        guard worse.isEmpty else {
            throw Failure(description: "\(worse.count) number(s) worse than the baseline (\(url.lastPathComponent), "
                + "\(baseline.head)) by more than \(Int(step.marginPercent))% and its floor: "
                + worse.joined(separator: "; "))
        }
        let judged = Set(baseline.metrics.map(\.key)).intersection(run.metrics.map(\.key)).count
        return "\(judged) numbers within \(Int(step.marginPercent))% of the baseline (\(url.lastPathComponent), "
            + "\(baseline.head)) and its floor"
    }

    // MARK: - The file

    private func write() {
        // The peak playing and editing is read up to the export; after it the
        // export's own peak is what grew (`ExportTally.peakFootprintMB`).
        if run.export == nil { run.walkPeakFootprintMB = Self.lifetimePeakMB() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(run) else { return }
        try? data.write(to: out.appendingPathComponent("speed.json"))
    }

    /// The commit the probe was built from, when the build said; the speed
    /// walk's command fills it in otherwise.
    private static var head: String {
        (Bundle.main.object(forInfoDictionaryKey: "PhotonzCommit") as? String) ?? "unknown"
    }

    private static var machine: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let name = String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let memory = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return String(format: "%@, %d cores, %.0fGB", name, ProcessInfo.processInfo.activeProcessorCount, memory)
    }
}
#endif

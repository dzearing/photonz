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
        case .memory: return try await memory(editor, seconds: step.seconds ?? 600)
        case .export: return try await export(editor)
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
        while CACurrentMediaTime() - start < seconds, editor.isDocumentPlaying {
            await frames.next()
            let now = CACurrentMediaTime() - start
            samples.append(SpeedWalk.PlaySample(wallMS: now * 1000, playheadMS: editor.documentTimeMS,
                                                shownMS: editor.shownMomentMS))
            if now >= nextSoundLook {
                looks += 1
                if !editor.audioPlayer.isPlaying { silent += 1 }
                nextSoundLook += 1
            }
        }
        samples.append(SpeedWalk.PlaySample(wallMS: (CACurrentMediaTime() - start) * 1000,
                                            playheadMS: editor.documentTimeMS, shownMS: editor.shownMomentMS))
        let leftOut = editor.audioPlayer.droppedSegments
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
        run.sound = SpeedWalk.SoundTally(piecesLeftOut: leftOut, silentLooks: silent, looks: looks)
        let worstCut = cuts.max { $0.worstGapMS < $1.worstGapMS }
        return String(format: "played %.1fs from %@ to %@: %d of %d frames shown, %d dropped, worst gap %.0fms",
                      whole.seconds, SpeedWalk.clock(fromMS), SpeedWalk.clock(reachedMS),
                      whole.framesShown, whole.framesDue, whole.dropped, whole.worstGapMS)
            + "; \(cuts.count) transitions crossed, \(cuts.filter { $0.dropped > 0 }.count) of them dropped frames"
            + (worstCut.map { String(format: ", the worst %@ (%d of %d dropped, gap %.0fms)", $0.label,
                                     $0.dropped, $0.framesDue, $0.worstGapMS) } ?? "")
            + "; sound: \(leftOut) piece(s) left out, silent at \(silent) of \(looks) one-second looks"
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
        let low = length / 50, high = length - length / 50
        var lines: [String] = []
        for speed in speeds {
            let count = PlaytestSpeedMeasure.scrubFrames(speed)
            editor.pauseDocument()
            editor.scrubDocument(toMS: low)
            await settle(editor, frames: frames)
            editor.beginPlayheadDrag()
            var hand: [Int] = [], handAt: [Double] = [], shown: [Int?] = [], at: [Double] = []
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
                // Past the end, it waits for the picture to arrive where the
                // hand stopped.
                if along >= 1, editor.shownMomentMS == editor.documentTimeMS { break }
            }
            editor.endPlayheadDrag()
            let refresh = frames.refreshInterval * 1000
            let lags = SpeedWalk.scrubLags(hand: hand, handAtMS: handAt, shown: shown, atMS: at,
                                                refreshMS: refresh)
            let stats = SpeedWalk.lagStats(lags)
            let times = SpeedWalk.frameTimes(speed, refreshesAtMS: at, refreshMS: refresh)
            run.scrubs.removeAll { $0.speed == speed }
            let made = looks
            let took = (at.last ?? 0) / 1000
            run.scrubs.append(SpeedWalk.ScrubTally(speed: speed, frames: count, lagMedianFrames: stats.median,
                                                   lagWorstFrames: stats.worst, worstFrameMS: times.worstMS,
                                                   movesMade: made, seconds: took))
            lines.append(String(format: "%@ (%d looks against %d refreshes, %.1fs against %.1fs at the display's pace): the picture "
                                + "trailed the hand by %d display frames in the middle, %d at worst; longest refresh %.0fms",
                                speed, made, count, took, Double(count) * refresh / 1000, stats.median, stats.worst,
                                times.worstMS))
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
        for edit in edits {
            if !editor.isDocumentPlaying { editor.playDocument(rate: 1) }
            MainThreadMeter.shared.reset()
            let began = CACurrentMediaTime()
            let did: String
            do {
                did = try perform(edit, on: editor)
            } catch let refused as Failure {
                // One edit that finds nothing to act on does not cost the
                // others their numbers: it is written down as not made.
                run.edits.removeAll { $0.edit == edit }
                run.edits.append(SpeedWalk.EditTally(edit: edit, did: "not made: \(refused.description)",
                                                     callMS: 0, longestPassMS: 0, made: false))
                lines.append("\(edit) not made: \(refused.description)")
                continue
            }
            let call = (CACurrentMediaTime() - began) * 1000
            try? await Task.sleep(for: .seconds(1.5))
            let longest = max(MainThreadMeter.shared.longestMS, call)
            let stillPlaying = editor.isDocumentPlaying
            run.edits.removeAll { $0.edit == edit }
            run.edits.append(SpeedWalk.EditTally(edit: edit, did: did, callMS: call, longestPassMS: longest))
            lines.append(String(format: "%@ (%@): %.0fms in the call, longest pass %.0fms%@", edit, did, call, longest,
                                stillPlaying ? "" : ", and it stopped playing"))
        }
        editor.pauseDocument()
        return "edited while it played: " + lines.joined(separator: "; ")
    }

    /// One edit a person makes while the video plays, on something just
    /// ahead of the playhead so what they are watching is what changes next.
    private func perform(_ edit: String, on editor: EditorState) throws -> String {
        guard let document = editor.document else { throw Failure(description: "no document") }
        let playhead = editor.documentTimeMS
        let pictureTracks = document.timelineTracks.filter { $0.kind == .video }
        func clips(onTrack index: Int) -> [Layer] {
            guard pictureTracks.indices.contains(index) else { return [] }
            return document.clipIDs(onTrack: pictureTracks[index].id).compactMap { document.layer(id: $0) }
                .filter { $0.movie != nil }
                .sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
        }
        // The main recordings sit on the picture track that holds the most.
        let byTrack = (0..<pictureTracks.count).map(clips(onTrack:))
        let main = byTrack.max { $0.count < $1.count } ?? []
        switch edit {
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
        case "blade":
            var under = (main + byTrack.flatMap { $0 }).first {
                ($0.time?.inMS ?? 0) + 100 < playhead && playhead < ($0.time?.outMS ?? 0) - 100
            }
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
            editor.selectLayer(clip.id)
            guard editor.canSplitClipAtPlayhead else { throw Failure(description: "\(clip.name) cannot be cut there") }
            editor.splitClipAtPlayhead()
            return "\(clip.name) cut at \(SpeedWalk.clock(editor.documentTimeMS))"
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
        func film(_ label: String, moves: Int, _ move: () -> Bool) async -> SpeedWalk.FrameTimes {
            ViewBuildMeter.shared.reset()
            var at: [Double] = []
            defer {
                let built = ViewBuildMeter.shared.count(.clipBar)
                barsPerFrame.append(String(format: "%@ %.0f", label, Double(built) / Double(max(1, at.count - 1))))
            }
            let start = CACurrentMediaTime()
            await frames.next()
            at.append(0)
            for _ in 0..<moves {
                // A timeline that cannot keep up is stopped at twenty seconds.
                guard CACurrentMediaTime() - start < 20, move() else { break }
                await frames.next()
                at.append((CACurrentMediaTime() - start) * 1000)
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
            + barsPerFrame.joined(separator: ", ") + "; " + [zoomIn, zoomOut, scroll].map {
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

    private func memory(_ editor: EditorState, seconds: Double) async throws -> String {
        let frames = try frames(editor)
        defer { frames.invalidate() }
        let length = editor.documentLengthMS
        var generator = SystemRandomNumberGenerator()
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
                let to = Int.random(in: 0...max(1, length - 30_000), using: &generator)
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
        return String(format: "%@: %d readings, footprint from %.0fMB to %.0fMB, peak %.0fMB; resident peak %.0fMB",
                      tally.during, taken.count, taken.first?.footprint ?? 0, taken.last?.footprint ?? 0,
                      tally.peakFootprintMB, tally.peakResidentMB)
    }

    /// Memory read once a second on a queue of its own.
    private final class MemoryReadings: @unchecked Sendable {
        struct Reading { let at: Double; let footprint: Double; let resident: Double }
        private let lock = NSLock()
        private var kept: [Reading] = []
        private var timer: DispatchSourceTimer?
        private let began = CACurrentMediaTime()

        var taken: [Reading] { lock.withLock { kept } }

        func start() {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let reading = SpeedWalkProbe.memoryReading()
                let now = CACurrentMediaTime() - self.began
                self.lock.withLock {
                    self.kept.append(Reading(at: now, footprint: reading.footprint, resident: reading.resident))
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

    private func export(_ editor: EditorState) async throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("photonz-speed-walk-export.mp4")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        editor.pauseDocument()
        let start = CACurrentMediaTime()
        // The export sheet's defaults: MP4, Standard, Full, the whole video
        // (the reference edit has no marks).
        let route = try await editor.writeVideo(format: .mp4, quality: .standard, size: .full, to: url)
        let seconds = CACurrentMediaTime() - start
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let tally = SpeedWalk.ExportTally(settings: "MP4, Standard, Full", seconds: seconds,
                                          megabytes: Double(bytes) / 1_048_576, route: "\(route)")
        run.export = tally
        let length = Double(editor.documentLengthMS) / 1000
        return String(format: "exported %.0fs of video at the sheet's defaults in %.1fs (%.2fx real time), %.0fMB, %@",
                      length, seconds, seconds / max(1, length), tally.megabytes, tally.route)
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

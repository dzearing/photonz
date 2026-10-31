import CoreGraphics
import Foundation
import ImageIO
import Observation
import PhotonzCore
import PhotonzRender

/// Ask in one editor window (`docs/design/ask.md`): what was asked, the model
/// on this Mac working it out, and the change it made, one row a request.
///
/// Planning only looks: the read-only tools run, every editing call is written
/// down. The moment the model is done, the steps run through the same tools
/// the MCP server offers, inside one undo step, so one Command Z takes the
/// whole request back (the user, 2026-10-20: "when I ask the agent to do
/// something, I want it to auto run"). A step that fails takes back what
/// already ran, so a bad plan leaves the document as it was. What landed is
/// one row in `changes`, which turns off, on again, or is deleted.
///
/// A request sent while one is working waits in `line` and runs when the one
/// before it is finished, so it plans against the document that one left. A
/// waiting request can be cancelled before it starts; closing the window
/// drops the line.
@MainActor
@Observable
final class AskSession {

    enum Phase: Equatable {
        case idle
        case planning
        case running
        case ran
        /// The model wrote no plan, or Ask could not reach it: one sentence why.
        case stopped(String)

        /// The phase's name, as a walk waits on it.
        var name: String {
            switch self {
            case .idle: "idle"
            case .planning: "planning"
            case .running: "running"
            case .ran: "ran"
            case .stopped: "stopped"
            }
        }

        var sentence: String? {
            if case .stopped(let words) = self { return words }
            return nil
        }
    }

    private(set) var phase: Phase = .idle
    /// The words in the composer. The first word typed starts Ask's model
    /// loading, so it is ready, or nearly, by the time the request is sent.
    var draft = "" {
        didSet { if oldValue.isEmpty, !draft.isEmpty { AskModelServer.shared.warm() } }
    }
    /// What was last asked.
    private(set) var asked = ""
    /// Every request that changed something, newest first.
    private(set) var changes = AskChangeList()
    /// Requests sent while one was working, waiting their turn.
    private(set) var line = AskRequestLine()
    /// The words of the request being worked on, from the send until its
    /// work has wound down, a stopped one included.
    private(set) var current: String?
    private(set) var plan: AskPlan?
    /// How many of the plan's steps have run.
    private(set) var stepsRun = 0
    /// Whether the composer is up over the canvas.
    var isComposerShown = false
    /// Once this window has asked, the panel keeps its Agent group.
    private(set) var hasAsked = false
    /// Bumped to ask the panel to open the Agent group and bring it into view.
    private(set) var revealPass = 0
    /// True from an ask until the panel has the Agent group on screen, so a
    /// panel the ask just brought out does the reveal when it appears.
    @ObservationIgnored var isRevealPending = false
    /// How long the last plan took, from Ask to the plan on screen.
    private(set) var lastPlanSeconds: Double?
    /// One line about the last request beside its row: that it made another
    /// kind of picture than the one asked for, and why.
    private(set) var said: String?

    @ObservationIgnored private var work: Task<Void, Never>?
    /// What the last plan did, a line a turn and a line a look, for a walk
    /// and for anybody finding out why a plan went the way it did.
    @ObservationIgnored private(set) var trace: [String] = []
    /// Where each drawing of the last run came from (stored, template or
    /// drawn), so the eval can count lookups.
    @ObservationIgnored private(set) var lastSources: [AskDrawingSource] = []
    /// The model the last request ran on.
    @ObservationIgnored private(set) var lastModel: String?
    /// Where each voted row's case was saved, so taking the vote back takes
    /// the case away too.
    @ObservationIgnored private var savedVotes: [UUID: URL] = [:]

    /// A request is being worked on: a send now waits in `line`.
    var isBusy: Bool { current != nil }

    /// The short state the Agent group's header carries: working while it
    /// works, else how many changes it holds.
    var chip: String? {
        isBusy ? AskCopy.workingChip : DockGroupHeader.countChip(changes.shown.count)
    }

    func openComposer() {
        isComposerShown = true
        AskModelServer.shared.warm()
    }

    func closeComposer() {
        isComposerShown = false
    }

    /// Why the last request asked with nothing open was not run (a video,
    /// or something that would already have to be open), shown under the
    /// field that asked it, which keeps the words. Cleared by the next ask.
    var refusal: String?
    /// Bumped to put the cursor in the New window's Describe field: Ask
    /// there is that field, not a composer over a canvas it does not have.
    private(set) var promptFocusPass = 0

    /// The title bar's Ask, Edit > Ask… and its key: the composer, or in the
    /// New window, its Describe field.
    func summon(in editor: EditorState) {
        if editor.isFrontDoor {
            promptFocusPass &+= 1
        } else {
            openComposer()
        }
    }

    /// Hands the composer's words to the model, or while it works on one,
    /// puts them in line behind it.
    ///
    /// In a window with nothing open, a request to make a picture makes a
    /// blank one here first, sized to the request (`AskFromNothing`), and Ask
    /// draws into it as it would on any picture. A request it cannot do with
    /// nothing open says why under the field and keeps the words.
    func ask(in editor: EditorState) {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        refusal = nil
        if editor.document == nil {
            switch AskFromNothing.start(words, picked: BlankCanvas.defaultPreset.size) {
            case nil: return
            case .video?:
                refusal = AskFromNothing.videoSentence
                return
            case .needsSomethingOpen?:
                refusal = AskFromNothing.nothingOpenSentence
                return
            case .picture(let size)?:
                editor.newBlankCanvas(size: size)
                guard editor.document != nil else { return }
            }
        }
        draft = ""
        send(words, in: editor)
    }

    /// Asks `words` in a window that was just made for them: the New
    /// window's Describe field opened this one holding a blank picture. Waits
    /// for the window to be on screen, since Ask reaches the document the way
    /// an agent does, through the windows that are open.
    func askOnceShown(_ words: String, in editor: EditorState) {
        hasAsked = true
        Task { [weak self, weak editor] in
            for _ in 0..<100 {
                guard let editor else { return }
                if editor.hostWindow?.isVisible == true, editor.agentID != nil { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let self, let editor else { return }
            self.send(words, in: editor)
        }
    }

    private func send(_ words: String, in editor: EditorState) {
        hasAsked = true
        isComposerShown = false
        // Whatever hides the Agent group comes out first: a video in View, a
        // closed panel. The panel may only be built after this, so the reveal
        // waits for it (`isRevealPending`).
        editor.bringAgentAreaForward()
        isRevealPending = true
        revealPass &+= 1
        if isBusy {
            line.add(words)
            return
        }
        start(words, in: editor)
    }

    private func start(_ typed: String, in editor: EditorState) {
        // "As a photo" makes the last request again that way.
        let words = AgentPictureKind.remade(typed, after: changes.rows.first?.asked) ?? typed
        said = nil
        asked = words
        current = words
        plan = nil
        stepsRun = 0
        phase = .planning
        let started = Date()
        trace = []
        lastSources = []
        work = Task { [weak self, weak editor] in
            if let editor {
                await self?.carryOut(words, in: editor, started: started)
            }
            self?.finished(in: editor)
        }
    }

    /// A request's work has ended, however it ended: the next in line starts,
    /// on the document as this one left it.
    private func finished(in editor: EditorState?) {
        current = nil
        work = nil
        guard let editor, let next = line.next() else { return }
        start(next.words, in: editor)
    }

    /// Takes a waiting request out of line before it starts.
    func cancelWaiting(_ id: UUID) {
        line.cancel(id)
    }

    /// The window is going: nothing waiting runs, and the request at work
    /// stops (its run, if part way, is taken back).
    func windowClosed() {
        line.clear()
        stop()
    }

    /// Plans, runs, and for a drawing looks at what it made, drawing it again
    /// at most twice when it does not read (`AskDrawingCheck`).
    private func carryOut(_ words: String, in editor: EditorState, started: Date) async {
        let began = Date()
        let note: (String) -> Void = { [weak self] line in
            self?.trace.append(String(format: "%.1fs ", Date().timeIntervalSince(began)) + line)
        }
        let model: String
        let found = await AskLocalModel.model()
        guard !Task.isCancelled else { return }
        switch found {
        case .success(let found):
            model = found
            lastModel = found
        case .failure(let trouble):
            phase = .stopped(trouble.sentence)
            return
        }
        // What this window's earlier requests did and made (`AskMemory`).
        let remembered = editor.document.map { AskMemory.turns(from: changes, in: $0) } ?? []
        if !remembered.isEmpty { note("remembering \(remembered.count) earlier requests") }
        let memory = AskMemory.prompt(remembered)
        let opened = await Self.conversation(words, in: editor, model: model, memory: memory, note: note)
        guard !Task.isCancelled else { return }
        guard var talk = opened else {
            phase = .stopped(AskCopy.noDocumentSentence)
            return
        }
        var revisions = 0
        // The plans the first try's drawings were checked against, held for
        // every try after it, and the closest try so far, kept to land if a
        // later one comes out worse.
        var carried: [[String]]?
        var closest: (attempt: AskDrawingCheck.Attempt, after: PhotonzDocument, ran: Ran, plan: AskPlan)?
        while true {
            let outcome = await Self.plan(&talk, model: model, in: editor, note: note)
            guard !Task.isCancelled else { return }
            lastPlanSeconds = Date().timeIntervalSince(started)
            var plan: AskPlan
            switch outcome {
            case .success(let planned): plan = planned
            case .failure(let trouble):
                phase = .stopped(trouble.sentence)
                return
            }
            if let carrying = carried.flatMap({ AskDrawingCheck.carryingPlans($0, into: plan) }) {
                plan = carrying
            } else {
                plan = await Self.withDrawingPlans(plan, asked: words, model: model, note: note)
            }
            guard !Task.isCancelled else { return }
            carried = carried ?? AskDrawingCheck.drawings(in: plan).map(\.plan)
            self.plan = plan
            guard let ran = await run(plan, in: editor) else { return }
            let miss = await look(at: plan, made: ran.made, in: editor, model: model, note: note)
            if Task.isCancelled {
                // Stopped while it looked at what it drew: what ran comes
                // back off, so a stop leaves the document as it was.
                editor.undo()
                stepsRun = 0
                phase = .stopped(AskCopy.stoppedSentence)
                return
            }
            var landed = ran
            let attempt = AskDrawingCheck.Attempt(reads: miss.map { !$0.unmet.isEmpty } ?? true, missed: miss?.unmet.count ?? 0)
            if miss != nil, revisions >= AskDrawingCheck.mostRevisions, let held = closest,
               !AskDrawingCheck.isCloser(attempt, than: held.attempt) {
                // The last try came out worse than an earlier one: that one
                // lands in its place, the closest Ask came.
                editor.undo()
                editor.perform { $0 = held.after }
                landed = held.ran
                lastSources = held.ran.sources
                self.plan = held.plan
                note("keeping an earlier drawing: it showed all but \(held.attempt.missed) of its plan")
            } else if let miss, !miss.unmet.isEmpty, revisions >= AskDrawingCheck.mostRevisions {
                // It reads as the thing but still misses part of its plan
                // after the last try: it stays, the closest Ask came.
                note("keeping the last drawing: still not shown: \(miss.unmet.joined(separator: "; "))")
            } else if let miss {
                if AskDrawingCheck.isCloser(attempt, than: closest?.attempt), let after = editor.document {
                    closest = (attempt, after, ran, plan)
                }
                // What was drawn does not read as what was asked, or does not
                // show what its plan said: it comes back off, and is drawn
                // again or owned up to.
                editor.undo()
                guard revisions < AskDrawingCheck.mostRevisions, !Task.isCancelled else {
                    stepsRun = 0
                    lastPlanSeconds = Date().timeIntervalSince(started)
                    phase = .stopped(AskCopy.couldNotDraw)
                    return
                }
                revisions += 1
                note(miss.unmet.isEmpty
                     ? "drawing again (\(revisions)): \(miss.subject) was seen as \(miss.seen)"
                     : "drawing again (\(revisions)): \(miss.subject) does not show \(miss.unmet.joined(separator: "; "))")
                talk.revise(subject: miss.subject, seen: miss.seen, unmet: miss.unmet)
                phase = .planning
                continue
            }
            if let after = editor.document {
                changes.record(asked: words, sentence: AskChangeWords.sentence(landed.landed, asked: words,
                                                                              before: landed.before, after: after),
                               before: landed.before, after: after, sources: landed.sources)
            }
            lastPlanSeconds = Date().timeIntervalSince(started)
            note("done")
            said = talk.note
            phase = .ran
            revealRows()
            return
        }
    }

    /// Stops planning or running. A run stopped part way is taken back.
    func stop() {
        work?.cancel()
        work = nil
        if phase == .planning { phase = .idle }
    }

    /// Steps the app refused, by number, with its reason. A refused step
    /// changed nothing, so the rest ran without it.
    private(set) var skipped: [Int: String] = [:]

    struct Ran {
        let before: PhotonzDocument
        let landed: [AskStep]
        /// What each step made, by step number.
        let made: [Int: String]
        let sources: [AskDrawingSource]
    }

    /// Runs the plan as one undo step. Nil when nothing is left changed: the
    /// phase then says why.
    private func run(_ plan: AskPlan, in editor: EditorState) async -> Ran? {
        guard let document = editor.agentID, let before = editor.document else {
            phase = .stopped(AskCopy.noDocumentSentence)
            return nil
        }
        phase = .running
        stepsRun = 0
        skipped = [:]
        var failure: String?
        var landed: [AskStep] = []
        var made: [Int: String] = [:]
        var sources: [AskDrawingSource] = []
        await editor.asOneUndoStepAwaiting {
            for (index, step) in plan.steps.enumerated() {
                let number = index + 1
                if Task.isCancelled { failure = AskCopy.stoppedSentence; return }
                var refusal: String?
                switch step.request(document: document, made: made) {
                case .failure(let refused):
                    refusal = refused.message
                case .success(let request):
                    let answer = await AgentWork.run(request)
                    let text = Self.text(of: answer)
                    if answer.isError {
                        refusal = text
                    } else {
                        landed.append(step)
                        if let id = AskStep.madeID(fromAnswer: text) { made[number] = id }
                        if let source = AskDrawingSource.of(tool: step.tool, answer: text) { sources.append(source) }
                    }
                }
                if let refusal {
                    skipped[number] = refusal
                    // Passed over, unless a later step counts on it.
                    if plan.isNamedLater(number) {
                        failure = AskCopy.stepFailed(number)
                        return
                    }
                }
                stepsRun = number
            }
        }
        if let failure {
            // What ran is one step in the history: take it back, so a plan
            // that went wrong half way leaves nothing half done.
            if !landed.isEmpty { editor.undo() }
            stepsRun = 0
            phase = .stopped(failure)
            return nil
        }
        guard !landed.isEmpty else {
            phase = .stopped(AskCopy.nothingRan)
            return nil
        }
        lastSources = sources
        return Ran(before: before, landed: landed, made: made, sources: sources)
    }

    /// The first drawing the plan made that a model that can see does not
    /// take for what was asked, or that does not show a statement of its
    /// plan (`unmet`), or nil when each reads (or nothing on this Mac can
    /// see, or nothing was drawn).
    private func look(at plan: AskPlan, made: [Int: String], in editor: EditorState, model: String,
                      note: (String) -> Void) async -> (subject: String, seen: String, unmet: [String])? {
        let drawings = AskDrawingCheck.drawings(in: plan)
        guard !drawings.isEmpty, let document = editor.agentID else { return nil }
        let installed = await AskLocalModel.installed() ?? []
        let ownEyes = await AskLocalModel.sees(model)
        guard let eyes = AskLocalModel.eyesOverride.flatMap({ installed.contains($0) ? $0 : nil })
                ?? AskModels.eyes(planner: model, plannerSees: ownEyes, installed: installed) else {
            note("look skipped: no model on this Mac can see")
            return nil
        }
        for drawing in drawings {
            guard let layer = made[drawing.step] else { continue }
            let picture = await AgentWork.run(.renderPicture(document: document, layer: layer, region: nil, maxSize: 512))
            guard let drawn = picture.content.compactMap({ part -> Data? in
                if case .png(let data) = part { return data }
                return nil
            }).first else { continue }
            let png = Self.onWhite(drawn)
            guard let seen = try? await AskLocalModel.chat(AskDrawingCheck.visionBody(model: eyes, png: png, planner: eyes == model))["message"]?["content"]?
                .stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !seen.isEmpty else {
                note("look: \(eyes) gave no answer")
                continue
            }
            var reads = AskDrawingCheck.reads(seen, as: drawing.subject)
            if reads == nil, let answer = try? await AskLocalModel.chat(
                AskDrawingCheck.judgeBody(model: model, subject: drawing.subject, seen: seen))["message"]?["content"]?.stringValue {
                reads = AskDrawingCheck.judged(answer)
            }
            note("look: \(drawing.subject) seen as \(seen) -> \(reads == true ? "reads" : "does not read")")
            if reads != true { return (drawing.subject, seen, []) }
            // It reads as the thing; now whether it shows the pose, the view
            // and the relationships its plan named.
            guard !drawing.plan.isEmpty,
                  let answer = try? await AskLocalModel.chat(AskDrawingCheck.planBody(
                      model: eyes, png: png, plan: drawing.plan, planner: eyes == model))["message"]?["content"]?.stringValue
            else { continue }
            let unmet = AskDrawingCheck.unmet(answer, plan: drawing.plan)
            note("look: plan \(drawing.plan.count - unmet.count) of \(drawing.plan.count) shown"
                 + (unmet.isEmpty ? "" : ", not: \(unmet.joined(separator: "; "))"))
            if !unmet.isEmpty { return (drawing.subject, seen, unmet) }
        }
        return nil
    }
    /// The plan with every drawing the model sent without a plan given one,
    /// asked of the planning model drawing by drawing, so a pose or a scene
    /// is painted from its statements and checked against them whichever
    /// model planned it. A plain thing's answer is none and leaves it as sent.
    /// Then every plan keeps only the statements the person's words ask for
    /// (`AskDrawingCheck.groundingBody`), so nothing is painted again for a
    /// detail nobody named.
    private static func withDrawingPlans(_ plan: AskPlan, asked words: String, model: String,
                                         note: (String) -> Void) async -> AskPlan {
        var plan = plan
        for drawing in AskDrawingCheck.unplanned(in: plan) {
            guard !Task.isCancelled,
                  let answer = try? await AskLocalModel.chat(AskDrawingCheck.planningBody(model: model, subject: drawing.subject))["message"]?["content"]?
                      .stringValue else { continue }
            let statements = AskDrawingCheck.statements(fromAnswer: answer)
            note("plan for \(drawing.subject): " + (statements.isEmpty ? "none" : statements.joined(separator: "; ")))
            plan = plan.settingDrawingPlan(step: drawing.step, to: statements)
        }
        for drawing in AskDrawingCheck.drawings(in: plan) where !drawing.plan.isEmpty {
            guard !Task.isCancelled,
                  let answer = try? await AskLocalModel.chat(AskDrawingCheck.groundingBody(model: model, request: words, plan: drawing.plan))["message"]?["content"]?
                      .stringValue else { continue }
            let kept = AskDrawingCheck.grounded(drawing.plan, answer: answer)
            guard kept != drawing.plan else { continue }
            note("plan asked for: " + (kept.isEmpty ? "none" : kept.joined(separator: "; ")))
            plan = plan.replacingDrawingPlan(step: drawing.step, with: kept)
        }
        return plan
    }

    /// A drawing rendered on its own has nothing behind it; the model that
    /// looks is shown it on white, the way it sits on a blank canvas, so a
    /// black drawing is not black on black to it.
    static func onWhite(_ png: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return png }
        let box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(box)
        context.draw(image, in: box)
        let out = NSMutableData()
        guard let flat = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return png }
        CGImageDestinationAddImage(destination, flat, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : png
    }

    // MARK: The rows

    /// Turns a request's change off or on, as one undo step. When something
    /// later builds on it, nothing moves and the row says so.
    func setChange(_ id: UUID, on: Bool, in editor: EditorState) {
        guard let document = editor.document else { return }
        land(changes.setOn(on, id: id, in: document), in: editor)
    }

    /// Puts the person's thumbs on a row (the same thumbs again takes it
    /// back). The request, the document before it and what it made are saved
    /// beside the vote, so a thumbs down becomes a case the eval has never
    /// seen (`Scripts/ask-eval/README.md`, "The held-out set").
    func vote(_ verdict: AskVerdict, on id: UUID, in editor: EditorState) {
        let now = changes.vote(verdict, id: id)
        guard let now, let row = changes.row(id) else {
            if let folder = savedVotes.removeValue(forKey: id) { try? FileManager.default.removeItem(at: folder) }
            return
        }
        guard let root = AskFeedbackFolder.root() else { return }
        let folder = savedVotes[id] ?? root.appendingPathComponent(
            AskFeedbackCase.folderName(request: row.asked, at: Date()), isDirectory: true)
        let saved = AskFeedbackCase(
            request: row.asked, verdict: now, at: ISO8601DateFormatter().string(from: Date()),
            sentence: row.sentence, sources: row.sources,
            canvas: [Double(row.change.before.canvasSize.width), Double(row.change.before.canvasSize.height)],
            model: lastModel, app: Bundle.main.bundleIdentifier ?? "Photonz")
        do {
            try AskFeedbackFolder.write(saved, before: row.change.before, after: row.change.after,
                                        editor: editor, into: folder, documentsToo: savedVotes[id] == nil)
            savedVotes[id] = folder
        } catch {
            note("vote: could not save the case: \(error)")
        }
    }

    private func note(_ line: String) { trace.append(line) }

    /// Deletes a request's row, taking its change out first when it is on.
    func deleteChange(_ id: UUID, in editor: EditorState) {
        guard let document = editor.document else { return }
        land(changes.delete(id: id, in: document), in: editor)
    }

    /// Picks on the canvas what a row's change made, the mock's Last change
    /// click: the selection jumps there so the person can keep going by hand.
    func pickChange(_ id: UUID, in editor: EditorState) {
        guard let row = changes.row(id), row.isOn, let document = editor.document else { return }
        let ids = row.change.madeLayerIDs(in: document)
        guard !ids.isEmpty else { return }
        editor.selectLayers(Set(ids))
    }

    private func land(_ outcome: AskRecordedChange.Outcome, in editor: EditorState) {
        guard case .changed(let next) = outcome else { return }
        editor.perform { $0 = next }
        revealRows()
    }

    /// A change landing picks a layer or drops one, and the panel fills with
    /// that layer's sections or loses them, a frame or two later: the Agent
    /// group is brought back into view now and once more when that settles,
    /// so the row a person just pressed stays under their pointer.
    private func revealRows() {
        revealPass &+= 1
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.revealPass &+= 1
        }
    }

    /// After an undo or a redo stepped the document, each row reads whether
    /// its change is in it now.
    func follow(_ document: PhotonzDocument?) {
        guard let document, !changes.rows.isEmpty else { return }
        changes.follow(document)
    }

    /// The talk with the model, opened with the document read and the
    /// Library handed over up front: "on brand" is its components and styles.
    private static func conversation(_ words: String, in editor: EditorState, model: String, memory: String = "",
                                     note: (String) -> Void) async -> AskConversation? {
        guard let document = editor.agentID else { return nil }
        note("model \(model), reading \(document)")
        let read = await AgentWork.run(.readDocument(document: document, layer: nil))
        note("read \(Self.text(of: read).count) characters")
        let components = await AgentWork.run(.listComponents(document: document))
        let styles = await AgentWork.run(.listStyles(document: document))
        // On a video, the title styles add_title takes by name.
        let titles = editor.documentHasTime ? await AgentWork.run(.listTitles(document: document)) : nil
        let paints = AskPictureModel.isReady()
        if paints { note("drawings painted by the picture model") }
        // Only when there is something of Ask's or the person's to look at:
        // a blank canvas or a lone screenshot plans as it always did.
        let canvas = !memory.isEmpty || (editor.document?.layers.count ?? 0) > 1
            ? await Self.canvasPicture(of: document, in: editor, model: model) : nil
        if let canvas { note("canvas picture, \(canvas.count / 1024) KB") }
        return AskConversation(request: words, documentRead: Self.text(of: read),
                               components: components.isError ? "" : AskTools.withoutStarters(Self.text(of: components)),
                               styles: styles.isError ? "" : Self.text(of: styles),
                               titles: titles.map { $0.isError ? "" : Self.text(of: $0) } ?? "",
                               paints: paints,
                               brushes: Experiments.shared.brushEnabled && !editor.documentHasTime,
                               memory: memory, canvas: canvas)
    }

    /// The longest side of the canvas picture the planning model is shown.
    static let canvasPictureSide = 768

    /// The canvas as it is now, for a planning model that sees, so "bluer"
    /// and "bigger" are judged against what is really there. Nil for a model
    /// that cannot see or a video.
    private static func canvasPicture(of document: String, in editor: EditorState, model: String) async -> Data? {
        guard !editor.documentHasTime, await AskLocalModel.sees(model) else { return nil }
        let picture = await AgentWork.run(.renderPicture(document: document, layer: nil, region: nil,
                                                         maxSize: canvasPictureSide))
        guard let png = picture.content.compactMap({ part -> Data? in
            if case .png(let data) = part { return data }
            return nil
        }).first else { return nil }
        return onWhite(png)
    }

    /// The model's turns, until it stops calling tools.
    private static func plan(_ talk: inout AskConversation, model: String, in editor: EditorState,
                             note: (String) -> Void) async -> Result<AskPlan, AskLocalModel.Trouble> {
        guard let document = editor.agentID else { return .failure(.said(AskCopy.noDocumentSentence)) }
        while talk.rounds < AskConversation.mostRounds {
            let reply: AgentJSON
            do {
                note("asking the model")
                reply = try await AskLocalModel.chat(talk.chatBody(model: model))
                // Long enough to hold a whole component call, so a look the
                // planner let through can be rebuilt from the trace (a blue
                // Off toggle could not be, cut at 300, 2026-10-24).
                note("answered: \(reply["message"]?.encodedString().prefix(3000) ?? "")")
            } catch let trouble as AskLocalModel.Trouble {
                if case .said(let words) = trouble, AskConversation.isUnreadableReply(words), !talk.steps.isEmpty {
                    if talk.askForTitle() {
                        note("unreadable reply after \(talk.steps.count) steps: asking for the sheet's title first")
                        continue
                    }
                    note("unreadable reply after \(talk.steps.count) steps: offering them")
                    return .success(AskPlan(steps: talk.steps, summary: "", names: talk.names))
                }
                return .failure(trouble)
            } catch {
                return .failure(.said(AskCopy.stoppedSentence))
            }
            if Task.isCancelled { return .failure(.said(AskCopy.stoppedSentence)) }
            let heard = talk.messages.count
            let outcome = talk.take(reply)
            note("turn \(talk.rounds): \(talk.steps.count) steps planned, \(talk.calls) calls, \(talk.brokenCalls) broken")
            // Why a call was refused, so a run's trace says what the model was told.
            for message in talk.messages.dropFirst(heard) where message["role"]?.stringValue == "tool" {
                if let said = message["content"]?.stringValue, said.hasPrefix("Not planned") { note("refused: \(said.prefix(300))") }
            }
            switch outcome {
            case .planned(let plan):
                return .success(plan)
            case .cannot(let sentence):
                return .failure(.said(sentence))
            case .again(let looks):
                for look in looks {
                    note("look \(look.tool) \(look.arguments.encodedString().prefix(120))")
                    var arguments = look.arguments.objectValue ?? [:]
                    arguments["document"] = .string(document)
                    let answer: String
                    switch AgentTools.request(tool: look.tool, arguments: .object(arguments)) {
                    case .success(let request):
                        let said = Self.text(of: await AgentWork.run(request))
                        answer = look.tool == "list_components" ? AskTools.withoutStarters(said) : said
                    case .failure(let refused): answer = refused.message
                    }
                    talk.answer(look, with: answer)
                }
            }
        }
        // Out of turns with steps written: offer what it has.
        if !talk.steps.isEmpty { return .success(AskPlan(steps: talk.steps, summary: "", names: talk.names)) }
        return .failure(.said(AskConversation.noPlanSentence))
    }

    private static func text(of answer: AgentWork.Answer) -> String {
        answer.content.compactMap { part -> String? in
            if case .text(let words) = part { return words }
            return nil
        }.joined(separator: "\n")
    }
}

/// Every word Ask puts on screen, in one place, to the chrome's budgets.
enum AskCopy {
    static let button = "Ask"
    static let buttonTooltip = "Ask for a change"
    static let menuRow = "Ask…"
    static let composerPlaceholder = "Ask for a change"
    static let composerHeader = "Agent"
    static let onDevice = "on-device"
    static let empty = "Ask for something"
    static let stop = "Stop"
    static let stopTooltip = "Stop this request"
    static let waiting = "Waiting"
    static let cancelWaiting = "Cancel"
    static let cancelWaitingTooltip = "Cancel this request"
    static let workingChip = "working"
    static let nothingRan = "None of it could run. Nothing was changed."
    static let workingLine = "Working…"
    /// The built-in model is loading into memory, the first request after a while.
    static let gettingReady = "Getting the model ready…"
    static let setUp = "Open Settings"
    static let turnOff = "Turn Off"
    static let turnOn = "Turn On"
    static let delete = "Delete"
    static let deleteTooltip = "Delete this change"
    static let goodResult = "Good Result"
    static let badResult = "Bad Result"
    static let stoppedSentence = "Stopped. Nothing was changed."
    static let noDocumentSentence = "Open a picture or video first."
    static func stepFailed(_ n: Int) -> String { "Step \(n) failed. Nothing was changed." }
    /// A drawing that still did not read after being drawn again.
    static let couldNotDraw = "I couldn't make a clear drawing of that. Nothing was changed."
    static let helpLine = "Each request is one row. Its switch turns the change off and on, and one Command Z takes back the latest. A request sent while one is working waits its turn."
}

/// Where a vote on one of Ask's rows is saved:
/// `~/Library/Application Support/<bundle id>/Ask feedback/<time-request>/`,
/// holding `case.json`, `before.photonz`, `after.photonz` and `after.png`.
enum AskFeedbackFolder {

    static func root() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.dzearing.photonz", isDirectory: true)
            .appendingPathComponent("Ask feedback", isDirectory: true)
    }

    /// Writes the case; the documents only the first time, since a swapped
    /// vote changes nothing but the verdict.
    @MainActor
    static func write(_ saved: AskFeedbackCase, before: PhotonzDocument, after: PhotonzDocument,
                      editor: EditorState, into folder: URL, documentsToo: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if documentsToo {
            try PackageIO.write(before, store: editor.store, to: folder.appendingPathComponent("before.photonz"))
            try PackageIO.write(after, store: editor.store, to: folder.appendingPathComponent("after.photonz"))
            if let picture = editor.previewRenderer.render(after, store: editor.store),
               let png = ImageCodec.encode(picture, format: .png) {
                try png.write(to: folder.appendingPathComponent("after.png"))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(saved).write(to: folder.appendingPathComponent("case.json"), options: .atomic)
    }
}

/// A request typed into the New window's Describe field, held from the moment
/// it asks for a window until that window is seeded with its blank picture.
@MainActor
enum AskHandoff {
    private static var held: [UUID: String] = [:]

    static func hold(_ words: String, for window: UUID) { held[window] = words }

    static func take(_ window: UUID) -> String? { held.removeValue(forKey: window) }
}

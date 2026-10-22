import Foundation
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
    /// The words in the composer.
    var draft = ""
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
    }

    func closeComposer() {
        isComposerShown = false
    }

    /// Hands the composer's words to the model, or while it works on one,
    /// puts them in line behind it.
    func ask(in editor: EditorState) {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        draft = ""
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

    private func start(_ words: String, in editor: EditorState) {
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
        let opened = await Self.conversation(words, in: editor, model: model, note: note)
        guard !Task.isCancelled else { return }
        guard var talk = opened else {
            phase = .stopped(AskCopy.noDocumentSentence)
            return
        }
        var revisions = 0
        while true {
            let outcome = await Self.plan(&talk, model: model, in: editor, note: note)
            guard !Task.isCancelled else { return }
            lastPlanSeconds = Date().timeIntervalSince(started)
            let plan: AskPlan
            switch outcome {
            case .success(let planned): plan = planned
            case .failure(let trouble):
                phase = .stopped(trouble.sentence)
                return
            }
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
            if let miss {
                // What was drawn does not read as what was asked: it comes
                // back off, and is drawn again or owned up to.
                editor.undo()
                guard revisions < AskDrawingCheck.mostRevisions, !Task.isCancelled else {
                    stepsRun = 0
                    lastPlanSeconds = Date().timeIntervalSince(started)
                    phase = .stopped(AskCopy.couldNotDraw)
                    return
                }
                revisions += 1
                note("drawing again (\(revisions)): \(miss.subject) was seen as \(miss.seen)")
                talk.revise(subject: miss.subject, seen: miss.seen)
                phase = .planning
                continue
            }
            if let after = editor.document {
                changes.record(asked: words, sentence: AskChangeWords.sentence(ran.landed, asked: words,
                                                                              before: ran.before, after: after),
                               before: ran.before, after: after, sources: ran.sources)
            }
            lastPlanSeconds = Date().timeIntervalSince(started)
            note("done")
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
    /// take for what was asked, or nil when each reads (or nothing on this
    /// Mac can see, or nothing was drawn).
    private func look(at plan: AskPlan, made: [Int: String], in editor: EditorState, model: String,
                      note: (String) -> Void) async -> (subject: String, seen: String)? {
        let drawings = AskDrawingCheck.drawings(in: plan, library: DrawingSet.shared)
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
            guard let png = picture.content.compactMap({ part -> Data? in
                if case .png(let data) = part { return data }
                return nil
            }).first else { continue }
            guard let seen = try? await AskLocalModel.chat(AskDrawingCheck.visionBody(model: eyes, png: png, planner: eyes == model))["message"]?["content"]?
                .stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !seen.isEmpty else {
                note("look: \(eyes) gave no answer")
                continue
            }
            var reads = AskDrawingCheck.reads(seen, as: drawing.subject, library: DrawingSet.shared)
            if reads == nil, let answer = try? await AskLocalModel.chat(
                AskDrawingCheck.judgeBody(model: model, subject: drawing.subject, seen: seen))["message"]?["content"]?.stringValue {
                reads = AskDrawingCheck.judged(answer)
            }
            note("look: \(drawing.subject) seen as \(seen) -> \(reads == true ? "reads" : "does not read")")
            if reads != true { return (drawing.subject, seen) }
        }
        return nil
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
    private static func conversation(_ words: String, in editor: EditorState, model: String,
                                     note: (String) -> Void) async -> AskConversation? {
        guard let document = editor.agentID else { return nil }
        note("model \(model), reading \(document)")
        let read = await AgentWork.run(.readDocument(document: document, layer: nil))
        note("read \(Self.text(of: read).count) characters")
        let components = await AgentWork.run(.listComponents(document: document))
        let styles = await AgentWork.run(.listStyles(document: document))
        // On a video, the title styles add_title takes by name.
        let titles = editor.documentHasTime ? await AgentWork.run(.listTitles(document: document)) : nil
        let paints = await AskPictureModel.isReady()
        if paints { note("drawings painted by the picture model") }
        return AskConversation(request: words, documentRead: Self.text(of: read),
                               components: components.isError ? "" : Self.text(of: components),
                               styles: styles.isError ? "" : Self.text(of: styles),
                               titles: titles.map { $0.isError ? "" : Self.text(of: $0) } ?? "",
                               drawings: DrawingSet.shared, paints: paints)
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
                note("answered: \(reply["message"]?.encodedString().prefix(300) ?? "")")
            } catch let trouble as AskLocalModel.Trouble {
                return .failure(trouble)
            } catch {
                return .failure(.said(AskCopy.stoppedSentence))
            }
            if Task.isCancelled { return .failure(.said(AskCopy.stoppedSentence)) }
            let outcome = talk.take(reply)
            note("turn \(talk.rounds): \(talk.steps.count) steps planned, \(talk.calls) calls, \(talk.brokenCalls) broken")
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
                    case .success(let request): answer = Self.text(of: await AgentWork.run(request))
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

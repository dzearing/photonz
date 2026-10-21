import Foundation
import Observation
import PhotonzCore

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

    var isBusy: Bool { phase == .planning || phase == .running }

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

    /// Hands the composer's words to the model.
    func ask(in editor: EditorState) {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !isBusy else { return }
        asked = words
        draft = ""
        plan = nil
        stepsRun = 0
        hasAsked = true
        isComposerShown = false
        phase = .planning
        // Whatever hides the Agent group comes out first: a video in View, a
        // closed panel. The panel may only be built after this, so the reveal
        // waits for it (`isRevealPending`).
        editor.bringAgentAreaForward()
        isRevealPending = true
        revealPass &+= 1
        let started = Date()
        trace = []
        work = Task { [weak self, weak editor] in
            guard let editor else { return }
            await self?.carryOut(words, in: editor, started: started)
        }
    }

    /// Plans, runs, and for a drawing looks at what it made, drawing it again
    /// at most twice when it does not read (`AskDrawingCheck`).
    private func carryOut(_ words: String, in editor: EditorState, started: Date) async {
        let began = Date()
        let note: (String) -> Void = { [weak self] line in
            self?.trace.append(String(format: "%.1fs ", Date().timeIntervalSince(began)) + line)
        }
        let model: String
        switch await AskLocalModel.model() {
        case .success(let found): model = found
        case .failure(let trouble):
            phase = .stopped(trouble.sentence)
            return
        }
        guard var talk = await Self.conversation(words, in: editor, model: model, note: note) else {
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
            if let miss = await look(at: plan, made: ran.made, in: editor, model: model, note: note) {
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
                changes.record(asked: words, sentence: AskChangeWords.sentence(ran.landed),
                               before: ran.before, after: after)
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
        return Ran(before: before, landed: landed, made: made)
    }

    /// The first drawing the plan made that a model that can see does not
    /// take for what was asked, or nil when each reads (or nothing on this
    /// Mac can see, or nothing was drawn).
    private func look(at plan: AskPlan, made: [Int: String], in editor: EditorState, model: String,
                      note: (String) -> Void) async -> (subject: String, seen: String)? {
        let drawings = AskDrawingCheck.drawings(in: plan, library: DrawingSet.shared)
        guard !drawings.isEmpty, let document = editor.agentID else { return nil }
        guard let eyes = AskModels.vision(installed: await AskLocalModel.installed() ?? []) else {
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
            guard let seen = try? await AskLocalModel.chat(AskDrawingCheck.visionBody(model: eyes, png: png))["message"]?["content"]?
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
        return AskConversation(request: words, documentRead: Self.text(of: read),
                               components: components.isError ? "" : Self.text(of: components),
                               styles: styles.isError ? "" : Self.text(of: styles),
                               titles: titles.map { $0.isError ? "" : Self.text(of: $0) } ?? "",
                               drawings: DrawingSet.shared)
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
            note("turn \(talk.rounds): \(talk.steps.count) steps planned")
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
    static let workingChip = "working"
    static let nothingRan = "None of it could run. Nothing was changed."
    static let workingLine = "Working…"
    static let turnOff = "Turn Off"
    static let turnOn = "Turn On"
    static let delete = "Delete"
    static let deleteTooltip = "Delete this change"
    static let stoppedSentence = "Stopped. Nothing was changed."
    static let noDocumentSentence = "Open a picture or video first."
    static func stepFailed(_ n: Int) -> String { "Step \(n) failed. Nothing was changed." }
    /// A drawing that still did not read after being drawn again.
    static let couldNotDraw = "I couldn't make a clear drawing of that. Nothing was changed."
    static let helpLine = "Each request is one row. Its switch turns the change off and on, and one Command Z takes back the latest."
}

import Foundation
import Observation
import PhotonzCore

/// Ask in one editor window (`docs/design/ask.md`): what was asked, the plan
/// the model on this Mac wrote for it, and running that plan.
///
/// Planning only looks: the read-only tools run, every editing call is written
/// into the plan. Run plan runs the steps through the same tools the MCP
/// server offers, inside one undo step, so one Command Z takes the whole batch
/// back. A step that fails takes back what already ran, so a bad plan leaves
/// the document as it was.
@MainActor
@Observable
final class AskSession {

    enum Phase: Equatable {
        case idle
        case planning
        case planned
        case running
        case ran
        /// The model wrote no plan, or Ask could not reach it: one sentence why.
        case stopped(String)

        /// The phase's name, as a walk waits on it.
        var name: String {
            switch self {
            case .idle: "idle"
            case .planning: "planning"
            case .planned: "planned"
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
    /// What was last asked, shown over its plan.
    private(set) var asked = ""
    private(set) var plan: AskPlan?
    /// How many of the plan's steps have run.
    private(set) var stepsRun = 0
    /// Whether the composer is up over the canvas.
    var isComposerShown = false
    /// Once this window has asked, the panel keeps its Agent group.
    private(set) var hasAsked = false
    /// Bumped to ask the panel to open the Agent group and bring it into view.
    private(set) var revealPass = 0
    /// How long the last plan took, from Ask to the plan on screen.
    private(set) var lastPlanSeconds: Double?

    @ObservationIgnored private var work: Task<Void, Never>?
    /// What the last plan did, a line a turn and a line a look, for a walk
    /// and for anybody finding out why a plan went the way it did.
    @ObservationIgnored private(set) var trace: [String] = []

    var isBusy: Bool { phase == .planning || phase == .running }

    /// The short state the Agent group's header carries.
    var chip: String? {
        switch phase {
        case .idle: nil
        case .planning: AskCopy.planningChip
        case .planned: AskCopy.stepsChip(plan?.steps.count ?? 0)
        case .running: AskCopy.runningChip
        case .ran: AskCopy.ranChip(stepsRun - skipped.count, of: stepsRun)
        case .stopped: nil
        }
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
        revealPass &+= 1
        let started = Date()
        trace = []
        work = Task { [weak self, weak editor] in
            guard let editor else { return }
            let outcome = await Self.plan(words, in: editor) { self?.trace.append($0) }
            guard let self, !Task.isCancelled else { return }
            lastPlanSeconds = Date().timeIntervalSince(started)
            switch outcome {
            case .success(let plan):
                self.plan = plan
                phase = .planned
            case .failure(let trouble):
                phase = .stopped(trouble.sentence)
            }
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

    /// Runs the plan as one undo step.
    func runPlan(in editor: EditorState) {
        guard phase == .planned, let plan, let document = editor.agentID else { return }
        phase = .running
        stepsRun = 0
        skipped = [:]
        work = Task { [weak self, weak editor] in
            guard let editor else { return }
            var failure: String?
            var landed = 0
            await editor.asOneUndoStepAwaiting {
                var made: [Int: String] = [:]
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
                            landed += 1
                            if let id = AskStep.madeID(fromAnswer: text) { made[number] = id }
                        }
                    }
                    if let refusal {
                        // Passed over, unless a later step counts on it.
                        if plan.isNamedLater(number) {
                            failure = AskCopy.stepFailed(number)
                            self?.skipped[number] = refusal
                            return
                        }
                        self?.skipped[number] = refusal
                    }
                    self?.stepsRun = number
                }
            }
            guard let self else { return }
            if let failure {
                // What ran is one step in the history: take it back, so a
                // plan that went wrong half way leaves nothing half done.
                if landed > 0 { editor.undo() }
                stepsRun = 0
                phase = .stopped(failure)
            } else if landed == 0 {
                phase = .stopped(AskCopy.nothingRan)
            } else {
                phase = .ran
            }
        }
    }

    /// The model's turns, until it stops calling tools.
    private static func plan(_ words: String, in editor: EditorState,
                             note: (String) -> Void) async -> Result<AskPlan, AskLocalModel.Trouble> {
        let began = Date()
        func at() -> String { String(format: "%.1fs", Date().timeIntervalSince(began)) }
        let model: String
        switch await AskLocalModel.model() {
        case .success(let found): model = found
        case .failure(let trouble): return .failure(trouble)
        }
        guard let document = editor.agentID else { return .failure(.said(AskCopy.noDocumentSentence)) }
        note("\(at()) model \(model), reading \(document)")
        let read = await AgentWork.run(.readDocument(document: document, layer: nil))
        note("\(at()) read \(Self.text(of: read).count) characters")
        // The Library up front: "on brand" is its components and styles.
        let components = await AgentWork.run(.listComponents(document: document))
        let styles = await AgentWork.run(.listStyles(document: document))
        // On a video, the title styles add_title takes by name.
        let titles = editor.documentHasTime ? await AgentWork.run(.listTitles(document: document)) : nil
        var talk = AskConversation(request: words, documentRead: Self.text(of: read),
                                   components: components.isError ? "" : Self.text(of: components),
                                   styles: styles.isError ? "" : Self.text(of: styles),
                                   titles: titles.map { $0.isError ? "" : Self.text(of: $0) } ?? "")
        while talk.rounds < AskConversation.mostRounds {
            let reply: AgentJSON
            do {
                note("\(at()) asking the model")
                reply = try await AskLocalModel.chat(talk.chatBody(model: model))
                note("\(at()) answered: \(reply["message"]?.encodedString().prefix(300) ?? "")")
            } catch let trouble as AskLocalModel.Trouble {
                return .failure(trouble)
            } catch {
                return .failure(.said(AskCopy.stoppedSentence))
            }
            if Task.isCancelled { return .failure(.said(AskCopy.stoppedSentence)) }
            let outcome = talk.take(reply)
            note("\(at()) turn \(talk.rounds): \(talk.steps.count) steps planned")
            switch outcome {
            case .planned(let plan):
                return .success(plan)
            case .cannot(let sentence):
                return .failure(.said(sentence))
            case .again(let looks):
                for look in looks {
                    note("\(at()) look \(look.tool) \(look.arguments.encodedString().prefix(120))")
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
    static let planHeader = "Plan"
    static let runPlan = "Run Plan"
    static let stop = "Stop"
    static let planningChip = "planning"
    static let runningChip = "running"
    static func stepsChip(_ n: Int) -> String { n == 1 ? "1 step" : "\(n) steps" }
    static func ranChip(_ n: Int, of all: Int) -> String {
        n == all ? (n == 1 ? "ran 1 step" : "ran \(n) steps") : "ran \(n) of \(all)"
    }
    static let nothingRan = "None of the plan could run. Nothing was changed."
    static let skippedTip = "Passed over: it would have changed nothing."
    static let planningLine = "Planning…"
    static let stoppedSentence = "Stopped. Nothing was changed."
    static let noDocumentSentence = "Open a picture or video first."
    static func stepFailed(_ n: Int) -> String { "Step \(n) failed. Nothing was changed." }
    static let helpLine = "You read the plan before anything happens. The whole run undoes with one Command Z."
}

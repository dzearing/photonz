import AppKit
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
/// one row of history in `changes`; undo is how a request is taken back.
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
    /// The card a row of history shows while the pointer rests on it.
    let card = AskHistoryHover()
    /// Clear History is waiting for its yes, at the top of the Agent group.
    private(set) var isConfirmingClear = false
    /// What `/` lists for the words in the field.
    private(set) var commands = AskCommandList.Listing()
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
    /// What the last request did not make, in one short line (`AskPlanRun`).
    /// The panel shows it under the row; the conversation answers with it.
    private(set) var leftOut: String?

    /// What the request at work is doing now, set by the pipeline as each
    /// stage starts (`AskStage`): the one live line under it in the panel.
    private(set) var stage: AskStage = .starting
    /// When the line last changed, so a long stage can say how long.
    private(set) var stageSince = Date()
    /// Every line the last request showed and when, from its send.
    @ObservationIgnored private(set) var stageLog = AskStageLog()
    @ObservationIgnored private var requestStarted = Date()

    /// The line as shown: a model loading into memory says so over whatever
    /// stage is waiting on it.
    var liveStage: AskStage {
        if AskModelServer.shared.loading { return .gettingModelReady }
        if AskPictureServer.shared.loading { return .gettingPainterReady }
        return stage
    }

    /// A stage starts. The same line again changes nothing, so its clock
    /// keeps running.
    private func enter(_ next: AskStage) {
        let now = Date()
        stageLog.enter(next, at: now.timeIntervalSince(requestStarted))
        guard next.line != stage.line else {
            stage = next
            return
        }
        stage = next
        stageSince = now
    }

    @ObservationIgnored private var work: Task<Void, Never>?
    /// What the last plan did, a line a turn and a line a look, for a walk
    /// and for anybody finding out why a plan went the way it did.
    @ObservationIgnored private(set) var trace: [String] = []
    /// Where each drawing of the last run came from (stored, template or
    /// drawn), so the eval can count lookups.
    @ObservationIgnored private(set) var lastSources: [AskDrawingSource] = []
    /// The model the last request ran on.
    @ObservationIgnored private(set) var lastModel: String?
    /// The web page the request in hand names, as the reader read it
    /// (`AskWebReader`), and every address the last request loaded: the
    /// eval's network check reads them.
    @ObservationIgnored private var webRead: AskWebReader.Read?
    /// What the reader found for a request that asked to look something up
    /// (`AskLookup`), checked, or nil.
    @ObservationIgnored private var lookedUp: AskLookup.Found?
    @ObservationIgnored private(set) var webRequests: [String] = []
    /// Where each voted row's case was saved, so taking the vote back takes
    /// the case away too.
    @ObservationIgnored private var savedVotes: [UUID: URL] = [:]

    /// A request is being worked on: a send now waits in `line`.
    var isBusy: Bool { current != nil }

    /// The short state the Agent group's header carries: working while the
    /// live request is showing, else how many rows it holds. Read off the
    /// phase rather than `isBusy`, which a request stopped during a model
    /// load keeps for as long as that load takes, with no live row to show
    /// for it (`ask-live-request-at-the-top-walk`, 2026-11-04).
    var chip: String? {
        phase == .planning || phase == .running
            ? AskCopy.workingChip : DockGroupHeader.countChip(changes.rows.count)
    }

    func openComposer() {
        isComposerShown = true
        AskModelServer.shared.warm()
    }

    func closeComposer() {
        isComposerShown = false
    }

    // MARK: Commands

    /// The field is a command search rather than a request.
    var isListingCommands: Bool { AskCommandList.query(in: draft) != nil }

    /// Reads the field again: the list follows every word typed.
    func refreshCommands(in editor: EditorState) {
        guard let query = AskCommandList.query(in: draft) else {
            commands = AskCommandList.Listing()
            return
        }
        commands = AskCommandList.matching(query) { editor.canRun($0.call) }
    }

    /// The arrow keys, and the pointer over a row.
    func moveCommandPick(by step: Int) { commands = commands.moved(by: step) }
    func pickCommand(at index: Int) { commands = commands.highlighting(index) }

    /// Whether Return in the field has anything to do.
    var canSubmit: Bool {
        if isListingCommands { return commands.picked != nil }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Return and the send button, in every field Ask has: the picked
    /// command when the field is listing them, else the request.
    func submit(in editor: EditorState) {
        if isListingCommands {
            if let picked = commands.picked { runCommand(picked, in: editor) }
        } else {
            ask(in: editor)
        }
    }

    /// Runs a listed command as its menu row does: one undo step, through
    /// the same call. The composer goes so the picture is not dimmed under
    /// the result and a sheet the command opens has nothing over it. What it
    /// changed gets a row beside the requests.
    func runCommand(_ entry: AskCommandEntry, in editor: EditorState) {
        guard editor.canRun(entry.call) else { return }
        draft = ""
        commands = AskCommandList.Listing()
        isComposerShown = false
        let before = editor.document
        editor.run(entry.call)
        guard let before, let after = editor.document else { return }
        if changes.record(asked: AskCopy.commandAsked(entry), sentence: entry.title,
                          before: before, after: after) != nil {
            hasAsked = true
        }
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
        guard !words.isEmpty, !isListingCommands else { return }
        refusal = nil
        // No model on this Mac yet: the setup dialog, and these words once it is done.
        if AskSetup.needed {
            needsSetup { [weak self, weak editor] in
                guard let self, let editor else { return }
                if self.draft.isEmpty { self.draft = words }
                self.ask(in: editor)
            }
            return
        }
        if editor.document == nil {
            switch AskFromNothing.start(words, picked: BlankCanvas.defaultPreset.size) {
            case nil: return
            case .video?:
                refusal = AskFromNothing.videoSentence
                return
            case .needsSomethingOpen?:
                refusal = AskFromNothing.nothingOpenSentence
                return
            case .picture(let size, let icon)?:
                editor.newBlankCanvas(size: size, asIcon: icon && Experiments.shared.iconFramesEnabled)
                guard editor.document != nil else { return }
            }
        }
        draft = ""
        send(words, in: editor)
    }

    // MARK: Setting up

    /// The setup dialog is up (`AskSetupSheet`).
    var isSetupShown = false
    /// What was asked with no model on the Mac, run once the set is down.
    @ObservationIgnored private var waitingForSetup: (@MainActor () -> Void)?
    @ObservationIgnored private var setupWatch: Task<Void, Never>?

    /// Opens the setup dialog; `then` runs once the set it offers is down.
    func needsSetup(then: @escaping @MainActor () -> Void) {
        waitingForSetup = then
        isSetupShown = true
    }

    /// Not Now: nothing downloads, and the words stay in their field.
    func cancelSetup() {
        waitingForSetup = nil
        isSetupShown = false
    }

    /// Hide while the set downloads: it carries on, and so does the request.
    /// With nothing downloading (Other Models…) the request is let go.
    func hideSetup() {
        isSetupShown = false
        if !AskSetup.downloading { waitingForSetup = nil }
    }

    /// Stop: the downloads end, and the words stay in their field.
    func stopSetup() {
        setupWatch?.cancel()
        setupWatch = nil
        AskModelDownload.shared.stop()
        AskModelDownload.pictures.stop()
        cancelSetup()
    }

    /// Download: the set starts down, and the request runs when it is all
    /// there. A chat model that did not come down puts the dialog back with why.
    func startSetup(_ plan: AskSetupPlan) {
        if let chat = plan.chat { AskModelDownload.shared.start(chat) }
        if plan.picture { AskPictureServer.download() }
        setupWatch?.cancel()
        setupWatch = Task { [weak self] in
            while AskSetup.downloading {
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { return }
            }
            guard let self, !Task.isCancelled else { return }
            setupWatch = nil
            if AskSetup.needed {
                isSetupShown = true
                return
            }
            isSetupShown = false
            let then = waitingForSetup
            waitingForSetup = nil
            then?()
        }
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
        // What "this" means is settled now, however long the request waits.
        let picked = editor.pickedForAsk
        if isBusy {
            line.add(words, picked: picked)
            return
        }
        start(words, picked: picked, in: editor)
    }

    private func start(_ typed: String, picked: [UUID], in editor: EditorState) {
        // "As a photo" makes the last request again that way.
        let words = AgentPictureKind.remade(typed, after: changes.rows.first?.asked) ?? typed
        said = nil
        leftOut = nil
        asked = words
        current = words
        plan = nil
        stepsRun = 0
        phase = .planning
        let started = Date()
        requestStarted = started
        stageLog = AskStageLog()
        stage = .starting
        stageSince = started
        stageLog.enter(.starting, at: 0)
        // A model loading into memory is shown over the stage waiting on it
        // (`liveStage`); the log hears of it here, a few times a second.
        Task { [weak self] in
            while let session = self, session.isBusy, session.requestStarted == started {
                session.stageLog.enter(session.liveStage, at: Date().timeIntervalSince(started))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        trace = []
        lastSources = []
        work = Task { [weak self, weak editor] in
            if let editor {
                await self?.carryOut(words, picked: picked, in: editor, started: started)
            }
            self?.finished(in: editor)
        }
    }

    /// A request's work has ended, however it ended: the next in line starts,
    /// on the document as this one left it.
    private func finished(in editor: EditorState?) {
        stageLog.end(at: Date().timeIntervalSince(requestStarted))
        if !stageLog.entries.isEmpty {
            trace.append(String(format: "stages: longest without news %.1fs", stageLog.longestGap))
        }
        current = nil
        work = nil
        guard let editor, let next = line.next() else { return }
        start(next.words, picked: next.picked, in: editor)
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
    private func carryOut(_ words: String, picked: [UUID], in editor: EditorState, started: Date) async {
        let began = Date()
        let note: (String) -> Void = { [weak self] line in
            self?.trace.append(String(format: "%.1fs ", Date().timeIntervalSince(began)) + line)
        }
        let say: @MainActor (AskStage) -> Void = { [weak self] stage in self?.enter(stage) }
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
        // An address the person typed is opened by app code, never by the
        // model (`AskWeb`): what the model sees is the page's picture and a
        // checked description.
        webRead = nil
        lookedUp = nil
        webRequests = []
        if AskWeb.address(in: words) == nil, AskLookup.wants(in: words) {
            // Looked up by a reader that never sees the document (`AskLookup`).
            guard AskWeb.allowed(in: .standard) else {
                note("web: kept off the web in Settings")
                phase = .stopped(AskWeb.offTheWebSentence)
                return
            }
            guard let service = AskSearch.service else {
                note("web: searching is not set up")
                phase = .stopped(AskLookup.notSetUpSentence)
                return
            }
            let found = await Self.lookUp(words, model: model, service: service, note: note, say: say) { [weak self] in
                self?.webRequests.append($0)
            }
            guard !Task.isCancelled else { return }
            guard let found else {
                phase = .stopped(AskLookup.nothingFoundSentence)
                return
            }
            lookedUp = found
        }
        if let address = AskWeb.address(in: words) {
            let host = AskWeb.shortHost(address)
            guard AskWeb.allowed(in: .standard) else {
                note("web: kept off the web in Settings")
                phase = .stopped(AskWeb.offTheWebSentence)
                return
            }
            say(.openingPage(host))
            let size = Self.pageSize(for: editor.document?.canvasSize)
            note("web: opening \(address.absoluteString) at \(Int(size.width)) x \(Int(size.height))")
            let read = await AskWebReader.read(address, size: size)
            guard !Task.isCancelled else { return }
            switch read {
            case .success(let read):
                webRead = read
                webRequests = read.requests
                note("web: read \(read.page.parts.count) parts, \(read.pictures.count) pictures, \(read.requests.count) requests")
                for request in read.requests { note("web request: \(request)") }
            case .failure:
                note("web: could not open \(address.absoluteString)")
                phase = .stopped(AskWeb.couldNotOpen(host))
                return
            }
        }
        let opened = await Self.conversation(words, picked: picked, in: editor, model: model, memory: memory, web: webRead,
                                             lookedUp: lookedUp, note: note, say: say)
        guard !Task.isCancelled else { return }
        guard var talk = opened else {
            phase = .stopped(AskCopy.noDocumentSentence)
            return
        }
        var revisions = 0
        // Where this request lands: the window it was asked in, or the new
        // picture an icon opened (`AgentDrawingPlacement.iconPlace`). Every
        // try lands there and is taken back there, so the person's own
        // picture is never touched and a second try opens no second window.
        var canvas = editor
        var openedForIcon = false
        // The icon that landed did not read to the model that looked at it.
        var unclear = false
        // A request that ends with nothing to show closes what it opened.
        func closeOpened() {
            if openedForIcon { canvas.hostWindow?.close() }
        }
        // The plans the first try's drawings were checked against, held for
        // every try after it, and the closest try so far, kept to land if a
        // later one comes out worse.
        var carried: [[String]]?
        var closest: (attempt: AskDrawingCheck.Attempt, after: PhotonzDocument, ran: Ran, plan: AskPlan)?
        // A try again says why for as long as it plans the next try.
        var retrying: AskStage?
        // How many times a moving icon's frames were looked at (`AskMotionLook`).
        var motionLooks = 0
        while true {
            let outcome = await Self.plan(&talk, model: model, in: editor, note: note, say: say, first: retrying)
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
            } else if !AskIcon.isIn(plan) {
                plan = await Self.withDrawingPlans(plan, asked: words, model: model, note: note, say: say)
            }
            guard !Task.isCancelled else { return }
            carried = carried ?? AskDrawingCheck.drawings(in: plan).map(\.plan)
            self.plan = plan
            if !openedForIcon, let side = AskIcon.side(of: plan), !AgentDrawingWork.isBlank(editor) {
                do {
                    canvas = try await AgentDrawingWork.openPicture(CGSize(width: side, height: side))
                    openedForIcon = true
                    note("icon: opened a new picture \(Int(side)) square")
                } catch {
                    phase = .stopped(AskCopy.nothingRan)
                    return
                }
            }
            guard let ran = await run(plan, in: canvas) else {
                closeOpened()
                return
            }
            // What landed is picked and the panel fills with its sections:
            // the Agent group comes back into view, so its line can still be
            // read while the drawing is checked or drawn again.
            revealRows()
            // A moving icon is looked at across its lap before it lands, and
            // what the look did not see goes back to the plan once.
            if talk.movesIcon, !AskLocalModel.answersAreScripted,
               AskMotionLook.looks(after: Date().timeIntervalSince(started), looked: motionLooks) {
                motionLooks += 1
                let seen = await lookAtMotion(in: canvas, asked: words, model: model, note: note)
                if Task.isCancelled {
                    canvas.undo()
                    closeOpened()
                    stepsRun = 0
                    phase = .stopped(AskCopy.stoppedSentence)
                    return
                }
                if let seen {
                    canvas.undo()
                    talk.reviseMotion(seen: seen)
                    retrying = .fixingMotion
                    enter(.fixingMotion)
                    phase = .planning
                    continue
                }
            }
            let miss = talk.landsAsDrawn ? nil : await look(at: plan, made: ran.made, in: canvas, model: model, note: note, say: say)
            if Task.isCancelled {
                // Stopped while it looked at what it drew: what ran comes
                // back off, so a stop leaves the document as it was.
                canvas.undo()
                closeOpened()
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
                enter(.keepingClosest)
                canvas.undo()
                canvas.perform { $0 = held.after }
                landed = held.ran
                lastSources = held.ran.sources
                self.plan = held.plan
                note("keeping an earlier drawing: it showed all but \(held.attempt.missed) of its plan")
            } else if let miss, !miss.unmet.isEmpty, revisions >= AskDrawingCheck.mostRevisions {
                // It reads as the thing but still misses part of its plan
                // after the last try: it stays, the closest Ask came.
                note("keeping the last drawing: still not shown: \(miss.unmet.joined(separator: "; "))")
            } else if let miss, revisions >= AskDrawingCheck.mostRevisions, AskIcon.asked(in: words) {
                // A plain outline, shown with no hint of what it is, is the
                // hardest thing to name: a balloon was seen as a ship's wheel
                // and a light bulb (the eval, 2026-11-04). An icon a person
                // can judge beats nothing, so it stays, and Ask says so.
                note("keeping the last icon: still seen as \(miss.seen)")
                unclear = true
            } else if let miss {
                if AskDrawingCheck.isCloser(attempt, than: closest?.attempt), let after = canvas.document {
                    closest = (attempt, after, ran, plan)
                }
                // What was drawn does not read as what was asked, or does not
                // show what its plan said: it comes back off, and is drawn
                // again or owned up to.
                canvas.undo()
                guard revisions < AskDrawingCheck.mostRevisions, !Task.isCancelled else {
                    closeOpened()
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
                retrying = .tryingAgain(miss.unmet.first.map { .missed($0) } ?? .seenAs(miss.seen))
                enter(retrying ?? .thinking(turn: 2))
                phase = .planning
                continue
            }
            if openedForIcon, let person = editor.document, let after = canvas.document {
                // The person's picture did not change: the row says where it went.
                let name = after.layers.first(where: \.isFrame)?.name ?? "Icon"
                changes.recordElsewhere(asked: words, sentence: AskChangeWords.madeNewIcon(name), document: person,
                                        sources: landed.sources, leftOut: landed.leftOut,
                                        understood: AskUnderstanding.lines(summary: self.plan?.summary ?? "", steps: landed.landed))
            } else if let after = editor.document {
                let made = AskChangeWords.sentence(landed.landed, asked: words, before: landed.before, after: after,
                                                   madeAll: landed.leftOut == nil)
                let components = landed.landed.filter { $0.tool == AskWeb.pageTool && $0.arguments["component"] != nil }.count
                // A request that looked something up says where it looked.
                let said = webRead.map { AskWeb.sentence(host: $0.page.host, components: components) }
                    ?? lookedUp.map { AskLookup.sentence(hosts: $0.hosts, made: made,
                                                         components: landed.landed.filter { $0.tool == "add_component" }.count) }
                    ?? made
                changes.record(asked: words, sentence: said,
                               before: landed.before, after: after, sources: landed.sources, leftOut: landed.leftOut,
                               understood: AskUnderstanding.lines(summary: self.plan?.summary ?? "", steps: landed.landed))
            }
            lastPlanSeconds = Date().timeIntervalSince(started)
            note("done")
            let sayings = [talk.note, landed.layoutSentence, unclear ? AskCopy.iconMayNotRead : nil,
                           Self.motionNote(of: landed, in: canvas)].compactMap { $0 }
            said = sayings.isEmpty ? nil : sayings.joined(separator: " ")
            leftOut = landed.leftOut
            if let line = landed.leftOut { note("left out: \(line)") }
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

    /// Steps left out, by number, with the reason: a step the app refused
    /// changed nothing, so the rest ran without it and what counted on it.
    private(set) var skipped: [Int: String] = [:]

    struct Ran {
        let before: PhotonzDocument
        let landed: [AskStep]
        /// What each step made, by step number.
        let made: [Int: String]
        let sources: [AskDrawingSource]
        /// What the look over the layout could not mend, in one sentence.
        let layoutSentence: String?
        /// What this change did not make, nil when it made it all.
        let leftOut: String?
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
        var ledger = AskPlanRun(plan: plan)
        var sources: [AskDrawingSource] = []
        var layoutSentence: String?
        let drawings = plan.steps.filter { $0.tool == "add_drawing" || $0.tool == "add_photo" }.count
        var drawn = 0
        await editor.asOneUndoStepAwaiting {
            for (index, step) in plan.steps.enumerated() {
                let number = index + 1
                if Task.isCancelled { failure = AskCopy.stoppedSentence; return }
                let stages = Self.stages(of: step, number: number, of: plan.steps.count,
                                         part: &drawn, drawings: drawings)
                // Counting on a step that was left out, it cannot run either.
                if ledger.passOver(number) {
                    skipped[number] = ledger.leftOut.last?.why
                    stepsRun = number
                    continue
                }
                enter(stages.working)
                var refusal: String?
                if step.tool == AskWeb.pageTool {
                    switch Self.landPage(step, from: webRead, in: editor) {
                    case .success(let id):
                        ledger.land(number, id: id)
                    case .failure(let refused):
                        refusal = refused.message
                    }
                    if let refusal {
                        skipped[number] = refusal
                        ledger.leaveOut(number, because: refusal)
                    }
                    stepsRun = number
                    continue
                }
                let readied = editor.document.map { AskMotion.landing(step, in: $0, plan: plan.steps, made: ledger.made) } ?? .success(step)
                switch readied.flatMap({ $0.request(document: document, made: ledger.made) }) {
                case .failure(let refused):
                    refusal = refused.message
                case .success(let request):
                    let heard: @MainActor @Sendable (AskPictureModel.Stage) -> Void = { [weak self] said in
                        switch said {
                        case .loading: self?.enter(.gettingPainterReady)
                        case .said(.tracing): self?.enter(stages.tracing ?? stages.working)
                        case .said(let painter):
                            if case .painting(true, _, _) = painter {
                                self?.enter(.tryingAgain(.offTheEdge))
                            } else {
                                self?.enter(stages.working.at(painter.percent))
                            }
                        }
                    }
                    let answer = await AskPictureModel.$report.withValue(heard) { await AgentWork.run(request) }
                    let text = Self.text(of: answer)
                    if answer.isError {
                        refusal = text
                    } else {
                        ledger.land(number, id: AskStep.madeID(fromAnswer: text))
                        if let source = AskDrawingSource.of(tool: step.tool, answer: text) { sources.append(source) }
                    }
                }
                if let refusal {
                    skipped[number] = refusal
                    ledger.leaveOut(number, because: refusal)
                }
                stepsRun = number
            }
            // Ask looks over the layout it made before it hands back, and
            // mends what it can in this same undo step (`AskLayoutCheck`).
            guard failure == nil, !ledger.landed.isEmpty, let now = editor.document else { return }
            let review = AskLayoutCheck.review(now, before: before, pictureColour: editor.store.flatColourHex(for:))
            for line in review.notes { note("look: " + line) }
            if !review.fixes.isEmpty { editor.perform { AskLayoutCheck.apply(review, to: &$0) } }
            layoutSentence = review.sentence
        }
        if let failure {
            // What ran is one step in the history: take it back, so a plan
            // stopped half way leaves nothing half done.
            if !ledger.landed.isEmpty { editor.undo() }
            stepsRun = 0
            phase = .stopped(failure)
            return nil
        }
        guard !ledger.landed.isEmpty else {
            phase = .stopped(AskCopy.nothingRan)
            return nil
        }
        lastSources = sources
        return Ran(before: before, landed: ledger.landed, made: ledger.made, sources: sources,
                   layoutSentence: layoutSentence, leftOut: ledger.sentence)
    }

    /// What a plan that keyed something says about it (`AskChangeWords.motionNote`).
    private static func motionNote(of ran: Ran, in editor: EditorState) -> String? {
        guard ran.landed.contains(where: { AskTools.keyDoing.contains($0.tool) }), let document = editor.document,
              !document.hasTime, let lap = document.keyLap else { return nil }
        let animation = CompositeCopy.svgAnimation(for: document, motionOn: Experiments.shared.animatedSVGExportEnabled)
        let written = SVGExporter.data(document, store: editor.store, renderer: DocumentRenderer(), animation: animation, background: .drop)
        return AskChangeWords.motionNote(lapSeconds: Double(document.motionCycleLengthMS) / 1000, loops: lap.repeats,
                                         notMoving: Array(Set(written?.unmoved.map(\.layerName) ?? [])).sorted())
    }

    /// What a step's line says while it runs, and once its painting is
    /// being traced. `part` counts the drawings so far.
    private static func stages(of step: AskStep, number: Int, of steps: Int, part: inout Int,
                               drawings: Int) -> (working: AskStage, tracing: AskStage?) {
        let subject = step.arguments["subject"]?.stringValue ?? ""
        switch step.tool {
        case "add_drawing" where !subject.isEmpty:
            part += 1
            let painted = AskPictureModel.isReady() && step.arguments["svg"] == nil
            return (painted ? .painting(subject: subject, part: part, of: drawings)
                            : .drawing(subject: subject, part: part, of: drawings),
                    .tracing(subject: subject, part: part, of: drawings))
        case "add_photo" where !subject.isEmpty:
            part += 1
            return (.photo(subject: subject, part: part, of: drawings), nil)
        default:
            return (.making(step: number, of: steps), nil)
        }
    }

    /// What the planning model sees wrong in frames of the moving icon that
    /// just landed, in its words, or nil when every beat reads (or it cannot
    /// see, or gave no answer): `AskMotionLook`.
    private func lookAtMotion(in editor: EditorState, asked words: String, model: String,
                              note: (String) -> Void) async -> String? {
        guard await AskLocalModel.sees(model) else {
            note("motion look skipped: \(model) cannot see")
            return nil
        }
        guard let lap = editor.document?.motionCycleLengthMS,
              let png = AgentWork.lapSheet(of: editor, times: AskMotionLook.times(lapMS: lap),
                                           columns: AskMotionLook.columns, cellSide: AskMotionLook.cellSide) else { return nil }
        enter(.checkingMotion)
        let answer = try? await AskLocalModel.chat(AskMotionLook.body(model: model, png: png, request: words))
        let said = answer?["message"]?["content"]?.stringValue ?? ""
        let seen = AskMotionLook.critique(fromAnswer: said)
        note("motion look: \(seen.map { "sent back: \($0)" } ?? (said.isEmpty ? "no answer" : "all good"))")
        return seen
    }

    /// The first drawing the plan made that a model that can see does not
    /// take for what was asked, or that does not show a statement of its
    /// plan (`unmet`), or nil when each reads (or nothing on this Mac can
    /// see, or nothing was drawn).
    private func look(at plan: AskPlan, made: [Int: String], in editor: EditorState, model: String,
                      note: (String) -> Void, say: (AskStage) -> Void) async -> (subject: String, seen: String, unmet: [String])? {
        let drawings = AskDrawingCheck.drawings(in: plan)
        guard !drawings.isEmpty, let document = editor.agentID else { return nil }
        let installed = await AskLocalModel.installed() ?? []
        let ownEyes = await AskLocalModel.sees(model)
        guard let eyes = AskLocalModel.eyesOverride.flatMap({ installed.contains($0) ? $0 : nil })
                ?? AskModels.eyes(planner: model, plannerSees: ownEyes, installed: installed) else {
            note("look skipped: no model on this Mac can see")
            return nil
        }
        for (index, drawing) in drawings.enumerated() {
            guard let layer = made[drawing.step] else { continue }
            say(.checking(subject: drawing.subject, part: index + 1, of: drawings.count))
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
                AskDrawingCheck.judgeBody(model: model, subject: drawing.subject, seen: seen, icon: AskIcon.isIn(plan)))["message"]?["content"]?.stringValue {
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
                                         note: (String) -> Void, say: (AskStage) -> Void) async -> AskPlan {
        var plan = plan
        let all = AskDrawingCheck.drawings(in: plan)
        func part(_ step: Int) -> (Int, Int) { ((all.firstIndex { $0.step == step } ?? 0) + 1, all.count) }
        for drawing in AskDrawingCheck.unplanned(in: plan) {
            let (n, of) = part(drawing.step)
            say(.planningDrawing(subject: drawing.subject, part: n, of: of))
            guard !Task.isCancelled,
                  let answer = try? await AskLocalModel.chat(AskDrawingCheck.planningBody(model: model, subject: drawing.subject))["message"]?["content"]?
                      .stringValue else { continue }
            let statements = AskDrawingCheck.statements(fromAnswer: answer)
            note("plan for \(drawing.subject): " + (statements.isEmpty ? "none" : statements.joined(separator: "; ")))
            plan = plan.settingDrawingPlan(step: drawing.step, to: statements)
        }
        for drawing in AskDrawingCheck.drawings(in: plan) where !drawing.plan.isEmpty {
            let (n, of) = part(drawing.step)
            say(.planningDrawing(subject: drawing.subject, part: n, of: of))
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

    /// Clear History, from the Agent group's menu or Edit: the question goes
    /// up in the Agent group, wherever that was.
    func askToClearHistory(in editor: EditorState) {
        guard !changes.rows.isEmpty else { return }
        isConfirmingClear = true
        editor.bringAgentAreaForward()
        isRevealPending = true
        revealRows()
    }

    func cancelClearHistory() {
        isConfirmingClear = false
    }

    /// The list goes, and with it what Ask remembers of the talk. Nothing on
    /// the canvas changes and undo still steps through it all. A request at
    /// work carries on, and gets a row when it lands.
    func clearHistory() {
        isConfirmingClear = false
        changes.clear()
        card.forget()
        savedVotes = [:]
        guard !isBusy else { return }
        said = nil
        leftOut = nil
        phase = .idle
    }

    /// Picks on the canvas what a row's change made, the mock's Last change
    /// click: the selection jumps there so the person can keep going by hand.
    func pickChange(_ id: UUID, in editor: EditorState) {
        guard let row = changes.row(id), row.isOn, let document = editor.document else { return }
        let ids = row.change.madeLayerIDs(in: document)
        guard !ids.isEmpty else { return }
        editor.selectLayers(Set(ids))
    }

    /// A change landing picks a layer or drops one, and the panel fills with
    /// that layer's sections or loses them, a frame or two later: the Agent
    /// group is brought back into view now and once more when that settles.
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
    private static func conversation(_ words: String, picked: [UUID], in editor: EditorState, model: String, memory: String = "",
                                     web: AskWebReader.Read? = nil, lookedUp: AskLookup.Found? = nil,
                                     note: (String) -> Void, say: (AskStage) -> Void) async -> AskConversation? {
        guard let document = editor.agentID else { return nil }
        say(.reading(video: editor.documentHasTime))
        note("model \(model), reading \(document)")
        let read = await AgentWork.run(.readDocument(document: document, layer: nil, picked: picked))
        note("read \(Self.text(of: read).count) characters")
        let components = await AgentWork.run(.listComponents(document: document))
        let styles = await AgentWork.run(.listStyles(document: document))
        // On a video, the title styles add_title takes by name.
        let titles = editor.documentHasTime ? await AgentWork.run(.listTitles(document: document)) : nil
        let paints = AskPictureModel.isReady()
        if paints { note("drawings painted by the picture model") }
        // Only when there is something of Ask's or the person's to look at:
        // a blank canvas or a lone screenshot plans as it always did.
        let looks = web == nil && (!memory.isEmpty || (editor.document?.layers.count ?? 0) > 1)
        if looks, !editor.documentHasTime { say(.lookingAtCanvas) }
        // With a web page, the picture the model sees is the page.
        let page: (png: Data, scale: Double)? = await AskLocalModel.sees(model) ? web.map { ($0.png, 1) } : nil
        let canvas = looks ? await Self.canvasPicture(of: document, in: editor, model: model) : page
        if let canvas { note("canvas picture, \(canvas.png.count / 1024) KB at \(Int(canvas.scale * 100))%") }
        let brushes = Experiments.shared.brushEnabled && !editor.documentHasTime
        // Something breaking is drawn whole and torn by a tool (`AskIconBreak`);
        // any other icon is designed in words before it is drawn when
        // something is happening to it (`AskIcon.designAsk`).
        var iconDesign: String?
        var iconBreak: AskIconBreak.Answer?
        // A picture made as an icon with nothing on it yet: something moving
        // asked of it is a moving icon, whatever the words call it.
        let blankIcon = web == nil && editor.document.map { $0.isIconCanvas && $0.layers.count <= 1 } == true
        let route = AskConversation.takesIconRoute(words, brushes: brushes, web: web != nil,
                                                   holdsIcon: AskIcon.holdsIcon(Self.text(of: read)), blankIcon: blankIcon)
        // An icon whose words name no motion may still tell one ("the lid
        // opens, trash is thrown in and it closes"): the model says whether
        // it moves before it is drawn still (`AskMotion.movesQuestion`).
        var toldMotion = false
        if !AskMotion.drawsMotion(words, blankIcon: blankIcon), route, !AskLocalModel.answersAreScripted {
            let answer = try? await AskLocalModel.chat(AskMotion.movesBody(model: model, request: words))
            toldMotion = (answer?["message"]?["content"]?.stringValue).map(AskMotion.moves(fromAnswer:)) ?? false
            note("icon: moves: \(toldMotion ? "yes" : "no")")
        }
        if toldMotion || AskMotion.drawsMotion(words, blankIcon: blankIcon), route,
           !AskLocalModel.answersAreScripted {
            let answer = try? await AskLocalModel.chat(AskMotion.designBody(model: model, request: words))
            iconDesign = (answer?["message"]?["content"]?.stringValue).flatMap(AskMotion.design(fromAnswer:))
            note("icon: motion design: \(iconDesign ?? "none")")
        } else if route, !AskLocalModel.answersAreScripted {
            let broken = try? await AskLocalModel.chat(AskIconBreak.questionBody(model: model, request: words))
            iconBreak = (broken?["message"]?["content"]?.stringValue).flatMap(AskIconBreak.answer(from:))
            note("icon: breaks: \(iconBreak.map { "\($0.kind.word): \($0.object)" } ?? "no")")
            if iconBreak == nil {
                let answer = try? await AskLocalModel.chat(AskIcon.designBody(model: model, request: words))
                iconDesign = (answer?["message"]?["content"]?.stringValue).flatMap(AskIcon.design(fromAnswer:))
                note("icon: design: \(iconDesign ?? "none")")
            }
        }
        return AskConversation(request: words, documentRead: Self.text(of: read),
                               components: components.isError ? "" : AskTools.withoutStarters(Self.text(of: components)),
                               library: components.isError ? "" : Self.text(of: components),
                               styles: styles.isError ? "" : Self.text(of: styles),
                               titles: titles.map { $0.isError ? "" : Self.text(of: $0) } ?? "",
                               paints: paints,
                               brushes: brushes,
                               memory: memory, canvas: canvas?.png, canvasScale: canvas?.scale ?? 1,
                               window: AskLocalModel.window, web: web?.page, lookedUp: lookedUp, iconDesign: iconDesign,
                               iconBreak: iconBreak, blankIcon: blankIcon, toldMotion: toldMotion)
    }

    /// The longest side of the canvas picture the planning model is shown:
    /// a canvas up to this size is shown a pixel a point, so a point the
    /// model reads off it is a canvas point.
    static let canvasPictureSide = 1024

    /// The canvas as it is now, for a planning model that sees, so "bluer"
    /// and "bigger" are judged against what is really there. Nil for a model
    /// that cannot see or a video.
    private static func canvasPicture(of document: String, in editor: EditorState,
                                      model: String) async -> (png: Data, scale: Double)? {
        guard !editor.documentHasTime, let size = editor.document?.canvasSize,
              await AskLocalModel.sees(model) else { return nil }
        let longest = max(size.width, size.height)
        let side = Int(min(CGFloat(canvasPictureSide), longest.rounded()))
        let picture = await AgentWork.run(.renderPicture(document: document, layer: nil, region: nil, maxSize: side))
        guard let png = picture.content.compactMap({ part -> Data? in
            if case .png(let data) = part { return data }
            return nil
        }).first else { return nil }
        return (onWhite(png), longest > 0 ? Double(side) / Double(longest) : 1)
    }

    /// The model's turns, until it stops calling tools.
    /// `first` is the line while the first turn is asked for, when it says
    /// more than thinking (a try again and why).
    private static func plan(_ talk: inout AskConversation, model: String, in editor: EditorState,
                             note: (String) -> Void, say: @escaping @MainActor (AskStage) -> Void,
                             first: AskStage? = nil) async -> Result<AskPlan, AskLocalModel.Trouble> {
        guard let document = editor.agentID else { return .failure(.said(AskCopy.noDocumentSentence)) }
        while talk.rounds < AskConversation.mostRounds {
            let reply: AgentJSON
            // Every request fits the window before it goes (`AskConversation.fittedMessages`):
            // one that still cannot is said plainly here, never sent for the server to refuse.
            guard talk.fits else {
                note("too big to send: about \(talk.estimatedTokens) tokens against \(talk.budget)")
                return .failure(.said(AskTrouble.tooMuchSentence))
            }
            let turn = talk.rounds + 1
            // A try again says why through every turn of its planning.
            let saying = first
            say(saying ?? .thinking(turn: turn))
            let expected = talk.estimatedTokens(of: talk.chatBody(model: model)["messages"]?.arrayValue ?? [])
            // While the model works, its server says how far it has read and
            // whether it is writing yet (a try again keeps saying why).
            let watch = saying == nil && AskLocalModel.runtime == .builtIn ? Task { @MainActor in
                // Not read for its first moment: while the server matches the
                // request against what it still holds from the last one, its
                // count is that one's (83% then 3%, seen on 2026-11-01).
                try? await Task.sleep(for: .milliseconds(2000))
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    if let progress = await AskModelServer.shared.progress(), !Task.isCancelled {
                        say(AskStage.thinking(turn: turn, at: progress, expected: expected))
                    }
                }
            } : nil
            defer { watch?.cancel() }
            do {
                note("asking the model (about \(expected) tokens of \(talk.window))")
                reply = try await AskLocalModel.chat(talk.chatBody(model: model))
                watch?.cancel()
                // Long enough to hold a whole component call, so a look the
                // planner let through can be rebuilt from the trace (a blue
                // Off toggle could not be, cut at 300, 2026-10-24), nor a
                // first answer of nine components (a Disabled field drawn
                // darker than its Default was past 3000, 2026-11-02).
                note("answered: \(reply["message"]?.encodedString().prefix(20000) ?? "")")
            } catch let trouble as AskLocalModel.Trouble {
                if case .server(let words) = trouble { note("the model's server said: \(words.prefix(300))") }
                if case .server(let words) = trouble, AskConversation.isUnreadableReply(words), !talk.steps.isEmpty {
                    if talk.askForTitle() {
                        note("unreadable reply after \(talk.steps.count) steps: asking for the sheet's title first")
                        continue
                    }
                    note("unreadable reply after \(talk.steps.count) steps: offering them")
                    return .success(talk.plan(summary: "", stoppedShort: true))
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
                    say(.lookingUp(tool: look.tool))
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
        if !talk.steps.isEmpty || talk.web != nil { return .success(talk.plan(summary: "", stoppedShort: true)) }
        return .failure(.said(AskConversation.noPlanSentence))
    }

    /// Looks the request up on the web (`AskLookup`), the reader's way: its
    /// first turn sees the person's words and nothing else and writes the
    /// searches; app code runs them and reads the first results' pages;
    /// its second turn reads all that and answers with a list, checked. The
    /// reader never sees the document, and every address loaded is handed to
    /// `loaded` for the trace and the eval's network check. Nil when nothing
    /// usable came back.
    private static func lookUp(_ words: String, model: String, service: (endpoint: URL, key: String),
                               note: (String) -> Void, say: (AskStage) -> Void,
                               loaded: (String) -> Void) async -> AskLookup.Found? {
        say(.searchingWeb)
        let asked = try? await AskLocalModel.chat(AskLookup.searchesBody(model: model, request: words))
        let searches = AskLookup.searches(fromAnswer: asked?["message"]?["content"]?.stringValue ?? "", request: words)
        note("lookup: searches \(searches)")
        var results: [AskLookup.Result] = []
        for query in searches {
            guard !Task.isCancelled else { return nil }
            switch await AskSearch.search(query, endpoint: service.endpoint, key: service.key) {
            case .success(let found):
                loaded(found.address)
                note("web request: \(found.address)")
                note("lookup: \(found.results.count) results for \(query)")
                for result in found.results where !results.contains(where: { $0.address == result.address }) { results.append(result) }
            case .failure:
                note("lookup: the search for \(query) failed")
            }
        }
        guard !results.isEmpty else { return nil }
        var pages: [(host: String, text: String)] = []
        for address in AskLookup.toRead(results) {
            guard !Task.isCancelled else { return nil }
            let host = AskWeb.shortHost(address)
            say(.openingPage(host))
            let read = await AskWebReader.text(address)
            for request in read.requests {
                loaded(request)
                note("web request: \(request)")
            }
            if let text = read.text {
                pages.append((host, text))
                note("lookup: read \(text.count) characters from \(host)")
            }
        }
        say(.readingWhatItFound)
        guard !Task.isCancelled,
              let answer = try? await AskLocalModel.chat(AskLookup.readingBody(model: model, request: words, results: results, pages: pages))["message"]?["content"]?.stringValue
        else { return nil }
        let hosts = pages.isEmpty ? results.prefix(1).map { AskWeb.shortHost($0.address) } : pages.map(\.host)
        let found = AskLookup.found(fromAnswer: answer, hosts: hosts)
        note("lookup: found \(found?.items.count ?? 0) things: \(found?.listing.prefix(1500) ?? answer.prefix(300))")
        return found
    }

    /// The size a page is read at: the canvas's, within what a page reads
    /// sensibly at, 1440 x 900 without a canvas.
    static func pageSize(for canvas: CGSize?) -> CGSize {
        guard let canvas, canvas.width > 0, canvas.height > 0 else { return CGSize(width: 1440, height: 900) }
        return CGSize(width: min(max(canvas.width, 640), 2560).rounded(), height: min(max(canvas.height, 400), 2400).rounded())
    }

    /// Lands an add_page_parts step: the parts it names, as the page drew
    /// them, one group (a component when the step names one). The canvas
    /// scale makes up for a page read at a size the canvas is not.
    private static func landPage(_ step: AskStep, from read: AskWebReader.Read?,
                                 in editor: EditorState) -> Result<String, AgentToolError> {
        guard let read else { return .failure(AgentToolError("There is no web page in this request.")) }
        guard let canvas = editor.document?.canvasSize else { return .failure(AgentToolError(AskCopy.noDocumentSentence)) }
        let ids = Set(step.arguments["parts"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        let parts = read.page.parts.filter { ids.contains($0.id) }
        guard !parts.isEmpty else { return .failure(AgentToolError("Those parts are not on the page.")) }
        var images: [String: ImageRef] = [:]
        for part in parts where part.kind == .image {
            if let picture = read.pictures[part.id] { images[part.id] = editor.store.register(picture) }
        }
        let component = step.arguments["component"]?.stringValue
        let name = component ?? step.arguments["name"]?.stringValue ?? read.page.host
        let scale = read.page.size.width > 0 ? canvas.width / read.page.size.width : 1
        var made: UUID?
        editor.perform { document in
            made = document.addWebParts(parts, of: read.page, name: name, component: component, images: images,
                                        font: Self.font(for:), measure: { content, width in
                                            TextRasterizer.naturalSize(content, maxWidth: width ?? .greatestFiniteMagnitude)
                                        }, scale: scale)
        }
        guard let made else { return .failure(AgentToolError("Photonz could not place those parts.")) }
        return .success(made.uuidString)
    }

    /// The family this Mac draws a page's font stack with: the first one it
    /// has, the system's own for a sans serif, nil (SF Pro) when none fits.
    static func font(for stack: [String]) -> String? {
        let families = NSFontManager.shared.availableFontFamilies
        let byLower = Dictionary(families.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        for name in stack {
            let lower = name.lowercased()
            if let found = byLower[lower] { return found }
            switch lower {
            case "sans-serif", "system-ui", "-apple-system", "blinkmacsystemfont", "ui-sans-serif": return nil
            case "serif", "ui-serif": return ["New York", "Times New Roman", "Georgia"].first { byLower[$0.lowercased()] != nil }
            case "monospace", "ui-monospace": return ["SF Mono", "Menlo", "Courier New"].first { byLower[$0.lowercased()] != nil }
            default: continue
            }
        }
        return nil
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
    static let composerPlaceholder = "Ask, or type / for a command"
    /// The mock's whole line, over the budget, so it is the field's tip.
    static let composerTip = "Ask for a change, or type / for a command"
    static let composerHeader = "Agent"
    static let commandsHeader = "Commands"
    static let noCommands = "Nothing matches"
    static func commandNeeds(_ entry: AskCommandEntry) -> String { "Needs \(entry.needs)" }
    /// A row's request when a command made it, which keeps it out of the
    /// thumbs: there was no request to judge.
    static let commandMark = "/"
    static func commandAsked(_ entry: AskCommandEntry) -> String { commandMark + entry.apiName }
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
    static let setUp = "Open Settings"
    static let selectMade = "Select What It Made"
    static let clearHistory = "Clear History…"
    static let clearHistoryMenuRow = "Clear Agent History…"
    static let clearHistoryQuestion = "Clear History?"
    static let clearHistoryYes = "Clear"
    static let clearHistoryCancel = "Cancel"
    static let clearHistoryTip = "Empties the list. The canvas stays as it is."
    static let historyMenuTip = "Clear the history"
    static let cardUnderstood = "Understood as"
    static let cardBefore = "Before"
    static let cardAfter = "After"
    static let cardUndone = "Undone"
    static let goodResult = "Good Result"
    static let badResult = "Bad Result"
    static let stoppedSentence = "Stopped. Nothing was changed."
    static let noDocumentSentence = "Open a picture or video first."
    /// A drawing that still did not read after being drawn again.
    static let couldNotDraw = "I couldn't make a clear drawing of that. Nothing was changed."
    static let iconMayNotRead = "This icon may not read clearly yet."
    static let helpLine = "Each request is one row. Rest on a row to see how it was understood, and click it to select what it made. One Command Z takes back the latest. A request sent while one is working waits its turn."
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

/// That a window on its way was asked for by the New Image sheet's Icon or App
/// Icon row, held until it is seeded with its picture. A window's id is written
/// down for restoring it, so this rides beside it rather than in it.
@MainActor
enum IconCanvasHandoff {
    private static var held: Set<UUID> = []

    static func hold(_ window: UUID) { held.insert(window) }

    static func take(_ window: UUID) -> Bool { held.remove(window) != nil }
}

/// A request typed into the New window's Describe field, held from the moment
/// it asks for a window until that window is seeded with its blank picture.
@MainActor
enum AskHandoff {
    private static var held: [UUID: String] = [:]

    static func hold(_ words: String, for window: UUID) { held[window] = words }

    static func take(_ window: UUID) -> String? { held.removeValue(forKey: window) }
}

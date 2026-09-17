import AppKit
import PhotonzCore

// What a guide runs OVER.
//
// Every track before the Video one taught in the picture editor, so the
// controller simply held an `EditorState`: it asked that for a window, told it
// to show the panel, and asked it whether what a step was waiting for was
// already so. A recording opens in a different window (`VideoEditorView`: one
// picture and one floating controller over it, no tool bar, no docked panel,
// no layers), so none of those questions have an answer there.
//
// This is the three questions, named. Both editors answer them; the controller
// asks nothing else of either, so a third kind of window becomes a third
// conformance rather than a branch in the controller.
@MainActor
protocol TutorialHost: AnyObject {
    /// The window the guide is teaching in. The callout is a child panel of it
    /// and every anchor is looked up inside it.
    var tutorialWindow: NSWindow? { get }

    /// Make this step's target visible. REVEAL ONLY, always: showing the panel
    /// so a step can point at the Layers list is fine, doing the thing the step
    /// asks the person to do is the timer lie in another costume. Anything the
    /// host has no equivalent of is ignored.
    func tutorialPrepare(_ prep: TutorialPrep)

    /// Whether what a step is waiting for is the case RIGHT NOW. Only a trigger
    /// that describes a STATE can be: nothing is already true about "the person
    /// made an edit".
    ///
    /// Asked twice over for two different reasons. Once as a step comes up, to
    /// spot a step asking for something that is already so, which shows Next
    /// rather than stranding somebody on Skip. And again, over and over, while
    /// a step waits on a VALUE (`TutorialTrigger.settingReached`), because a
    /// number the person is pulling towards is a question nothing can announce.
    func tutorialIsAlreadyTrue(_ trigger: TutorialTrigger) -> Bool

    /// A guide started or stopped over this window. The picture editor does not
    /// care; a recording's window keeps its floating controller up while one is
    /// running, because otherwise every control a video guide points at fades
    /// out two seconds after the pointer leaves it.
    func tutorialRunning(_ running: Bool)

    /// Whether this window is one a guide opened FOR ITSELF, holding a made up
    /// picture rather than anything of the person's own.
    ///
    /// What the card at the end of a guide asks before it offers to move
    /// somebody on: there is only somewhere to move on FROM when the window is
    /// practice, and offering to leave a window somebody was already working in
    /// would be the guide taking their work off the screen (`TutorialFinish`).
    var isTutorialSampleWindow: Bool { get }
}

extension TutorialHost {
    func tutorialRunning(_ running: Bool) {}
    var isTutorialSampleWindow: Bool { false }
}

// MARK: - The picture editor

extension EditorState: TutorialHost {
    var tutorialWindow: NSWindow? { hostWindow }

    /// Only a window seeded from a `.tutorial` id holds a sample, and only a
    /// sample that is a made up PICTURE is something to be moved on from: an
    /// empty window is already the place a person starts work.
    var isTutorialSampleWindow: Bool { tutorialSample?.isMadeUpPicture == true }

    func tutorialPrepare(_ prep: TutorialPrep) {
        switch prep {
        case .showPanel:
            if !isInspectorShown { setInspectorVisible(true) }
        case .showLibrary:
            if !isLibraryVisible { setLibraryVisible(true) }
        case .showComponentShelf:
            // The scope the shelf is on is remembered across launches and
            // starts as the captures you have taken, so a step about a button
            // would otherwise ring a shelf of screenshots. Same two lines Make
            // Component runs for the same reason.
            if !isLibraryVisible { setLibraryVisible(true) }
            UserDefaults.standard.set(LibraryScope.components.rawValue,
                                      forKey: LibraryPanel.scopeKey)
        case .revealTarget:
            break // the controller drives this one through the registry
        }
    }

    /// Whether one of the sheets a guide can point at is up right now.
    private func isShowing(_ dialog: TutorialAnchor.Dialog) -> Bool {
        switch dialog {
        case .newFrame: isNewFrameDialogPresented
        case .export: isExportDialogPresented
        }
    }

    /// Whether a setting a guide can wait for has reached its mark.
    ///
    /// Answered off what the person has SETTLED ON, never off a slider still
    /// under their finger. A pull that swept up past the mark and came back
    /// before letting go ends BELOW the mark, and a step that had already moved
    /// on for the highest number the pull passed through would be claiming
    /// something the person did not do, which is the exact lie this trigger
    /// exists to stop.
    ///
    /// Today the committed value is all `selectedLens` can answer anyway: a
    /// live pull renders through `submit` and never reaches the document until
    /// `commitLensAmount`. The guard says so out loud rather than resting on
    /// it, because where a preview is kept is a rendering decision and this is
    /// a promise to the person.
    private func isSetting(_ setting: TutorialSetting, atLeast mark: CGFloat) -> Bool {
        switch setting {
        case .lensAmount:
            guard let picked = selectedLens else { return false }
            guard lensAmountPreview?.id != picked.id else { return false }
            return picked.content.amount >= mark
        }
    }

    func tutorialIsAlreadyTrue(_ trigger: TutorialTrigger) -> Bool {
        switch trigger {
        case .toolPicked(let tool): activeTool == tool
        case .measureMode(let mode): activeTool == .measure && measureToolMode == mode
        case .panelShown: isInspectorShown
        case .layerSelected, .editMade, .undone, .pictureCopied, .specListCopied: false
        // The three that are STATES rather than events: somebody who already
        // works with the grid on, or who has the sheet up, has already done
        // what the step is asking for, and a step that made them switch it off
        // and on again would be the app arguing with them.
        case .gridShown: canvasGrid.isVisible
        case .keylinesShown: iconKeylinesShowing
        case .dialogOpened(let dialog): isShowing(dialog)
        // The one that is a NUMBER rather than a switch. Read off the lens the
        // person is holding, because that is the one whose slider the step is
        // pointing at; with nothing picked there is no number and the answer is
        // no, which leaves the step waiting with Skip on it rather than moving
        // on for a lens somebody is not looking at.
        case .settingReached(let setting, let mark): isSetting(setting, atLeast: mark)
        // Nothing a recording's window can do is ever already true in a
        // picture window, because none of it exists here.
        case .trimModeOpened, .trimStartMoved, .trimEndMoved, .trimApplied,
             .recordingCopied: false
        }
    }
}

// MARK: - A recording's window

extension VideoEditorState: TutorialHost {
    var tutorialWindow: NSWindow? { hostWindow }

    /// A recording window is practice when it is holding the clip the video
    /// guides bring with them, and somebody's own work otherwise.
    var isTutorialSampleWindow: Bool {
        url?.standardizedFileURL == TutorialSampleRecording.url.standardizedFileURL
    }

    /// Nothing to prepare. There is no docked panel and no shelf in here, and
    /// the one thing that DOES need revealing, the floating controller, is
    /// kept up for the whole guide rather than for one step: it holds every
    /// control a video guide points at, so a step by step reveal would be a
    /// ring appearing and fading three times a minute.
    func tutorialPrepare(_ prep: TutorialPrep) {}

    func tutorialIsAlreadyTrue(_ trigger: TutorialTrigger) -> Bool {
        switch trigger {
        // The trim being open is a state, and a guide restarted half way
        // through could find it open already.
        case .trimModeOpened: isTrimming
        // Everything else here is an event: the person dragged a handle, the
        // person pressed Done, the person copied the clip. None of those is
        // ever already so.
        case .trimStartMoved, .trimEndMoved, .trimApplied, .recordingCopied: false
        case .toolPicked, .measureMode, .panelShown, .layerSelected, .editMade,
             .undone, .pictureCopied, .specListCopied: false
        // A recording's window has no canvas, no grid, neither of these sheets
        // and no lens, so none of them is ever already so in here either.
        case .gridShown, .keylinesShown, .dialogOpened, .settingReached: false
        }
    }

    func tutorialRunning(_ running: Bool) {
        isTutorialRunning = running
    }
}

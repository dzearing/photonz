import AppKit
import Foundation
import PhotonzCore

// The clicks in a recording: the ones the recorder took down while it ran
// (beside the file, `PointerTrack.swift`) and the ones a person adds by hand.
//
// Adding one by hand is Add Click at Playhead… on the clip's right-click menu
// (and the Clip menu): the playhead says WHEN, and the next click on the
// picture says WHERE, under a crosshair. Escape calls it off. The click is an
// ordinary edit, so Command Z takes it back.
extension EditorState {

    /// Where the pointer went while this clip's recording was made, or nil for
    /// a clip whose recording kept nothing (made before Photonz kept it, or
    /// brought in from elsewhere).
    func recordedPointerTrack(ofClip id: UUID) -> PointerTrack? {
        guard let movie = document?.layer(id: id)?.movie else { return nil }
        return MovieLibrary.shared.pointerTrack(for: movie)
    }

    /// Every click on a clip, recorded and added by hand, in the order they
    /// happen in its recording.
    func clicks(ofClip id: UUID) -> [PointerClick] {
        PointerClick.all(recorded: recordedPointerTrack(ofClip: id),
                         added: document?.layer(id: id)?.addedClicks)
    }

    /// Whether a click can be added to this clip now: it plays a recording,
    /// it is under the playhead, and its track is not locked.
    func canAddClick(toClip id: UUID) -> Bool {
        guard let layer = document?.layer(id: id), layer.movie != nil,
              let time = layer.time, time.contains(ms: documentTimeMS) else { return false }
        return !isClipLocked(id)
    }

    /// The clip Add Click at Playhead… would add to from the menu bar: the
    /// clip in hand when it can take one, otherwise the recording under the
    /// playhead.
    var clipToAddClickTo: UUID? {
        if let clip = clipInHandID, canAddClick(toClip: clip) { return clip }
        return document?.allLayers.last { canAddClick(toClip: $0.id) }?.id
    }

    /// Choose where the click happened on the picture next.
    func beginPlacingClick(onClip id: UUID) {
        guard canAddClick(toClip: id) else { return }
        clickPlacementClip = id
        // Escape calls it off wherever the keyboard is, since the menu that
        // started it was on the timeline and the timeline may still have it.
        if clickPlacementEscape == nil {
            clickPlacementEscape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                let calledOff = MainActor.assumeIsolated { () -> Bool in
                    guard let self, self.clickPlacementClip != nil else { return false }
                    self.endPlacingClick()
                    return true
                }
                return calledOff ? nil : event
            }
        }
    }

    func endPlacingClick() {
        clickPlacementClip = nil
        if let monitor = clickPlacementEscape { NSEvent.removeMonitor(monitor) }
        clickPlacementEscape = nil
    }

    /// The click on the picture that says where it happened. A click off the
    /// recording's picture places nothing and leaves the crosshair up, so a
    /// near miss is not a lost step.
    func placeClick(at documentPoint: CGPoint) {
        guard let id = clickPlacementClip, let document else { endPlacingClick(); return }
        var trial = document
        guard trial.addClick(toClip: id, atMS: documentTimeMS, canvasPoint: documentPoint) != nil else {
            NSSound.beep()
            return
        }
        endPlacingClick()
        let ms = documentTimeMS
        perform { _ = $0.addClick(toClip: id, atMS: ms, canvasPoint: documentPoint) }
        raiseCanvasNotice(.clickAdded(atMS: ms), action: .undo)
    }
}

import CoreGraphics
import Foundation

// A component on the timeline (`components-on-the-timeline-animated-the-way-ever`,
// `docs/design/mocks/pages/video-compositing.html`).
//
// **A component placed on a recording is a layer with an in and an out.** That
// is the whole of it, and it is the same sentence titles are built on
// (`TitleTime.swift`): what you draw and what you edit are one document, so a
// badge you built in a design file goes on a video timeline without being
// exported, converted or imported first.
//
// Nothing here is about components in particular. The rule is **anything newly
// placed in a document with time arrives at the playhead and runs for three
// seconds**, and the three functions below are the three ways a component
// arrives: a copy of one this document already holds, one taken off the shared
// shelf for the first time, and one of the app's own starters.

extension PhotonzDocument {

    /// Give something that has just landed its stretch of the timeline.
    ///
    /// Refused, and harmlessly, in four cases: a document with no time in it
    /// (every screenshot, where none of this exists), something that already
    /// says when it is on screen, something with media behind it (a clip
    /// carries its own stretch and its own source), and something dropped
    /// INSIDE a layer that is itself placed in time — a part of a thing that
    /// arrives at four seconds arrives when the thing does, and giving it a
    /// second opinion is how a part goes missing while its parent is on
    /// screen.
    @discardableResult
    public mutating func placeInTime(_ id: UUID, atTimeMS ms: Int) -> Bool {
        guard let layer = layer(id: id), layer.time == nil, !layer.hasMediaBehindIt,
              !isInsideSomethingPlacedInTime(id), let span = placedSpan(atTimeMS: ms)
        else { return false }
        updateLayer(id: id) { $0.time = span }
        refreshDuration()
        return true
    }

    /// Whether anything this layer sits inside already says when it is on
    /// screen.
    func isInsideSomethingPlacedInTime(_ id: UUID) -> Bool {
        var current = parentID(of: id)
        while let this = current {
            if layer(id: this)?.time != nil { return true }
            current = parentID(of: this)
        }
        return false
    }

    /// A copy of a component this document already holds, placed at a moment
    /// of the document's own clock.
    ///
    /// One call rather than two so the copy and its stretch are one change:
    /// dropped on a recording, a component arrives already knowing when it is
    /// on screen, and undo takes the whole of it away.
    @discardableResult
    public mutating func insertComponentInstance(of componentID: UUID, at point: CGPoint,
                                                 inside context: UUID? = nil,
                                                 version: UUID? = nil,
                                                 atTimeMS ms: Int?) -> UUID? {
        guard let placed = insertComponentInstance(of: componentID, at: point,
                                                   inside: context, version: version)
        else { return nil }
        if let ms { placeInTime(placed, atTimeMS: ms) }
        return placed
    }

    /// The same, for a component taken off the shared shelf. What is placed in
    /// time is the COPY you let go of, which is what makes a component built in
    /// a design file show up on a recording at the moment you dropped it.
    @discardableResult
    public mutating func adoptSharedComponent(_ shared: SharedComponent, at point: CGPoint,
                                              inside context: UUID? = nil,
                                              atTimeMS ms: Int?) -> UUID? {
        let hadIt = mainComponent(componentID: shared.id) != nil
        guard let placed = adoptSharedComponent(shared, at: point, inside: context)
        else { return nil }
        if let ms {
            placeInTime(placed, atTimeMS: ms)
            if !hadIt { placeOriginalInTime(componentID: shared.id, besides: placed, atTimeMS: ms) }
        }
        return placed
    }

    /// ...and for one of the app's own starters.
    @discardableResult
    public mutating func insertStarterComponent(
        _ kind: StarterComponent, at point: CGPoint, inside context: UUID? = nil,
        measure: @escaping StarterTextMeasure = StarterComponents.estimatedTextSize,
        atTimeMS ms: Int?) -> UUID? {
        let hadIt = mainComponent(componentID: kind.componentID) != nil
        guard let placed = insertStarterComponent(kind, at: point, inside: context,
                                                  measure: measure) else { return nil }
        if let ms {
            placeInTime(placed, atTimeMS: ms)
            if !hadIt {
                placeOriginalInTime(componentID: kind.componentID, besides: placed, atTimeMS: ms)
            }
        }
        return placed
    }

    /// The ORIGINAL a first drop brought in with it, given the same stretch of
    /// the timeline as the copy you let go of.
    ///
    /// Without this, dragging a component onto a recording would leave its
    /// original standing on top of the whole film: the copy comes and goes at
    /// the moment you dropped it, and the parts bin beside it, which nothing
    /// placed it in time, would be on screen from the first frame to the last.
    private mutating func placeOriginalInTime(componentID: UUID, besides placed: UUID,
                                              atTimeMS ms: Int) {
        guard let main = mainComponent(componentID: componentID), main.id != placed else { return }
        placeInTime(main.id, atTimeMS: ms)
    }
}

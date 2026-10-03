/// What kind of layer a layer is, as the small mark in front of its name says
/// it: a path, a circle, words, a picture.
///
/// The timing strip draws it before each layer's heading, the way the Make a
/// bell swing mock does (`icon-animate-wt.html`, the timing dock), so a shape
/// tells itself from a picture or from text at a glance.
///
/// Finer than `TimelineTrackKind`, which is the kind of TRACK a layer sits on
/// and so calls every drawn shape an overlay. The mock marks the bell's body as
/// a path and its knob as a circle, so the mark tells the shapes apart.
public enum LayerMark: String, CaseIterable, Hashable, Sendable {
    case path, rectangle, ellipse, arrow, line, highlight
    case text, picture, video, sound
    case group, frame, component
    case zoomCallout, lens, measure, collage
}

extension Layer {
    /// This layer's kind mark. A placed component and a recording are what
    /// they are whatever they hold, which is the order `timelineTrackKind`
    /// reads them in too.
    public var mark: LayerMark {
        if instanceOf != nil { return .component }
        if movie != nil { return .video }
        if let merged { return merged.isSoundOnly ? .sound : .video }
        switch content {
        case .path: return .path
        case .annotation(let annotation):
            switch annotation.shape {
            case .rectangle: return .rectangle
            case .ellipse: return .ellipse
            case .arrow: return .arrow
            case .line: return .line
            case .highlight: return .highlight
            }
        case .text: return .text
        case .image: return .picture
        case .sound: return .sound
        case .group(let group): return group.isFrame ? .frame : .group
        case .zoomCallout: return .zoomCallout
        case .lens: return .lens
        case .measure: return .measure
        case .collage: return .collage
        }
    }
}

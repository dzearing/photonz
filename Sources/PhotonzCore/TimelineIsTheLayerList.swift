/// **Where there is a timeline, the timeline is the layer list.**
///
/// The user's video design leaves the Layers group out of the panel
/// (`docs/design/mocks/pages/video.html`, "NO LAYERS GROUP IN THE VIDEO LENS"):
/// it listed the same objects, in the same groups, in the same order as the
/// timeline under it, a second rendering of the thing you had just clicked. The
/// timeline carries everything Layers did (pick, rename, hide, lock, reorder,
/// the Captions group) plus when each thing starts and stops, so the panel
/// opens straight onto the picked clip instead.
///
/// This is NOT a mode and not one of `PanelSectionVisibility`'s optional
/// sections. A mode may never fold the layers list (`docs/design/modes.md` §2),
/// and nothing here lets it: the list goes because the WINDOW is showing the
/// timeline, which it does because the document has time, never because of a
/// mode. The same sentence decides the timeline itself.
///
/// And it comes straight back the moment the timeline is folded away, so a
/// document is never left with no list of what is in it. A picture with no time
/// is never touched.
public enum TimelineIsTheLayerList {

    /// The layers list's stored section id.
    public static let layersSection = "layers"

    /// Whether the panel draws its layers list.
    ///
    /// - Parameters:
    ///   - isOn: the Next flag that ships this rule.
    ///   - documentHasTime: the document has a length, so it has a timeline.
    ///   - isTimelineOpen: the timeline is on screen rather than folded down
    ///     to the one row it leaves behind.
    public static func showsLayersList(isOn: Bool, documentHasTime: Bool,
                                       isTimelineOpen: Bool) -> Bool {
        !(isOn && documentHasTime && isTimelineOpen)
    }

    /// The panel's sections with the layers list taken out where the timeline
    /// stands in for it, keeping the rest in their order. Nothing else is ever
    /// removed: this rule is about one list and only that list.
    public static func sections(_ sections: [String], isOn: Bool,
                                documentHasTime: Bool, isTimelineOpen: Bool) -> [String] {
        guard !showsLayersList(isOn: isOn, documentHasTime: documentHasTime,
                               isTimelineOpen: isTimelineOpen) else { return sections }
        return sections.filter { $0 != layersSection }
    }
}

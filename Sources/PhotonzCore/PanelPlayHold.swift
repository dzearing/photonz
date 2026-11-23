/// Whether the pieces of the right hand panel a pick brings in (a section the
/// dock lets in, the rows a section brings a pass late) wait for a playing
/// video to stop.
///
/// Every piece that lands costs the window a frame or two, and while a video
/// plays that frame is the picture's: picking a clip from nothing on the 6
/// minute reference edit while it played landed eight sections and six sets
/// of rows over 0.7 s, in passes of 16 to 61 ms against the 16 a frame has
/// (`picking-letting-go-of-and-cutting-a-clip-while-a`, 2026-11-23). Nobody
/// tunes a clip that is sliding past, so the pieces wait, and the panel
/// catches up when play stops, as it already does with nothing picked
/// (`EditorState+PanelPlayhead`). Somebody who brings the pointer into the
/// panel has come to use it, so then they land at once, playing or not.
public enum PanelPlayHold {
    public static func waits(hasTime: Bool, playing: Bool, pointerInPanel: Bool) -> Bool {
        hasTime && playing && !pointerInPanel
    }
}

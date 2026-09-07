/// The one word the app uses for the right hand panel, and every phrase built
/// from it.
///
/// The same button used to answer to three names at once: resting on it said
/// Panel, the View menu said Show Layers, and the walk that photographs every
/// tooltip was still asking for Inspector. A person who reads the menu and then
/// looks for it on screen was hunting for a word that is not there, and the
/// walk had already stopped working over it (2026-09-07).
///
/// Panel is the word, for two reasons. It is what the thing is: one column
/// holding Layers, Library, Appearance, Measurement and whatever the tool in
/// hand brings with it, so naming the whole column Layers names one of its
/// sections and hides the rest. And it is the word the app already used
/// everywhere else — the button's own tooltip, every commit, every audit — so
/// nothing has to be re-learned. Inspector was the older word and is retired:
/// half the column inspects nothing.
///
/// Everything that names the panel reads it from here, so the three names
/// cannot come back one file at a time.
public enum PanelCopy {
    /// The panel itself, as a person says it. Title Case: it is a proper part
    /// of the window, the way the Library shelf is.
    public static let noun = "Panel"

    /// The View menu's row. A setting, so ONE name plus a checkmark, never a
    /// name that flips (see `MenuToggleNames`).
    public static let menuItem = "Show " + noun

    /// Resting on the title bar button. A tooltip DOES flip, because it names
    /// the action a press would take rather than a state, and there is no
    /// checkmark on a button to say which way it is.
    public static let showTooltip = "Show " + noun
    public static let hideTooltip = "Hide " + noun

    /// What a scripted walk asks for. One name in both states: it is one
    /// button in one place, so a walk presses whatever it currently means.
    public static let controlName = noun
}

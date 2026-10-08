import Foundation

/// The names a tool goes by where the document changes what it is for.
///
/// On a video the T tool makes titles, and an editor coming from Premiere or
/// Final Cut looks for it as the Title tool (`video-title-wt.html`: "Pick up
/// the Title tool", its tooltip "Title / Text (T)"). On a picture it is the
/// Text tool it has always been. The name follows the document, so the bar,
/// its More menu, Edit ▸ Tools and a guide's card all read one answer.
public enum ToolName {

    /// The T tool's name: Title in a document with time, Text in a picture.
    public static func text(inTime: Bool) -> String {
        inTime ? "Title" : "Text"
    }

    /// The T tool's tooltip label: the mock's "Title / Text" on a video, so a
    /// person who knows it as Text still finds it, and Text on a picture.
    public static func textTip(inTime: Bool) -> String {
        inTime ? "Title / Text" : "Text"
    }

    /// The name `tool` goes by in this document when it is not its usual one,
    /// nil when it keeps the name it has everywhere.
    public static func renamed(_ tool: Tool, inTime: Bool) -> String? {
        tool == .text && inTime ? text(inTime: true) : nil
    }
}

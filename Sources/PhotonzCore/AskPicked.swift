import Foundation

/// Ask works on what is picked (`docs/design/ask.md`, "What is picked"), the
/// way generative fill works on a selection in Photoshop: the read says what
/// is picked, this rule aims "this" and "it" at it, and the composer shows the
/// scope, as the mock `agent-edit.html` does.
///
/// With nothing picked there is no rule and no scope, so a request is sent
/// word for word as it was before any of this.
public enum AskPicked {

    /// How the rule starts, for telling that it is there.
    static let ruleOpening = "- The person has picked"

    /// The composer's scope: "1 selected", "3 selected", nothing at none.
    public static func scope(count: Int) -> String? {
        count > 0 ? "\(count) selected" : nil
    }

    /// The line for the instructions, or nil when `documentRead` says nothing
    /// is picked. Read from the read itself, never searched for in its words,
    /// so a layer's own text can never pass for a pick.
    static func rule(documentRead: String) -> String? {
        guard let read = try? JSONDecoder().decode(AgentDocumentRead.self, from: Data(documentRead.utf8)),
              let picked = read.selected, !picked.isEmpty else { return nil }
        let listed = picked.map { "\($0.name) (\($0.id))" }.joined(separator: ", ")
        return """
        \(ruleOpening) \(listed). "This", "it", "these", "them", "the selection" and a change that \
        names no layer ("make it bigger", "round the corners") mean what is picked: change those layers by \
        those ids and leave every other layer exactly as it is. A request that names another layer goes to \
        that layer. A request to make something new still makes it, and one about the whole picture is \
        about the whole picture.
        """
    }
}

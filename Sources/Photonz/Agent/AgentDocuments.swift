import AppKit
import PhotonzCore

/// The open documents as an agent names them (`docs/design/agent-mcp.md`).
///
/// Each editor gets a short id (`d1`, `d2`, ...) the first time a window is
/// seeded with it, and keeps it for as long as the window is open. Held
/// weakly: a closed window's editor goes away and so does its entry.
@MainActor
enum AgentDocuments {

    private static let editors = NSHashTable<EditorState>.weakObjects()
    private static var count = 0

    static func note(_ editor: EditorState) {
        guard !editor.isWarmUp, editor.agentID == nil else { return }
        count += 1
        editor.agentID = "d\(count)"
        editors.add(editor)
    }

    /// Every editor holding a document in a window, front window first.
    static var open: [EditorState] {
        let order = Dictionary(NSApp.orderedWindows.enumerated().map { (ObjectIdentifier($0.element), $0.offset) },
                               uniquingKeysWith: { first, _ in first })
        return editors.allObjects
            .filter { $0.document != nil && $0.agentID != nil && ($0.hostWindow?.isVisible ?? false) }
            .sorted { a, b in
                let ia = a.hostWindow.flatMap { order[ObjectIdentifier($0)] } ?? Int.max
                let ib = b.hostWindow.flatMap { order[ObjectIdentifier($0)] } ?? Int.max
                return ia < ib
            }
    }

    /// The editor highest in the app's window order: the one a person is
    /// looking at, whether or not it holds the keys right now.
    static var front: EditorState? { open.first }

    /// The editor an agent named, or the one in front when it named none.
    static func editor(_ id: String?) -> Result<EditorState, AgentWork.Failure> {
        let open = open
        guard let id else {
            if let front = open.first { return .success(front) }
            return .failure(.init("No document is open in Photonz. Open one with open_document."))
        }
        if let editor = open.first(where: { $0.agentID == id }) { return .success(editor) }
        let ids = open.compactMap(\.agentID).joined(separator: ", ")
        return .failure(.init(ids.isEmpty
            ? "There is no document \(id), and none is open. Open one with open_document."
            : "There is no document \(id). The open ones are \(ids)."))
    }

    /// Every file a window's document came from or was saved to.
    static func files(of editor: EditorState) -> [URL] {
        [editor.documentURL, editor.openedFileURL, editor.recordingURL, editor.sourceCaptureURL]
            .compactMap { $0?.standardizedFileURL }
    }
}

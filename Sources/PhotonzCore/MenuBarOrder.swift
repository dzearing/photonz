/// The order of the menus along the top of the screen, the way a professional
/// Mac editor lays them out: the app, File, Edit, the menus for what the
/// document is made of, then View, Window and Help (Photoshop's File, Edit,
/// Image, Layer ... View, Window, Help; Final Cut's Clip beside its timeline
/// menus). The placement contract's Menu bar row, UX-PATTERNS.md.
///
/// SwiftUI puts every `CommandMenu` AFTER its own View menu, so left alone the
/// bar read Photonz, File, Edit, View, Image, Layer ... (measured on the probe
/// on 2026-09-29). Nothing in SwiftUI moves View, so the app moves it: this is
/// the one move, worked out here where it can be tested, and applied to the
/// live bar by `MenuBarArranger`.
public enum MenuBarOrder {
    public static let view = "View"
    public static let window = "Window"
    public static let help = "Help"
    /// The picked clip's commands (Final Cut's Clip menu, Premiere's Clip).
    public static let clip = "Clip"
    /// The commands about time as a whole (Premiere's Sequence menu).
    public static let sequence = "Sequence"

    /// The menus for what the document is made of, in the order they read.
    /// Clip and Sequence are there only on a document with time.
    public static let documentMenus = ["Image", "Layer", clip, sequence, "Measure"]

    public struct Move: Equatable, Sendable {
        public let from: Int
        public let to: Int
    }

    /// The single move that puts View straight before Window (before Help
    /// when there is no Window menu, last when there is neither), or nil when
    /// it is already there. `to` is the index View ends up at after it has
    /// been taken out, which is how `NSMenu.insertItem` wants it.
    public static func viewMove(in titles: [String]) -> Move? {
        guard let from = titles.firstIndex(of: view) else { return nil }
        var rest = titles
        rest.remove(at: from)
        let to = rest.firstIndex(of: window) ?? rest.firstIndex(of: help) ?? rest.count
        return to == from ? nil : Move(from: from, to: to)
    }

    /// The titles as they read once the move is made.
    public static func arranged(_ titles: [String]) -> [String] {
        guard let move = viewMove(in: titles) else { return titles }
        var result = titles
        let item = result.remove(at: move.from)
        result.insert(item, at: move.to)
        return result
    }
}

/// One shortcut printed on more than one row of the menu bar. A key can only
/// do one thing, so every row but one is promising something the key will not
/// do. The playtest `menus` step reads the live bar into rows and fails a walk
/// on any clash when it is asked to (`oneKeyEach`).
public struct MenuKeyClash: Equatable, Sendable {
    public let chord: String
    public let paths: [String]

    public init(chord: String, paths: [String]) {
        self.chord = chord
        self.paths = paths
    }

    public struct Row: Equatable, Sendable {
        public let path: String
        public let chord: String

        public init(path: String, chord: String) {
            self.path = path
            self.chord = chord
        }
    }

    /// "⇧Z is on Clip ▸ Punch In and View ▸ Zoom Timeline to Fit".
    public var sentence: String {
        let rows = paths.count > 2
            ? paths.dropLast().joined(separator: ", ") + " and " + (paths.last ?? "")
            : paths.joined(separator: " and ")
        return "\(chord) is on \(rows)"
    }

    /// Every chord more than one row prints, in the order the first of them
    /// reads along the bar.
    public static func clashes(in rows: [Row]) -> [MenuKeyClash] {
        var order: [String] = []
        var paths: [String: [String]] = [:]
        for row in rows {
            if paths[row.chord] == nil { order.append(row.chord) }
            paths[row.chord, default: []].append(row.path)
        }
        return order.compactMap { chord in
            guard let found = paths[chord], found.count > 1 else { return nil }
            return MenuKeyClash(chord: chord, paths: found)
        }
    }
}

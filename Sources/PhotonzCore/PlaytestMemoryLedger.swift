import Foundation

/// What one walk changed in the app's remembered settings, and what has to go
/// back when it ends.
///
/// The probe keeps its settings between runs on purpose: that is what a
/// person's app does, and a walk that assumed a fresh state would be lying
/// about what the app is like. The cost, until this landed, was that a walk
/// which changed a setting handed the NEXT walk a machine it never asked for.
/// Four walks were failing that way on 2026-09-05: each passed on its own and
/// failed inside the full run, because something earlier had moved a size, a
/// colour or the dock under it.
///
/// So the walk still sees the app remember things while it runs, and the
/// machine is put back to exactly what it was the moment the walk ends. The
/// order of the walks then cannot change the answer, which is the whole point
/// of running them together.
public struct PlaytestMemoryLedger: Sendable, Equatable {
    /// Areas of memory whose settings are not what they were, in the order the
    /// app remembers them, so a log line reads the same way every time.
    public let changed: [PlaytestMemory]
    /// The value to put back for each setting that moved. A `nil` value means
    /// the walk created that setting out of nothing, so putting it back means
    /// taking it away again.
    public let restore: [String: Data?]

    /// Works out what moved between two readings of the same settings.
    ///
    /// - Parameters:
    ///   - before: every remembered setting as it stood before step one, by
    ///     key. A key that was not set at all is simply absent.
    ///   - after: the same reading, taken as the walk ends.
    ///   - keys: which keys belong to which area of memory. Anything not named
    ///     here is not the walk's business and is left alone.
    public init(before: [String: Data], after: [String: Data], keys: [PlaytestMemory: [String]]) {
        var changed: [PlaytestMemory] = []
        var restore: [String: Data?] = [:]
        for memory in PlaytestMemory.allCases {
            var moved = false
            for key in keys[memory] ?? [] where before[key] != after[key] {
                restore[key] = .some(before[key])
                moved = true
            }
            if moved { changed.append(memory) }
        }
        self.changed = changed
        self.restore = restore
    }

    /// The areas this walk changed without saying it would, given what its
    /// `setup` block declared. Nothing is failed over this: it is the line a
    /// walk's author reads when they want to know what to declare.
    public func undeclared(given declared: [PlaytestMemory]) -> [PlaytestMemory] {
        changed.filter { !declared.contains($0) }
    }

    /// One line for the log, in plain words.
    public var report: String {
        changed.isEmpty
            ? "left every remembered setting as it found it"
            : "put back " + changed.map(\.rawValue).joined(separator: ", ")
    }
}

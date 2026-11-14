import Foundation

extension Dictionary {
    /// This dictionary without the entries whose keys `isLiving` turns down,
    /// or nil when every key is living and there is nothing to take out.
    ///
    /// For a cache somebody watches: writing it back unchanged tells every
    /// watcher it changed, so a prune that finds nothing dead must not write
    /// at all (`CachePruningTests`).
    public func withoutDead(keeping isLiving: (Key) -> Bool) -> Self? {
        guard keys.contains(where: { !isLiving($0) }) else { return nil }
        return filter { isLiving($0.key) }
    }
}

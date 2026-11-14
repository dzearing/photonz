import Testing
@testable import PhotonzCore

/// A cache of pictures keyed by layer is pruned of layers that have gone, and
/// only then (`Dictionary.withoutDead`). The editor watches its caches, so a
/// cache written back unchanged wakes every view that draws from it: on
/// 2026-11-14 every edit of a long video rewrote three of them, because the
/// prune ran whenever the cache held a different number of pictures than the
/// document had layers, which on a video is nearly always.
@Suite struct CachePruningTests {
    @Test func aCacheOfLivingKeysIsLeftAlone() {
        let cache = ["a": 1, "b": 2]
        #expect(cache.withoutDead(keeping: { _ in true }) == nil)
    }

    @Test func anEmptyCacheIsLeftAlone() {
        let cache: [String: Int] = [:]
        #expect(cache.withoutDead(keeping: { _ in false }) == nil)
    }

    @Test func aDeadKeyIsTakenOutAndTheRestKept() {
        let cache = ["a": 1, "b": 2, "c": 3]
        #expect(cache.withoutDead(keeping: { $0 != "b" }) == ["a": 1, "c": 3])
    }

    @Test func everyKeyDeadLeavesAnEmptyCache() {
        let cache = ["a": 1]
        #expect(cache.withoutDead(keeping: { _ in false }) == [:])
    }

    /// The number of entries says nothing: a cache holding fewer pictures than
    /// there are layers, all of them living, is left alone.
    @Test func fewerEntriesThanLivingKeysIsNotAPrune() {
        let living: Set<String> = ["a", "b", "c", "d"]
        let cache = ["a": 1, "c": 3]
        #expect(cache.withoutDead(keeping: living.contains) == nil)
    }
}

import Foundation
import PhotonzCore
import Testing

/// Where the strip writes "repeats": up on the ruler beside the dashed line,
/// unless that would put it on top of a tick's number, in which case it drops
/// to the band just under the ruler so each is readable on its own.
///
/// A lone 800 ms spinner starts over exactly on the ruler's 800, and with the
/// label on the ruler the two read as "800eats" (2026-10-15).
@Suite("The repeats label on the timing strip")
struct MotionStripRepeatsLabelTests {

    /// Monospaced digits at the ruler's size, near enough what the strip draws.
    static func tickWidth(_ label: String) -> Double { Double(label.count) * 5.4 }
    static let repeatsWidth = 36.0

    static func place(cycleMS: Int, laneWidth: Double) -> MotionStripRuler.RepeatsLabelPlace {
        MotionStripRuler(cycleMS: cycleMS).repeatsLabelPlace(
            laneWidth: laneWidth, labelWidth: repeatsWidth, tickLabelWidth: tickWidth)
    }

    @Test("A turn that ends on a tick drops its label under the ruler")
    func onATickDropsUnder() {
        #expect(Self.place(cycleMS: 800, laneWidth: 920) == .underTheRuler)
    }

    @Test("A lap that ends between ticks keeps its label on the ruler")
    func betweenTicksStaysOnTheRuler() {
        #expect(Self.place(cycleMS: 900, laneWidth: 920) == .onTheRuler)
    }

    @Test("A restart just past a tick, close enough to land on its number, drops under")
    func justPastATickDropsUnder() {
        #expect(Self.place(cycleMS: 810, laneWidth: 920) == .underTheRuler)
    }

    @Test("A narrow strip where the label would run into the next tick drops under")
    func runningIntoTheNextTickDropsUnder() {
        #expect(Self.place(cycleMS: 900, laneWidth: 300) == .underTheRuler)
    }

    @Test("A ruler that does not repeat has no label to move")
    func aDocumentKeepsItsPlace() {
        let ruler = MotionStripRuler(documentMS: 8000)
        #expect(ruler.repeatsLabelPlace(laneWidth: 920, labelWidth: Self.repeatsWidth,
                                        tickLabelWidth: Self.tickWidth) == .onTheRuler)
    }
}

import Foundation
import PhotonzCore
import Testing

@Suite("Letters that move as one piece")
struct LetterSteadinessTests {
    private func marks(_ scale: Double, nudge: Double = 0) -> [LetterSteadiness.Mark] {
        [(10.0, 20.0), (40, 22), (75, 19), (120, 21)].enumerated().map { i, p in
            .init(x: 50 + p.0 * scale + (i == 1 ? nudge : 0), y: 30 + p.1 * scale, ink: 20)
        }
    }

    @Test("A word growing as one piece slips nowhere and only grows")
    func growsAsOne() {
        let read = LetterSteadiness((0...20).map { marks(0.5 + 0.025 * Double($0)) })
        #expect(read.slip < 1e-9)
        #expect(read.unread == 0)
        #expect(read.sizesKeepGoing())
        #expect(abs((read.sizes.first ?? 0) - 0.5) < 1e-9)
    }

    @Test("One letter jumping half a pixel is read as slipping")
    func oneLetterJumps() {
        let read = LetterSteadiness((0...20).map { marks(0.5 + 0.025 * Double($0), nudge: $0 == 7 ? 0.5 : 0) })
        #expect(read.slip > 0.25)
    }

    @Test("A word stepping back on its way up is caught")
    func stepsBack() {
        #expect(!LetterSteadiness([0.5, 0.6, 0.59, 0.7, 1].map { marks($0) }).sizesKeepGoing())
    }

    @Test("A picture missing a letter is counted as unread, not measured")
    func missingLetter() {
        let read = LetterSteadiness([marks(0.5), Array(marks(0.6).dropLast()), marks(0.8), marks(1)])
        #expect(read.unread == 1)
        #expect(read.sizes.count == 3)
    }

    @Test("A dot and the stem under it are told apart whichever is found first")
    func dotAndStemSwap() {
        let pictures = (0...6).map { step -> [LetterSteadiness.Mark] in
            let word = marks(1 + Double(step) / 10) + [.init(x: 50 + 150 * (1 + Double(step) / 10), y: 10, ink: 5),
                                                       .init(x: 50 + 150 * (1 + Double(step) / 10), y: 60, ink: 5)]
            return step.isMultiple(of: 2) ? word : word.reversed()
        }
        // Their y grows with the word's, so only the pairing is at stake.
        let grown = pictures.enumerated().map { step, marks in
            marks.map { LetterSteadiness.Mark(x: $0.x, y: $0.ink < 10 ? 30 + ($0.y - 30) * (1 + Double(step) / 10) : $0.y,
                                              ink: $0.ink) }
        }
        #expect(LetterSteadiness(grown).slip < 1e-6)
    }

    @Test("Marks are the islands of ink, centred on their ink")
    func findsMarks() {
        var ink = [UInt8](repeating: 0, count: 20 * 10)
        for y in 2..<6 { for x in 1..<4 { ink[y * 20 + x] = 255 } }
        for y in 3..<7 { for x in 10..<14 { ink[y * 20 + x] = 128 } }
        ink[9 * 20 + 19] = 40
        let found = LetterSteadiness.marks(in: ink, width: 20, height: 10)
        #expect(found.count == 2)
        #expect(abs(found[0].x - 2.5) < 1e-9 && abs(found[0].y - 4) < 1e-9 && abs(found[0].ink - 12) < 1e-9)
        #expect(abs(found[1].x - 12) < 1e-9 && abs(found[1].y - 5) < 1e-9)
    }
}

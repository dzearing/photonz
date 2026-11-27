import Foundation
import PhotonzCore
import Testing

/// A dropout is what a person hears as the sound cutting out: a stretch over
/// 10 ms quieter than -45 dB where something should be playing.
@Suite("Finding where sound drops out")
struct SoundDropoutsTests {

    static let rate = 44_100.0

    static func tone(seconds: Double, amplitude: Float = 0.5) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * Double.pi * 440 * Double($0) / rate)) }
    }

    @Test("A steady tone has no dropouts, though it crosses nought twice a cycle")
    func steadyToneIsUnbroken() {
        #expect(SoundDropouts.find(in: Self.tone(seconds: 2), sampleRate: Self.rate).isEmpty)
    }

    @Test("A hole of half a second in a tone is found, where it is")
    func holeIsFound() {
        var samples = Self.tone(seconds: 3)
        for index in Int(1.0 * Self.rate)..<Int(1.5 * Self.rate) { samples[index] = 0 }
        let found = SoundDropouts.find(in: samples, sampleRate: Self.rate)
        #expect(found.count == 1)
        #expect(abs((found.first?.fromMS ?? 0) - 1000) <= 2)
        #expect(abs((found.first?.toMS ?? 0) - 1500) <= 2)
        #expect(abs((found.first?.lengthMS ?? 0) - 500) <= 3)
    }

    @Test("A hole under 10 ms is not a dropout, one over it is")
    func tenMillisecondBar() {
        var short = Self.tone(seconds: 1)
        for index in 22_050..<(22_050 + Int(0.008 * Self.rate)) { short[index] = 0 }
        #expect(SoundDropouts.find(in: short, sampleRate: Self.rate).isEmpty)
        var long = Self.tone(seconds: 1)
        for index in 22_050..<(22_050 + Int(0.012 * Self.rate)) { long[index] = 0 }
        #expect(SoundDropouts.find(in: long, sampleRate: Self.rate).count == 1)
    }

    @Test("Sound quieter than -45 dB counts as silence, sound above it does not")
    func levelBar() {
        let under = Self.tone(seconds: 1, amplitude: 0.004)   // about -48 dB
        let over = Self.tone(seconds: 1, amplitude: 0.01)     // about -40 dB
        #expect(SoundDropouts.find(in: under, sampleRate: Self.rate).count == 1)
        #expect(SoundDropouts.find(in: over, sampleRate: Self.rate).isEmpty)
    }

    @Test("A hole running to the end of what was heard is still a dropout")
    func holeAtTheEnd() {
        var samples = Self.tone(seconds: 1)
        for index in Int(0.8 * Self.rate)..<samples.count { samples[index] = 0 }
        let found = SoundDropouts.find(in: samples, sampleRate: Self.rate)
        #expect(found.count == 1)
        #expect(abs((found.first?.toMS ?? 0) - 1000) <= 2)
    }

    @Test("It says what it found in a line a walk can print")
    func summary() {
        var samples = Self.tone(seconds: 2)
        for index in Int(1.0 * Self.rate)..<Int(1.25 * Self.rate) { samples[index] = 0 }
        let found = SoundDropouts.find(in: samples, sampleRate: Self.rate)
        #expect(SoundDropouts.describe(found) == "1 dropout: 1.000 to 1.250 s")
        #expect(SoundDropouts.describe([]) == "no dropouts")
    }
}

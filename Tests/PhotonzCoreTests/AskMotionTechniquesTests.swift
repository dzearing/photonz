import Foundation
import Testing
@testable import PhotonzCore

/// The general motion techniques Ask picks from for a moving icon
/// (`AskMotionTechnique`, docs/design/ask.md "The techniques it picks from").
@Suite struct AskMotionTechniquesTests {
    /// Every subject the eval's animated cases and the user's examples name.
    /// None of them may appear in what the model is told about motion.
    static let subjects = ["trash", "lid", "bell", "envelope", "heart", "rocket", "checkbox", "checkmark", "balloon",
                           "spinner", "gear", "wifi", "plane", "letter", "star", "arrow", "door", "flag", "cup",
                           "steam", "dog", "tail", "phone", "bin", "tick", "flap"]

    @Test("The catalogue holds the thirteen techniques the user's list names, each said once")
    func thirteen() {
        let names = AskMotionTechnique.allCases.map(\.name)
        #expect(names.count == 13)
        #expect(Set(names).count == 13)
        for name in ["turn on a pivot", "fold over an edge", "squash and stretch", "throw on an arc", "shake", "pulse",
                     "sway in a chain", "spin or orbit", "draw a line on", "pop in or out", "enter or leave the frame",
                     "rest between laps", "follow through and stagger"] {
            #expect(names.contains(name), "\(name)")
        }
    }

    @Test("Every technique is carried by keys an animated SVG keeps, and says them by the names the tool takes")
    func keysTheFileKeeps() {
        for technique in AskMotionTechnique.allCases {
            #expect(!technique.keys.isEmpty, "\(technique)")
            for key in technique.keys {
                #expect(MotionSVG.carried.contains(key), "\(technique): \(key)")
            }
            // At least one of its keys is named in its own words, so the model knows what to call.
            #expect(technique.keys.contains { technique.does.contains($0.rawValue) }, "\(technique)")
        }
    }

    @Test("No technique names a subject: each is said by parts, pivots, paths and time")
    func noSubject() {
        let told = (AskMotionTechnique.catalogue + AskMotion.drawRules + AskMotion.designAsk + AskMotion.keyRules).lowercased()
        let words = Set(told.split { !$0.isLetter }.map(String.init))
        for subject in Self.subjects {
            #expect(!words.contains(subject), "\(subject)")
        }
    }

    @Test("The whole catalogue is read where a technique is chosen: the design, and keys on a picture that has no design")
    func taught() {
        for technique in AskMotionTechnique.allCases {
            #expect(AskMotion.keyRules.contains("\(technique.name): "), "\(technique)")
        }
        let body = AskMotion.designBody(model: "m", request: "make an animated icon of a thing")
        let system = body["messages"]?.arrayValue?.first?["content"]?.stringValue ?? ""
        #expect(system.contains(AskMotionTechnique.catalogue))
        // The plan that draws a design reads only what the design chose.
        #expect(!AskMotion.drawRules.contains(AskMotionTechnique.catalogue))
    }

    @Test("The plan is told how to key the techniques its design named, and only those")
    func chosenOnly() {
        let design = "3) arm: Turn on a pivot, at its top end; marks: pop in or out, then follow-through and stagger."
        #expect(AskMotionTechnique.chosen(in: design) == [.turn, .pop, .followThrough])
        let told = AskMotion.drawTheDesign(design)
        #expect(told.hasPrefix(AskMotion.drawTheDesign))
        #expect(told.contains("- turn on a pivot: \(AskMotionTechnique.turn.does)"))
        #expect(told.contains("- pop in or out: "))
        #expect(!told.contains("spin or orbit"))
        // A design that names none is drawn as before.
        #expect(AskMotion.drawTheDesign("Parts and beats.") == AskMotion.drawTheDesign)
        let talk = AskConversation(request: "make an animated icon of a thing", documentRead: #"{"kind":"picture","canvas":{"width":512,"height":512}}"#, iconDesign: design)
        #expect(talk.messages.last?["content"]?.stringValue == told)
    }

    @Test("A technique named in a model's own words is still found, and a word inside another word is not")
    func saidInOwnWords() {
        #expect(AskMotionTechnique.chosen(in: "the blades spin; the body buzzes? no: buzz") == [.shake, .spin])
        #expect(AskMotionTechnique.chosen(in: "it breathes slowly, breathing in") == [.pulse])
        #expect(AskMotionTechnique.chosen(in: "spinning and popping") == [])
    }

    @Test("The design says which technique it chose for which part, and combines them when the request asks for more than one thing")
    func designNamesTheTechnique() {
        #expect(AskMotion.designAsk.contains("technique"))
        #expect(AskMotion.designAsk.contains("for each part that moves"))
        #expect(AskMotion.designAsk.contains("more than one"))
    }

    @Test("Squash and stretch is said with the keys that can do it: a fold squeezes one way, scale makes up the bulk")
    func squashIsAFoldAndAScale() {
        let squash = AskMotionTechnique.squash
        #expect(squash.does.contains("rotationX"))
        #expect(squash.does.contains("rotationY"))
        #expect(squash.does.contains("scale"))
        #expect(squash.does.contains("bottom edge"))
    }
}

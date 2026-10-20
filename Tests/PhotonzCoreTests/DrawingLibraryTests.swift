import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The built-in drawing set Ask draws a thing from (`DrawingLibrary.swift`).
@Suite("The built-in drawing set finds a drawing by the words people use")
struct DrawingLibraryTests {

    static let circle = ##"<svg viewBox="0 0 36 36"><circle cx="18" cy="18" r="18" fill="#C1694F"/></svg>"##

    static let library = DrawingLibrary(entries: [
        .init(name: "dog face", words: ["dog", "face", "pet"], svg: circle),
        .init(name: "dog", words: ["pet"], svg: circle, aliases: ["puppy"]),
        .init(name: "racing car", words: ["car", "racing"], svg: circle),
        .init(name: "automobile", words: ["car", "vehicle"], svg: circle, aliases: ["car"]),
        .init(name: "hot beverage", words: ["coffee", "drink", "tea"], svg: circle, aliases: ["coffee cup", "cup"]),
        .init(name: "sunrise over mountains", words: ["morning", "mountain", "sun", "sunrise"], svg: circle),
        .init(name: "mountain", words: [], svg: circle),
        .init(name: "slightly smiling face", words: ["face", "smile"], svg: circle,
              aliases: ["smiley", "smiley face"], isFace: true),
    ])

    @Test("A plain name finds its drawing, words like a, picture and icon set aside",
          arguments: [("dog", "dog"), ("a dog", "dog"), ("a picture of a dog.", "dog"), ("Puppy", "dog"),
                      ("dogs", "dog"), ("car", "automobile"), ("a coffee cup", "hot beverage"),
                      ("smiley face icon", "slightly smiling face"), ("the sun over mountains", "sunrise over mountains"),
                      ("a mountain", "mountain"), ("cute little dog", "dog"), ("dog face", "dog face")])
    func finds(subject: String, expected: String) {
        #expect(Self.library.match(subject)?.name == expected)
    }

    @Test("Something the set does not have finds nothing, so the agent draws it itself",
          arguments: ["a bicycle", "spaceship interior", "", "a picture"])
    func findsNothing(subject: String) {
        #expect(Self.library.match(subject) == nil)
    }

    @Test("The set reads from its file")
    func decodes() throws {
        let json = #"{"about":"x","drawings":[{"n":"dog","w":["pet"],"s":"<svg/>","a":["puppy"]},{"n":"grinning face","w":[],"s":"<svg/>","f":true}]}"#
        let library = try #require(DrawingLibrary.decode(Data(json.utf8)))
        #expect(library.entries.count == 2)
        #expect(library.entries[0].aliases == ["puppy"])
        #expect(library.entries[1].isFace)
        #expect(library.match("puppy")?.name == "dog")
    }

    @Test("A face's parts are named face, eyes and mouth, so they can be found and checked")
    func faceParts() throws {
        let svg = """
            <svg viewBox="0 0 36 36"><circle cx="18" cy="18" r="18" fill="#FFCC4D"/><path fill="#664500" d="M10.515 23.621C10.56 23.8 11.683 28 18 28c6.318 0 7.44-4.2 7.485-4.379a.499.499 0 0 0-.237-.554.505.505 0 0 0-.6.077C24.629 23.163 22.694 25 18 25s-6.63-1.837-6.648-1.855a.502.502 0 0 0-.598-.081.5.5 0 0 0-.239.557z"/><ellipse cx="12" cy="13.5" fill="#664500" rx="2.5" ry="3.5"/><ellipse cx="24" cy="13.5" fill="#664500" rx="2.5" ry="3.5"/><path fill="#664500" d="M8 8h6v1H8zM22 8h6v1h-6z"/></svg>
            """
        let entry = DrawingLibrary.Entry(name: "slightly smiling face", words: [], svg: svg, isFace: true)
        let drawing = try entry.drawing().get()
        #expect(drawing.parts.map(\.name) == ["Face", "Mouth", "Left eye", "Right eye", nil])
    }

    @Test("A drawing that is not a face keeps its parts unnamed, for the drawing's name to number")
    func notAFace() throws {
        let entry = DrawingLibrary.Entry(name: "dog", words: [], svg: Self.circle)
        #expect(try entry.drawing().get().parts.map(\.name) == [nil])
    }

    // MARK: The set that ships

    static func shipped() throws -> DrawingLibrary {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Drawings/drawings.json")
        return try #require(DrawingLibrary.decode(Data(contentsOf: file)))
    }

    @Test("Every drawing in the shipped set reads as layers")
    func everyDrawingReads() throws {
        let library = try Self.shipped()
        #expect(library.entries.count > 900)
        var broken: [String] = []
        for entry in library.entries {
            guard case .success(let drawing) = entry.drawing(), !drawing.bounds.isNull else {
                broken.append(entry.name)
                continue
            }
        }
        #expect(broken.isEmpty, "\(broken.count) drawings do not read: \(broken.prefix(10))")
    }

    @Test("The everyday things people ask for are in the shipped set",
          arguments: [("dog", "dog"), ("smiley face", "slightly smiling face"), ("cat", "cat"), ("house", "house"),
                      ("tree", "deciduous tree"), ("car", "automobile"), ("bicycle", "bicycle"),
                      ("coffee cup", "hot beverage"), ("fish", "fish"), ("bird", "bird"), ("rocket", "rocket"),
                      ("flower", "blossom"), ("sun over mountains", "sunrise over mountains"),
                      ("heart", "red heart"), ("pizza", "pizza"), ("airplane", "airplane")])
    func everydayThings(subject: String, expected: String) throws {
        #expect(try Self.shipped().match(subject)?.name == expected)
    }

    @Test("Every face in the shipped set that has two eyes and a mouth has them named")
    func shippedFaces() throws {
        let smile = try #require(try Self.shipped().match("smiley"))
        let names = try smile.drawing().get().parts.compactMap(\.name)
        #expect(names.contains("Face") && names.contains("Left eye") && names.contains("Right eye") && names.contains("Mouth"))
    }
}

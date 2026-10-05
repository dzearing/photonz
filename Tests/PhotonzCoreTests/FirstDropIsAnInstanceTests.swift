import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What a drag off the Library shelf hands you: an INSTANCE, every time, and
/// nothing else. The original goes into the document's component library, not
/// onto the canvas (the user, 2026-10-04: "how does 'always a copy' translate
/// into 'copy AND original'"; `ComponentLibraryTests`).
///
/// Chosen by the user on 2026-09-20 answering "When you drag a component onto
/// the canvas, should you get the original or a copy?" with "Always a copy",
/// and the note "An Instance, not a copy. Changes to the component change
/// instances, but you can right click and make unique?". Before this the FIRST
/// drop of any component landed the original itself, so what you clicked
/// depended on invisible history: drop a Button on a fresh document, click it,
/// and you got the authoring wall instead of the two rows a placed component
/// is for. That is the report this answers
/// (`a-copy-of-a-component-is-configured-not-authored`).
struct FirstDropIsAnInstanceTests {

    private func document(_ size: CGFloat = 1200) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: size, height: size), pixelScale: 1)
    }

    private let drop = CGPoint(x: 300, y: 300)

    // MARK: - One of the app's own starters

    @Test func theFirstDropOfAStarterIsAnInstance() {
        var doc = document()
        guard let placed = doc.insertStarterComponent(.button, at: drop) else {
            Issue.record("nothing placed"); return
        }
        #expect(doc.layer(id: placed)?.isComponentInstance == true)
        #expect(doc.layer(id: placed)?.isMainComponent == false)
        #expect(doc.mainComponents.count == 1)
        #expect(doc.instanceCount(of: StarterComponent.button.componentID) == 1)
    }

    /// The instance is the thing under your pointer, and the only thing the
    /// drop put on the canvas: the original is in the component library.
    @Test func theInstanceTakesTheDropAndTheOriginalStaysOffTheCanvas() {
        var doc = document()
        guard let placed = doc.insertStarterComponent(.button, at: drop),
              let main = doc.mainComponent(componentID: StarterComponent.button.componentID),
              let instanceBox = doc.canvasBounds(of: placed)
        else { Issue.record("nothing placed"); return }
        #expect(abs(instanceBox.midX - drop.x) <= 1)
        #expect(abs(instanceBox.midY - drop.y) <= 1)
        #expect(doc.layers.map(\.id) == [placed])
        #expect(doc.componentOriginals.map(\.id) == [main.id])
    }

    /// Everything the original used to arrive with still arrives: the named
    /// colors it paints from and the properties it offers.
    @Test func theOriginalStillArrivesWithItsStylesAndProperties() {
        var doc = document()
        doc.insertStarterComponent(.card, at: drop)
        #expect(doc.componentProperties(of: StarterComponent.card.componentID).map(\.name)
                == ["Title", "Body", "Picture"])
        let wanted = StarterComponent.card.usedStyles.map(\.name)
        #expect(!wanted.isEmpty)
        #expect(wanted.allSatisfy { name in doc.colorStyles.contains { $0.name == name } })
    }

    /// Dropping a second one is unchanged: another instance, still one
    /// original. What was history-dependent is now the same both times.
    @Test func theSecondDropIsAnotherInstanceAndTheOriginalIsNotDuplicated() {
        var doc = document()
        doc.insertStarterComponent(.button, at: drop)
        let second = doc.insertStarterComponent(.button, at: CGPoint(x: 800, y: 800))
        #expect(doc.mainComponents.count == 1)
        #expect(doc.layer(id: second ?? UUID())?.isComponentInstance == true)
        #expect(doc.instanceCount(of: StarterComponent.button.componentID) == 2)
    }

    /// Dropped into a group you have stepped inside, the INSTANCE joins the
    /// group and the original goes into the component library: a parts bin
    /// does not belong inside the bar you are arranging, or on the canvas.
    @Test func droppingIntoAGroupPutsTheInstanceInItAndTheOriginalInTheLibrary() {
        var doc = document()
        guard let barInstance = doc.insertStarterComponent(.navBar, at: CGPoint(x: 400, y: 200)),
              let barBox = doc.canvasBounds(of: barInstance)
        else { Issue.record("no nav bar"); return }
        let inside = CGPoint(x: barBox.midX, y: barBox.midY)
        guard let badge = doc.insertStarterComponent(.badge, at: inside, inside: barInstance)
        else { Issue.record("no badge"); return }
        // A badge dropped inside a bar is an instance of the badge...
        #expect(doc.layer(id: badge)?.isComponentInstance == true)
        // ...and the badge's ORIGINAL is in the library, not in the bar.
        guard let badgeMain = doc.mainComponent(componentID: StarterComponent.badge.componentID)
        else { Issue.record("no badge original"); return }
        #expect(doc.componentOriginals.contains { $0.id == badgeMain.id })
        #expect(!doc.allLayers.contains { $0.isMainComponent })
    }

    // MARK: - On a recording

    /// Dropped on a film, the copy gets the stretch of timeline the drop asked
    /// for, and nothing else lands on the film: the original is in the
    /// component library, so there is no parts bin standing over every frame.
    @Test func droppedOnARecordingOnlyTheCopyLandsOnTheFilm() {
        let canvas = CGSize(width: 1200, height: 800)
        let movie = MovieRef(pixelSize: canvas, durationMS: 8000)
        var clip = Layer(name: "Recording", content: .image(movie.frameRef(atSourceMS: 0)),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.movie = movie
        clip.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        var doc = PhotonzDocument(canvasSize: canvas, layers: [clip])
        doc.durationMS = 8000

        guard let placed = doc.insertStarterComponent(.button, at: drop, atTimeMS: 4000),
              let main = doc.mainComponent(componentID: StarterComponent.button.componentID)
        else { Issue.record("nothing placed"); return }
        #expect(doc.layer(id: placed)?.time?.inMS == 4000)
        #expect(main.id != placed)
        #expect(doc.layers.count == 2)
        #expect(!doc.allLayers.contains { $0.isMainComponent })
    }

    // MARK: - A component off the shared shelf

    @Test func theFirstDropOfASharedComponentIsAnInstance() {
        var source = document()
        source.insertStarterComponent(.button, at: drop)
        guard let shared = source.shareComponent(componentID: StarterComponent.button.componentID)
        else { Issue.record("nothing to publish"); return }

        var doc = document()
        guard let placed = doc.adoptSharedComponent(shared, at: drop) else {
            Issue.record("nothing placed"); return
        }
        #expect(doc.layer(id: placed)?.isComponentInstance == true)
        #expect(doc.mainComponents.count == 1)
        guard doc.mainComponent(componentID: shared.id) != nil,
              let instanceBox = doc.canvasBounds(of: placed)
        else { Issue.record("no original"); return }
        #expect(doc.layers.map(\.id) == [placed])
        #expect(abs(instanceBox.midX - drop.x) <= 1)
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Every main in a document is worked out once and kept until a layer or the
/// component library changes (`DocumentDerived`).
///
/// Why: putting every copy back in step with its original
/// (`syncComponentInstances`, after every edit) asked for the document's mains
/// several times per copy, and each answer was a walk of the whole tree. When
/// Ask landed a sheet of eleven components with their states (2026-11-18,
/// `find-out-whether-landing-a-component-sheet-holds`), that sync was about a
/// third of a 533 ms hold of the main thread, and it grew with the square of
/// the copies on the sheet.
struct MainComponentsKeptTests {

    private static func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// `kinds` components on the canvas, each with three versions, and
    /// `copies` copies spread over them, each showing one of the versions.
    private static func sheet(kinds: Int, copies: Int) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 4000, height: 4000), layers: [])
        var components: [(id: UUID, versions: [UUID])] = []
        for kind in 0..<kinds {
            let y = CGFloat(kind) * 80
            let a = box("Back \(kind)", CGRect(x: 10, y: y, width: 60, height: 30))
            let b = box("Label \(kind)", CGRect(x: 20, y: y + 5, width: 40, height: 20))
            doc.addLayer(a)
            doc.addLayer(b)
            guard let group = doc.groupLayers(ids: [a.id, b.id], name: "Kind \(kind)"),
                  let component = doc.makeComponent(id: group.id) else { continue }
            _ = doc.addComponentVersion(componentID: component, name: "Hover")
            _ = doc.addComponentVersion(componentID: component, name: "Disabled")
            components.append((component, doc.componentVersions(of: component).map(\.id)))
        }
        for index in 0..<copies {
            let (component, versions) = components[index % components.count]
            _ = doc.insertComponentInstance(of: component,
                                            at: CGPoint(x: 400 + CGFloat(index % 20) * 90,
                                                        y: 100 + CGFloat(index / 20) * 60),
                                            version: versions[index % versions.count])
        }
        doc.syncComponentInstances()
        return doc
    }

    @Test("The mains are kept, and a change to a layer or to the library is seen at once")
    func mainsKeptAndForgotten() throws {
        var doc = Self.sheet(kinds: 3, copies: 6)
        let first = doc.mainComponents
        #expect(first.count == 9)
        #expect(doc.derived.keptMainComponents?.map(\.id) == first.map(\.id))

        // A main renamed on the canvas: the next answer carries the new name.
        let renamed = try #require(first.first)
        doc.updateLayer(id: renamed.id) { $0.name = "Renamed" }
        #expect(doc.derived.keptMainComponents == nil)
        #expect(doc.mainComponents.first?.name == "Renamed")

        // A main moved into the library: the library is part of the answer,
        // so writing it starts the kept answers again.
        _ = doc.mainComponents
        var library = doc.componentOriginals
        library.append(Self.box("Loose", CGRect(x: 0, y: 0, width: 10, height: 10)))
        let promoted = try #require(doc.mainComponents.last)
        let moved = promoted.reidentified()
        #expect(moved.isMainComponent)
        library.append(moved)
        doc.componentOriginals = library
        #expect(doc.derived.keptMainComponents == nil)
        #expect(doc.mainComponents.first?.id == moved.id)
        #expect(doc.mainComponents.count == 10)
    }

    @Test("A copy of the document keeps its own mains once either is written to")
    func copiesKeepTheirOwn() throws {
        var doc = Self.sheet(kinds: 2, copies: 2)
        _ = doc.mainComponents
        var copy = doc
        let main = try #require(copy.mainComponents.first)
        copy.updateLayer(id: main.id) { $0.name = "Only in the copy" }
        #expect(copy.mainComponents.first?.name == "Only in the copy")
        #expect(doc.mainComponents.first?.name != "Only in the copy")
        doc.updateLayer(id: main.id) { $0.isVisible = false }
        #expect(doc.mainComponents.first?.isVisible == false)
        #expect(copy.mainComponents.first?.isVisible == true)
    }

    @Test("Putting copies in step costs in proportion to the copies, not their square")
    func syncGrowsWithTheCopies() {
        let small = Self.sheet(kinds: 6, copies: 24)
        let large = Self.sheet(kinds: 6, copies: 96)
        func cost(_ doc: PhotonzDocument) -> Double {
            var fastest = Double.infinity
            for _ in 0..<5 {
                var working = doc
                // A write first, as every edit makes one, so nothing the last
                // round worked out is still kept.
                working.updateLayer(id: working.layers[0].id) { $0.name += " " }
                let start = Self.threadCPUSeconds()
                working.syncComponentInstances()
                fastest = min(fastest, Self.threadCPUSeconds() - start)
            }
            return fastest
        }
        let a = cost(small), b = cost(large)
        let ratio = b / a
        print(String(format: "[perf] sync of 24 copies %.2fms, of 96 copies %.2fms, ratio %.1f",
                     a * 1000, b * 1000, ratio))
        // Four times the copies: about four times the work when each copy
        // costs the same, about sixteen when each copy walks the whole sheet.
        // Read from one machine at one moment, so a busy Mac moves both. It
        // read 8.9 before the mains were kept and 3.4 after (2026-11-18).
        #expect(ratio < 6)
    }

    private static func threadCPUSeconds() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
    }
}

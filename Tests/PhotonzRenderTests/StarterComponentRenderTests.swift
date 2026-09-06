import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The app's own components have to LOOK right, not just decode right: they
/// are the first thing anybody sees on the Library shelf
/// (`docs/design/ui-building.md`, step D7).
///
/// `PhotonzCore` cannot measure text, so a label's place inside its control is
/// only as good as the measurement the app hands it. These tests draw the real
/// thing with the real measurement and check where the ink lands.
@Suite("Starter component rendering")
struct StarterComponentRenderTests {

    private let measure: StarterTextMeasure = { TextRasterizer.naturalSize($0) }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return data }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// The starter drawn on its own, top-left at the origin.
    private func render(_ kind: StarterComponent, scale: CGFloat = 1) -> CGImage? {
        var main = StarterComponents.layer(kind, scale: scale, measure: measure)
        let box = main.localBounds
        main.frame.origin = .zero
        let document = PhotonzDocument(canvasSize: box.size, layers: [main])
        return DocumentRenderer().render(document, store: ImageStore())
    }

    /// The columns (top-left coordinates) where a row of pixels differs from
    /// the color at the far left of that row: the ink on top of the control.
    /// `within` narrows the search, which the nav bar needs — its back label
    /// shares a row with its title and would drag the middle to the left.
    private func inkColumns(_ image: CGImage, row: Int,
                            within: ClosedRange<CGFloat> = 0...1) -> [Int] {
        let data = rgba(image)
        func pixel(_ x: Int) -> [UInt8] {
            let offset = (row * image.width + x) * 4
            return Array(data[offset..<(offset + 4)])
        }
        let background = pixel(2)
        let window = Int(within.lowerBound * CGFloat(image.width))
            ..< Int(within.upperBound * CGFloat(image.width))
        return window.filter { x in
            zip(pixel(x), background).contains { abs(Int($0) - Int($1)) > 24 }
        }
    }

    @Test func everyStarterDrawsSomething() throws {
        for kind in StarterComponent.allCases {
            let image = try #require(render(kind), "\(kind.name) drew nothing")
            let data = rgba(image)
            let lit = stride(from: 3, to: data.count, by: 4).filter { data[$0] > 8 }.count
            #expect(lit > image.width * image.height / 4,
                    "\(kind.name) is mostly empty")
        }
    }

    /// A label that is off by ten points reads as a mistake, and nothing in
    /// the model can catch it: the numbers are all correct, the font is just
    /// not the width the estimate guessed.
    @Test func aCentredLabelIsActuallyCentred() throws {
        let cases: [(kind: StarterComponent, row: Int, window: ClosedRange<CGFloat>)] =
            [(.button, 18, 0...1), (.badge, 10, 0...1), (.navBar, 24, 0.3...0.7)]
        for (kind, row, window) in cases {
            let image = try #require(render(kind))
            let columns = inkColumns(image, row: row, within: window)
            guard let first = columns.first, let last = columns.last else {
                Issue.record("\(kind.name) has no label ink on row \(row)")
                continue
            }
            let middle = CGFloat(first + last) / 2
            #expect(abs(middle - CGFloat(image.width) / 2) <= 2,
                    "\(kind.name) label sits at \(middle) of \(image.width)")
        }
    }

    /// Nothing may hang outside the control it belongs to: a label wider than
    /// its button is the first sign the frame numbers are wrong.
    ///
    /// Measured on the box a person SEES. A measured text box carries a few
    /// points of slack on its far edges for the antialiased glyph edges to
    /// round into, and a label told to span its container has that slack
    /// sitting past the container's own edge with nothing drawn in it: the
    /// nav bar's title is exactly that. Counting it would fail every bar in
    /// the app over four transparent points.
    @Test func nothingSpillsOutOfItsControl() throws {
        for kind in StarterComponent.allCases {
            let layer = StarterComponents.layer(kind, measure: measure)
            let box = layer.localBounds
            for child in layer.children {
                let seen = child.contentBounds
                #expect(box.contains(seen.integral.insetBy(dx: 0.5, dy: 0.5)),
                        "\(kind.name) / \(child.name) at \(seen) leaves \(box)")
            }
        }
    }

    /// The same drawing at twice the size, for a Retina capture, not a
    /// stretched copy of the one-to-one one.
    ///
    /// The button closes around its label, and the system face is not exactly
    /// twice as wide at twice the point size (it is optically sized), so twice
    /// the button is within a few percent of twice as wide rather than exactly
    /// it. Its height is a number it was given, so that IS exactly double.
    @Test func aRetinaDocumentDrawsThemAtTwiceTheSize() throws {
        let one = try #require(render(.button, scale: 1))
        let two = try #require(render(.button, scale: 2))
        #expect(two.height == one.height * 2)
        #expect(abs(two.width - one.width * 2) <= one.width / 10)
    }

    /// A contact sheet of all five, for looking at rather than asserting on.
    /// Off unless asked for, so the suite writes nothing in the normal run.
    @Test func writesAContactSheetWhenAsked() throws {
        guard let directory = ProcessInfo.processInfo.environment["PHOTONZ_STARTER_SHEET"]
        else { return }
        for kind in StarterComponent.allCases {
            guard let image = render(kind, scale: 2) else { continue }
            let url = URL(fileURLWithPath: directory)
                .appendingPathComponent("starter-\(kind.rawValue).png")
            try ImageCodec.encode(image, format: .png)?.write(to: url)
        }
    }
}

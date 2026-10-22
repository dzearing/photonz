import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A colour set on a drawing's group recolours the drawing ("make the cat
/// black"): its main colour becomes the one asked for, every other part keeps
/// how much lighter or darker it was, and no detail sinks into the main colour.
@Suite("A fill on a group recolours what it holds")
struct AgentGroupRecolourTests {

    /// A body, a stripe on it and a dark eye: the shape of any traced drawing.
    static let svg = """
        <svg viewBox="0 0 100 100">
        <path id="Body" d="M0 0 L100 0 L100 100 L0 100 Z" fill="#E8A050"/>
        <path id="Stripe" d="M10 10 L60 10 L60 30 L10 30 Z" fill="#B86A20"/>
        <path id="Eye" d="M70 70 L78 70 L78 78 L70 78 Z" fill="#2A1508"/>
        </svg>
        """

    static func group() throws -> Layer {
        guard case .success(let art) = SVGArtwork.parse(svg) else { throw AgentToolError("svg did not parse") }
        return art.group(named: "Cat", fitting: CGRect(x: 0, y: 0, width: 400, height: 400))
    }

    static func fills(_ layer: Layer) -> [String: String] {
        var out: [String: String] = [:]
        for child in layer.group?.children ?? [] {
            if let hex = child.path?.fill?.hex { out[child.name] = hex }
        }
        return out
    }

    static func lightness(_ hex: String) -> Double {
        let rgb = AgentGroupRecolour.rgb(hex)
        return (max(rgb.r, rgb.g, rgb.b) + min(rgb.r, rgb.g, rgb.b)) / 2
    }

    @Test("Make it black: the body is black and the eye still shows against it")
    func black() throws {
        let made = AgentDrawing.applying(AgentLayerChange(look: AgentLook(fill: .hex("#000000"))),
                                         to: try Self.group(), canvas: nil)
        guard case .success(let recoloured) = made else {
            Issue.record("refused: \(made)")
            return
        }
        let fills = Self.fills(recoloured)
        #expect(Self.lightness(fills["Body"] ?? "#FFFFFF") < 0.08)
        #expect(abs(Self.lightness(fills["Eye"] ?? "#000000") - Self.lightness(fills["Body"] ?? "#000000")) >= 0.1)
        #expect(abs(Self.lightness(fills["Stripe"] ?? "#000000") - Self.lightness(fills["Body"] ?? "#000000")) >= 0.1)
    }

    @Test("Make it blue: the body takes the blue asked for, the stripe stays darker than it")
    func blue() throws {
        let made = AgentDrawing.applying(AgentLayerChange(look: AgentLook(fill: .hex("#3070E0"))),
                                         to: try Self.group(), canvas: nil)
        guard case .success(let recoloured) = made else {
            Issue.record("refused: \(made)")
            return
        }
        let fills = Self.fills(recoloured)
        #expect(fills["Body"] == "#3070E0")
        let body = AgentGroupRecolour.rgb(fills["Body"] ?? "#000000")
        let stripe = AgentGroupRecolour.rgb(fills["Stripe"] ?? "#000000")
        #expect(stripe.b > stripe.r)
        #expect(Self.lightness(fills["Stripe"] ?? "#FFFFFF") < Self.lightness(fills["Body"] ?? "#000000"))
        #expect(body.b > body.r)
    }

    @Test("The main colour is the one covering the most, not the first part")
    func mainColourIsTheLargest() throws {
        var group = try Self.group()
        // Move the eye to the bottom of the stack; the body still covers most.
        if var content = group.group {
            content.children.reverse()
            group.content = .group(content)
        }
        let main = AgentGroupRecolour.mainColour(of: group)
        #expect(main == "#E8A050")
    }

    @Test("A traced drawing's outline is a dark silhouette under the body: the body is the main colour")
    func outlineUnderneathIsNotMain() throws {
        let stacked = """
            <svg viewBox="0 0 100 100">
            <path id="Outline" d="M0 0 L100 0 L100 100 L0 100 Z" fill="#3A2010"/>
            <path id="Body" d="M6 6 L94 6 L94 94 L6 94 Z" fill="#F2C080"/>
            </svg>
            """
        guard case .success(let art) = SVGArtwork.parse(stacked) else { throw AgentToolError("svg did not parse") }
        let group = art.group(named: "Cat", fitting: CGRect(x: 50, y: 80, width: 300, height: 300))
        #expect(AgentGroupRecolour.mainColour(of: group) == "#F2C080")
    }
}

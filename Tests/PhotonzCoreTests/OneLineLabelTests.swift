import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A label that stays on one line never grows a second one, whatever the
/// container around it decides about its width
/// (`docs/design/ui-building.md`, "A title stays on one line").
///
/// The complaint this answers: type a long title into the starter Nav Bar and
/// the words wrap onto a second line that hangs out of the bottom of the bar,
/// straight through its hairline. A bar is 48 points tall because a bar is 48
/// points tall; its title has nothing to say about that.
@Suite("A label that stays on one line never grows a second one")
struct OneLineLabelTests {

    // MARK: - Building blocks

    private func words(_ string: String, oneLine: Bool, at x: CGFloat = 0,
                       _ y: CGFloat = 0) -> Layer {
        var content = TextContent(string: string, fontSize: 10)
        content.staysOnOneLine = oneLine ? true : nil
        let size = TextMeasurement.size(of: content)
        return Layer(name: "Label", content: .text(content),
                     frame: CGRect(origin: CGPoint(x: x, y: y), size: size))
    }

    private func group(_ children: [Layer], layout: GroupLayout) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        return Layer(name: "Group", content: .group(content), frame: .zero)
    }

    private func piece(_ layer: Layer, _ name: String) -> CGRect {
        layer.children.first { $0.name == name }?.frame.standardized ?? .null
    }

    /// How tall one line of these words is, which is what "it did not wrap"
    /// looks like.
    private var oneLine: CGFloat {
        TextMeasurement.size(of: TextContent(string: "x", fontSize: 10)).height
    }

    /// The starter bar with a different title in it, exactly as retitling one
    /// on the canvas leaves it: new words, the box back at their natural size,
    /// and the flow asked for its answer.
    private func navBar(titled title: String) -> Layer {
        var bar = StarterComponents.layer(.navBar)
        bar.children = bar.children.map { child in
            guard child.name == "Title", case .text(var content) = child.content
            else { return child }
            content.string = title
            var out = child
            out.content = .text(content)
            out.frame = CGRect(origin: child.frame.standardized.origin,
                               size: TextMeasurement.size(of: content))
            return out
        }
        return GroupFlow.flowing(bar)
    }

    // MARK: - The bar

    @Test("A bar title too long for the room left stays on one line")
    func aLongBarTitleStaysOnOneLine() {
        let short = piece(navBar(titled: "Inbox"), "Title")
        let long = piece(navBar(titled: "A very long navigation bar title indeed"), "Title")
        #expect(long.height == short.height)
        // And it sits exactly where the short one did: same line, same place
        // down the bar, only the words are longer.
        #expect(long.minY == short.minY)
    }

    @Test("Nothing the bar draws hangs below the bar itself")
    func nothingHangsBelowTheBar() {
        let bar = navBar(titled: "A very long navigation bar title indeed")
        let box = bar.localBounds
        #expect(box.height == 48)
        for child in bar.children {
            #expect(child.contentBounds.maxY <= box.maxY,
                    "\(child.name) hangs \(child.contentBounds.maxY - box.maxY) below the bar")
        }
    }

    @Test("A short bar title is unchanged")
    func aShortBarTitleIsUnchanged() {
        let plain = StarterComponents.layer(.navBar)
        let same = navBar(titled: "Title")
        #expect(piece(same, "Title") == piece(plain, "Title"))
        #expect(piece(same, "Back") == piece(plain, "Back"))
        #expect(same.localBounds == plain.localBounds)
    }

    @Test("The title takes the room the back label leaves and no more")
    func theTitleTakesTheRoomLeft() {
        let bar = navBar(titled: "A very long navigation bar title indeed")
        let title = piece(bar, "Title")
        let back = piece(bar, "Back")
        #expect(title.minX >= back.maxX)
        #expect(title.maxX - TextMeasurement.slack <= bar.localBounds.maxX - 14)
    }

    // MARK: - The rule underneath it

    @Test("A container that would wrap a label leaves a one-line one alone")
    func aContainerLeavesAOneLineLabelAlone() {
        var layout = GroupLayout(kind: .stack, direction: .column, padding: GroupPadding(10))
        layout.width = 100
        let wrapping = GroupFlow.flowing(group([words("Save all the changes", oneLine: false)],
                                               layout: layout))
        let held = GroupFlow.flowing(group([words("Save all the changes", oneLine: true)],
                                           layout: layout))
        #expect(piece(wrapping, "Label").height > oneLine)
        #expect(piece(held, "Label").height == oneLine)
    }

    @Test("A one-line label handed a narrower box keeps its one line")
    func aNarrowerBoxKeepsOneLine() {
        let label = words("Save all the changes", oneLine: true)
        let narrow = label.resized(to: CGRect(x: 0, y: 0, width: 60, height: 40),
                                   placedByContainer: true)
        #expect(narrow.frame.standardized.width == 60)
        #expect(narrow.frame.standardized.height == oneLine)
    }

    @Test("Words that stay on one line measure as one line however narrow the room")
    func measuringIgnoresTheRoom() {
        var content = TextContent(string: "Save all the changes", fontSize: 10)
        content.staysOnOneLine = true
        #expect(TextMeasurement.size(of: content, wrappingAt: 40)
                == TextMeasurement.size(of: content))
    }

    @Test("Staying on one line survives being saved and opened again")
    func itSurvivesARoundTrip() throws {
        var content = TextContent(string: "Title", fontSize: 10)
        content.staysOnOneLine = true
        let data = try JSONEncoder().encode(content)
        #expect(try JSONDecoder().decode(TextContent.self, from: data).staysOnOneLine == true)
        // Text written before this existed wraps exactly as it always did.
        var plain = content
        plain.staysOnOneLine = nil
        let old = try JSONEncoder().encode(plain)
        #expect(try JSONDecoder().decode(TextContent.self, from: old).staysOnOneLine == nil)
    }
}

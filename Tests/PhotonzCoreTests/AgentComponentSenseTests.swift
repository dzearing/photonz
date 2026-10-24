import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// What Ask's planner sets right in a component before it is built: looks
/// that say the opposite of their state's name, words off one type scale, an
/// empty box and words that measure into each other (judges of the eval,
/// 2026-10-24: an Off checkbox with its tick, a blue Off switch, a Disabled
/// field darker than its Default, eight type sizes, empty cards, "BackNavigation").
@Suite("Agent add_component: looks that mean their state")
struct AgentComponentSenseTests {

    static func plain(_ json: String) throws -> AgentNewComponent {
        let made = AgentNewComponent.madePlain(try AgentJSON.parse(Data(json.utf8)))
        switch AgentTools.request(tool: "add_component", arguments: made) {
        case .success(.addComponent(_, let spec)): return spec
        case .failure(let error): throw error
        default: throw AgentToolError("not add_component")
        }
    }

    static func part(_ name: String, in spec: AgentNewComponent, look: String) -> AgentComponentPart? {
        guard let found = spec.looks.first(where: { $0.name == look }) else { return nil }
        return spec.inLook(found).parts.first { $0.name == name }
    }

    @Test("An Off checkbox drawn with its tick shows no tick; On and On Disabled still show it")
    func offHasNoTick() throws {
        let spec = try Self.plain(##"""
            {"name": "Checkbox", "x": 0, "y": 0, "labels": true, "firstLook": "Off",
             "parts": [{"name": "Box", "shape": "rectangle", "x": 0, "y": 0, "width": 22, "height": 22, "cornerRadius": 6, "fill": "#FFFFFF", "stroke": "#C7C7CC", "strokeWidth": 1},
                       {"name": "Check", "shape": "path", "x": 0, "y": 0, "width": 22, "height": 22, "points": [{"x": 6, "y": 11}, {"x": 10, "y": 15}, {"x": 16, "y": 7}], "stroke": "#1C1C1E", "strokeWidth": 2}],
             "looks": [{"name": "On", "changes": [{"part": "Box", "fill": "#007AFF", "stroke": "#007AFF"}, {"part": "Check", "stroke": "#FFFFFF"}]},
                       {"name": "On Disabled", "changes": [{"part": "Box", "fill": "#007AFF", "opacity": 0.4}]}]}
            """##)
        #expect(Self.part("Check", in: spec, look: "Off")?.hidden == true)
        #expect(Self.part("Check", in: spec, look: "On")?.hidden == false)
        #expect(Self.part("Check", in: spec, look: "On Disabled")?.hidden == false)
        #expect(spec.problem == nil)
    }

    @Test("A first look called Default beside one called Checked is the Off look: its tick is hidden")
    func defaultBesideChecked() throws {
        // The eval, 2026-10-24, read off the trace: "Default" and "Checked",
        // and every judge read the Default box as already ticked.
        let spec = try Self.plain(##"""
            {"name": "Checkbox", "x": 40, "y": 800, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Box", "shape": "rectangle", "x": 0, "y": 0, "width": 20, "height": 20, "cornerRadius": 4, "fill": "#FFFFFF", "stroke": "#D1D1D6", "strokeWidth": 1},
                       {"name": "Check", "shape": "path", "closed": false, "x": 0, "y": 0, "width": 20, "height": 20, "points": [{"x": 4, "y": 10}, {"x": 8, "y": 14}, {"x": 16, "y": 6}]},
                       {"name": "Label", "shape": "text", "text": "Option", "fontSize": 15, "x": 28, "y": 0, "width": 100, "height": 20, "color": "#1C1C1E"}],
             "looks": [{"name": "Checked", "changes": [{"part": "Box", "fill": "#007AFF", "stroke": "#007AFF"}, {"part": "Check", "stroke": "#FFFFFF"}]}]}
            """##)
        #expect(Self.part("Check", in: spec, look: "Default")?.hidden == true)
        #expect(Self.part("Check", in: spec, look: "Checked")?.hidden == false)
        // Default beside Selected (a tab) is not an Off look.
        let tab = try Self.plain(##"""
            {"name": "Tab", "x": 40, "y": 800, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 80, "height": 32, "fill": "#007AFF"},
                       {"name": "Chevron", "shape": "path", "closed": false, "x": 60, "y": 10, "width": 10, "height": 12, "stroke": "#FFFFFF", "points": [{"x": 0, "y": 0}, {"x": 6, "y": 6}, {"x": 0, "y": 12}]}],
             "looks": [{"name": "Selected", "changes": [{"part": "Back", "fill": "#0040DD"}]}]}
            """##)
        #expect(Self.part("Chevron", in: tab, look: "Default")?.hidden == false)
        #expect(Self.part("Back", in: tab, look: "Default")?.look.fill?.hexValue == "#007AFF")
    }

    @Test("An Off look given later hides the tick in that look only")
    func laterOffHidesTick() throws {
        let spec = try Self.plain(##"""
            {"name": "Checkbox", "x": 0, "y": 0, "labels": true, "firstLook": "Checked",
             "parts": [{"name": "Box", "shape": "rectangle", "x": 0, "y": 0, "width": 22, "height": 22, "fill": "#007AFF"},
                       {"name": "Check", "shape": "path", "x": 0, "y": 0, "width": 22, "height": 22, "points": [{"x": 6, "y": 11}, {"x": 10, "y": 15}, {"x": 16, "y": 7}], "stroke": "#FFFFFF", "strokeWidth": 2}],
             "looks": [{"name": "Unchecked", "changes": [{"part": "Box", "fill": "#FFFFFF", "stroke": "#C7C7CC", "strokeWidth": 1}]}]}
            """##)
        #expect(Self.part("Check", in: spec, look: "Checked")?.hidden == false)
        #expect(Self.part("Check", in: spec, look: "Unchecked")?.hidden == true)
    }

    @Test("An Off switch with a blue or near black track gets the off grey; On keeps its colour")
    func offTrackIsGrey() throws {
        for track in ["#007AFF", "#3A3A3C"] {
            let spec = try Self.plain(##"""
                {"name": "Switch", "x": 0, "y": 0, "labels": true, "firstLook": "Off",
                 "parts": [{"name": "Track", "shape": "rectangle", "x": 0, "y": 0, "width": 51, "height": 31, "cornerRadius": 15.5, "fill": "\##(track)"},
                           {"name": "Knob", "shape": "ellipse", "x": 2, "y": 2, "width": 27, "height": 27, "fill": "#FFFFFF"}],
                 "looks": [{"name": "On", "changes": [{"part": "Knob", "x": 22}]}]}
                """##)
            #expect(Self.part("Track", in: spec, look: "Off")?.look.fill?.hexValue == AgentNewComponent.offTrack, "\(track)")
            #expect(Self.part("Track", in: spec, look: "On")?.look.fill?.hexValue == track, "On keeps \(track)")
        }
        // An Off already grey, and a component with no On, are left as drawn.
        let grey = try Self.plain(##"""
            {"name": "Switch", "x": 0, "y": 0, "labels": true, "firstLook": "Off",
             "parts": [{"name": "Track", "shape": "rectangle", "x": 0, "y": 0, "width": 51, "height": 31, "fill": "#E5E5EA"},
                       {"name": "Knob", "shape": "ellipse", "x": 2, "y": 2, "width": 27, "height": 27, "fill": "#FFFFFF"}],
             "looks": [{"name": "On", "changes": [{"part": "Track", "fill": "#34C759"}, {"part": "Knob", "x": 22}]}]}
            """##)
        #expect(grey.parts[0].look.fill?.hexValue == "#E5E5EA")
        let button = try Self.plain(##"""
            {"name": "Button", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 120, "height": 40, "fill": "#007AFF"},
                       {"name": "Label", "shape": "text", "text": "Go", "fontSize": 15, "x": 0, "y": 0, "width": 0, "height": 0, "centerIn": "Back", "color": "#FFFFFF"}],
             "looks": [{"name": "Pressed", "changes": [{"part": "Back", "fill": "#0056CC"}]}]}
            """##)
        #expect(button.parts[0].look.fill?.hexValue == "#007AFF")
    }

    @Test("An Off track drawn blue with an edge of nothing is still given the off grey")
    func offTrackWithEdge() throws {
        let spec = try Self.plain(##"""
            {"name": "Toggle", "x": 40, "y": 600, "labels": true, "firstLook": "Off",
             "parts": [{"name": "Track", "shape": "rectangle", "x": 0, "y": 0, "width": 51, "height": 31, "cornerRadius": 15.5, "fill": "#0A84FF", "stroke": "#0A84FF", "strokeWidth": 0},
                       {"name": "Knob", "shape": "ellipse", "x": 2, "y": 2, "width": 27, "height": 27, "fill": "#FFFFFF", "stroke": "#FFFFFF", "strokeWidth": 0}],
             "looks": [{"name": "On", "changes": [{"part": "Track", "fill": "#34C759"}, {"part": "Knob", "x": 22}]}]}
            """##)
        #expect(Self.part("Track", in: spec, look: "Off")?.look.fill?.hexValue == AgentNewComponent.offTrack)
        #expect(Self.part("Track", in: spec, look: "On")?.look.fill?.hexValue == "#34C759")
    }

    @Test("An Off track drawn as a closed path, under a bigger box nobody sees, or with no paint at all is still given the off grey")
    func offTrackAnyShape() throws {
        // The eval, 2026-10-24: a blue Off toggle the rectangle-only check
        // let through, twice.
        let path = try Self.plain(##"""
            {"name": "Toggle", "x": 40, "y": 600, "labels": true, "firstLook": "Off",
             "parts": [{"name": "Track", "shape": "path", "closed": true, "x": 0, "y": 0, "width": 51, "height": 31, "fill": "#007AFF",
                        "points": [{"x": 0, "y": 0}, {"x": 51, "y": 0}, {"x": 51, "y": 31}, {"x": 0, "y": 31}]},
                       {"name": "Knob", "shape": "ellipse", "x": 2, "y": 2, "width": 27, "height": 27, "fill": "#FFFFFF"}],
             "looks": [{"name": "On", "changes": [{"part": "Track", "fill": "#34C759"}, {"part": "Knob", "x": 22}]}]}
            """##)
        #expect(Self.part("Track", in: path, look: "Off")?.look.fill?.hexValue == AgentNewComponent.offTrack)
        #expect(Self.part("Track", in: path, look: "On")?.look.fill?.hexValue == "#34C759")
        let framed = try Self.plain(##"""
            {"name": "Toggle", "x": 40, "y": 600, "labels": true, "firstLook": "Off",
             "parts": [{"name": "Hit Area", "shape": "rectangle", "x": 0, "y": 0, "width": 60, "height": 36, "opacity": 0},
                       {"name": "Track", "shape": "rectangle", "x": 4, "y": 2, "width": 51, "height": 31, "cornerRadius": 15.5, "fill": "#007AFF"},
                       {"name": "Knob", "shape": "ellipse", "x": 6, "y": 4, "width": 27, "height": 27, "fill": "#FFFFFF"}],
             "looks": [{"name": "On", "changes": [{"part": "Knob", "x": 26}]}]}
            """##)
        #expect(Self.part("Track", in: framed, look: "Off")?.look.fill?.hexValue == AgentNewComponent.offTrack)
        #expect(Self.part("Track", in: framed, look: "On")?.look.fill?.hexValue == "#007AFF", "On keeps its blue")
        // A track given no paint at all is drawn in the default blue (the
        // eval, 2026-10-24, read off the trace: "Track" with no fill).
        let unpainted = try Self.plain(##"""
            {"name": "Toggle Switch", "x": 40, "y": 600, "labels": true, "firstLook": "Off",
             "parts": [{"name": "Track", "shape": "rectangle", "x": 0, "y": 0, "width": 52, "height": 32, "cornerRadius": 16},
                       {"name": "Knob", "shape": "ellipse", "x": 2, "y": 2, "width": 28, "height": 28, "fill": "#FFFFFF", "stroke": "#D1D1D6", "strokeWidth": 1}],
             "looks": [{"name": "On", "changes": [{"part": "Track", "fill": "#34C759"}, {"part": "Knob", "x": 22}]}]}
            """##)
        #expect(Self.part("Track", in: unpainted, look: "Off")?.look.fill?.hexValue == AgentNewComponent.offTrack)
        #expect(Self.part("Track", in: unpainted, look: "On")?.look.fill?.hexValue == "#34C759")
    }

    @Test("Boxes hanging past the card they sit in grow the card to hold them, with the room it leaves elsewhere")
    func cardHoldsItsButtons() throws {
        // The eval, 2026-10-24: an alert's OK and Cancel hanging under its card.
        let spec = try Self.plain(##"""
            {"name": "Alert", "x": 40, "y": 600, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Card", "shape": "rectangle", "x": 0, "y": 0, "width": 280, "height": 120, "cornerRadius": 12, "fill": "#FFFFFF", "stroke": "#D1D1D6", "strokeWidth": 1},
                       {"name": "Title", "shape": "text", "text": "Alert Title", "fontSize": 17, "x": 20, "y": 20, "width": 240, "height": 22},
                       {"name": "OK", "shape": "rectangle", "x": 20, "y": 100, "width": 110, "height": 36, "fill": "#007AFF"},
                       {"name": "Cancel", "shape": "rectangle", "x": 150, "y": 100, "width": 110, "height": 36, "fill": "#E5E5EA"}],
             "looks": [{"name": "Hover", "changes": [{"part": "OK", "fill": "#0062CC"}]}]}
            """##)
        let card = try #require(spec.parts.first { $0.name == "Card" })
        #expect(card.frame == CGRect(x: 0, y: 0, width: 280, height: 156), "\(card.frame)")
        // A card already holding its buttons is left as drawn.
        let held = try Self.plain(##"""
            {"name": "Alert", "x": 40, "y": 600, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Card", "shape": "rectangle", "x": 0, "y": 0, "width": 280, "height": 160, "fill": "#F2F2F7"},
                       {"name": "OK", "shape": "rectangle", "x": 20, "y": 100, "width": 110, "height": 36, "fill": "#007AFF"}],
             "looks": [{"name": "Hover", "changes": [{"part": "OK", "fill": "#0062CC"}]}]}
            """##)
        #expect(held.parts[0].frame.height == 160)
    }

    @Test("Words half over a drawn icon are refused, as words half over a box are")
    func wordsHalfOnIcon() throws {
        do {
            _ = try AgentComponentTests.spec(##"""
                {"name": "Tab", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
                 "parts": [{"name": "Icon", "shape": "path", "closed": true, "x": 0, "y": 0, "width": 24, "height": 24, "fill": "#007AFF",
                            "points": [{"x": 0, "y": 0}, {"x": 24, "y": 12}, {"x": 0, "y": 24}]},
                           {"name": "Name", "shape": "text", "text": "Search", "fontSize": 11, "x": -6, "y": 16, "width": 40, "height": 14}],
                 "looks": [{"name": "Selected", "changes": [{"part": "Icon", "fill": "#0040DD"}]}]}
                """##)
            Issue.record("words half over the icon were let through")
        } catch {
            #expect(error.localizedDescription.contains("edge of Icon"), "\(error)")
        }
    }

    @Test("An Off radio drawn with its dot shows none, and an On switch drawn with its knob still at the off end has it moved over")
    func onIsNotOff() throws {
        // The eval, 2026-10-24: "the Off radio is already selected", "the On
        // toggle keeps its knob on the left".
        let radio = try Self.plain(##"""
            {"name": "Radio", "x": 40, "y": 600, "labels": true, "firstLook": "Off",
             "parts": [{"name": "Ring", "shape": "ellipse", "x": 0, "y": 0, "width": 20, "height": 20, "fill": "#FFFFFF", "stroke": "#C7C7CC", "strokeWidth": 1},
                       {"name": "Dot", "shape": "ellipse", "x": 6, "y": 6, "width": 8, "height": 8, "fill": "#007AFF"}],
             "looks": [{"name": "On", "changes": [{"part": "Ring", "stroke": "#007AFF"}]}]}
            """##)
        #expect(Self.part("Dot", in: radio, look: "Off")?.hidden == true)
        #expect(Self.part("Dot", in: radio, look: "On")?.hidden == false)
        let toggle = try Self.plain(##"""
            {"name": "Toggle", "x": 40, "y": 600, "labels": true, "firstLook": "Off",
             "parts": [{"name": "Track", "shape": "rectangle", "x": 0, "y": 0, "width": 51, "height": 31, "cornerRadius": 15.5, "fill": "#E9E9EA"},
                       {"name": "Knob", "shape": "ellipse", "x": 2, "y": 2, "width": 27, "height": 27, "fill": "#FFFFFF"}],
             "looks": [{"name": "On", "changes": [{"part": "Track", "fill": "#34C759"}]}]}
            """##)
        #expect(Self.part("Knob", in: toggle, look: "Off")?.frame.minX == 2)
        #expect(Self.part("Knob", in: toggle, look: "On")?.frame.minX == 22)
        #expect(Self.part("Knob", in: toggle, look: "On")?.hidden == false, "a knob is moved, never hidden")
        // A knob the model already moved is left where it put it.
        let moved = try Self.plain(##"""
            {"name": "Toggle", "x": 40, "y": 600, "labels": true, "firstLook": "Off",
             "parts": [{"name": "Track", "shape": "rectangle", "x": 0, "y": 0, "width": 51, "height": 31, "fill": "#E9E9EA"},
                       {"name": "Knob", "shape": "ellipse", "x": 2, "y": 2, "width": 27, "height": 27, "fill": "#FFFFFF"}],
             "looks": [{"name": "On", "changes": [{"part": "Track", "fill": "#34C759"}, {"part": "Knob", "x": 21}]}]}
            """##)
        #expect(Self.part("Knob", in: moved, look: "On")?.frame.minX == 21)
    }

    @Test("A tick drawn in the colour of the box it sits on is set white or near black, whichever shows")
    func markStandsOut() throws {
        // The walk, 2026-10-24: a blue tick on the blue box of an On checkbox.
        let spec = try Self.plain(##"""
            {"name": "Checkbox", "x": 664, "y": 96, "labels": true, "firstLook": "Off",
             "parts": [{"name": "Box", "shape": "rectangle", "x": 0, "y": 0, "width": 20, "height": 20, "cornerRadius": 4, "fill": "#FFFFFF", "stroke": "#8E8E93", "strokeWidth": 1},
                       {"name": "Check", "shape": "path", "closed": false, "x": 0, "y": 0, "width": 20, "height": 20, "stroke": "#007AFF", "strokeWidth": 2,
                        "points": [{"x": 4, "y": 10}, {"x": 8, "y": 14}, {"x": 16, "y": 6}]}],
             "looks": [{"name": "On", "changes": [{"part": "Box", "fill": "#007AFF", "stroke": "#007AFF"}, {"part": "Check", "visible": true}]}]}
            """##)
        #expect(Self.part("Check", in: spec, look: "On")?.look.stroke?.hexValue == "#FFFFFF")
        #expect(Self.part("Check", in: spec, look: "On")?.hidden == false)
        #expect(Self.part("Check", in: spec, look: "Off")?.hidden == true)
    }

    @Test("A Disabled look whose words stand out more than Default's is dimmed, and still reads")
    func disabledIsDimmer() throws {
        let spec = try Self.plain(##"""
            {"name": "Field", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 160, "height": 36, "cornerRadius": 8, "fill": "#F2F2F7"},
                       {"name": "Text", "shape": "text", "text": "Placeholder", "fontSize": 15, "x": 12, "y": 8, "width": 0, "height": 0, "color": "#8E8E93"}],
             "looks": [{"name": "Disabled", "changes": [{"part": "Back", "fill": "#E5E5EA"}, {"part": "Text", "color": "#1C1C1E"}]}]}
            """##)
        let first = try #require(spec.parts.last), disabled = try #require(Self.part("Text", in: spec, look: "Disabled"))
        let read = { (hex: String?, ground: String) in
            abs(RGBA.lightnessContrast(text: RGBA(hex: hex ?? "") ?? RGBA(r: 0, g: 0, b: 0), on: RGBA(hex: ground) ?? RGBA(r: 1, g: 1, b: 1)))
        }
        #expect(read(disabled.colorHex, "#E5E5EA") <= read(first.colorHex, "#F2F2F7"), "\(disabled.colorHex ?? "")")
        #expect(read(disabled.colorHex, "#E5E5EA") >= AgentNewComponent.leastWordLightness)
        #expect(spec.problem == nil)
    }

    @Test("Words on a planned component are set on one type scale")
    func oneTypeScale() throws {
        let spec = try Self.plain(##"""
            {"name": "Tab", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 200, "height": 80, "fill": "#F2F2F7"},
                       {"name": "Small", "shape": "text", "text": "Tab", "fontSize": 10, "x": 10, "y": 4, "width": 0, "height": 0},
                       {"name": "Mid", "shape": "text", "text": "Body", "fontSize": 14, "x": 10, "y": 24, "width": 0, "height": 0},
                       {"name": "Big", "shape": "text", "text": "Title", "fontSize": 22, "x": 10, "y": 48, "width": 0, "height": 0}],
             "looks": [{"name": "Selected", "changes": [{"part": "Small", "color": "#007AFF"}]}]}
            """##)
        let sizes = Set(spec.looks.flatMap { look in spec.inLook(look).parts.compactMap(\.fontSize) })
        #expect(sizes.isSubset(of: Set(AgentNewComponent.typeScale.map { CGFloat($0) })), "\(sizes.sorted())")
    }

    @Test("A component drawn as one big box with nothing in it is refused, saying what to put in it")
    func emptyBox() throws {
        let empty = ##"""
            {"name": "Card", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 280, "height": 200, "cornerRadius": 12, "fill": "#FFFFFF", "stroke": "#E5E5EA", "strokeWidth": 1}],
             "looks": [{"name": "Hover", "changes": [{"part": "Background", "stroke": "#007AFF"}]}]}
            """##
        guard case .failure(let refused) = try AgentComponentTests.request(empty) else { Issue.record("accepted an empty card"); return }
        #expect(refused.message.contains("empty"), "\(refused.message)")
        // A small one-box control (a chip, a swatch) is not a card.
        let chip = empty.replacingOccurrences(of: #""width": 280, "height": 200"#, with: #""width": 60, "height": 24"#)
        #expect(throws: Never.self) { _ = try AgentComponentTests.request(chip).get() }
    }

    @Test("A back label at the left and a centred title that would measure into each other are words on words")
    func backOverTitle() throws {
        let json = ##"""
            {"name": "Navigation Bar", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 200, "height": 44, "fill": "#F9F9F9", "stroke": "#E5E5EA", "strokeWidth": 1},
                       {"name": "Back", "shape": "text", "text": "← Back", "fontSize": 17, "x": 8, "y": 10, "width": 0, "height": 0, "color": "#007AFF"},
                       {"name": "Title", "shape": "text", "text": "Navigation", "fontSize": 17, "weight": "semibold", "x": 0, "y": 0, "width": 0, "height": 0, "centerIn": "Background"}],
             "looks": [{"name": "Hover", "changes": [{"part": "Background", "fill": "#E5E5EA"}]}]}
            """##
        guard case .failure(let refused) = try AgentComponentTests.request(json) else { Issue.record("let Back run into the title"); return }
        #expect(refused.message.contains("Back") && refused.message.contains("Title"), "\(refused.message)")
    }
}

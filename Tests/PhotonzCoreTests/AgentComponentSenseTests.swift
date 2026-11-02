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
        // The Disabled fill is set faint too (no darker than Default's), so
        // the words are read on the fill it ends with.
        let ground = try #require(Self.part("Back", in: spec, look: "Disabled")?.look.fill?.hexValue)
        #expect(read(disabled.colorHex, ground) <= read(first.colorHex, "#F2F2F7"), "\(disabled.colorHex ?? "") on \(ground)")
        #expect(read(disabled.colorHex, ground) >= AgentNewComponent.leastWordLightness)
        #expect(spec.problem == nil)
    }

    @Test("A Disabled look whose faint words the plain pass had to darken to read is dimmed again, on a fill no darker than Default's")
    func disabledStaysFaintAfterRecolour() throws {
        // Ask's trace, 2026-10-24: #C7C7CC on #E5E5EA was set near black to
        // read, and every judge read the Disabled field as "more active than
        // the default one".
        let spec = try Self.plain(##"""
            {"name": "Text Field", "x": 32, "y": 160, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 200, "height": 36, "cornerRadius": 8, "fill": "#F2F2F7"},
                       {"name": "Label", "shape": "text", "text": "Placeholder", "fontSize": 15, "alignment": "left", "x": 12, "y": 0, "width": 176, "height": 36, "color": "#8E8E93"}],
             "looks": [{"name": "Focused", "changes": [{"part": "Background", "fill": "#FFFFFF", "stroke": "#007AFF", "strokeWidth": 2}]},
                       {"name": "Disabled", "changes": [{"part": "Background", "fill": "#E5E5EA"}, {"part": "Label", "color": "#C7C7CC"}]}]}
            """##)
        let back = try #require(Self.part("Background", in: spec, look: "Disabled")?.look.fill?.hexValue)
        let ground = try #require(RGBA(hex: back)), first = try #require(RGBA(hex: "#F2F2F7"))
        #expect(ground.linearLuminance >= first.linearLuminance, "\(back) is no darker than Default's #F2F2F7")
        let words = try #require(Self.part("Label", in: spec, look: "Disabled")?.colorHex)
        let reads = abs(RGBA.lightnessContrast(text: RGBA(hex: words) ?? first, on: ground))
        let before = abs(RGBA.lightnessContrast(text: RGBA(hex: "#8E8E93") ?? first, on: first))
        #expect(reads <= before, "\(words) on \(back) stands out no more than Default's words")
        #expect(reads >= AgentNewComponent.leastWordLightness, "\(words) on \(back) still reads")
        #expect(spec.problem == nil)
    }

    @Test("Words centred in one box that would land on each other keep the places their own boxes give them, in every look")
    func wordsKeepTheirOwnPlaces() throws {
        // Ask's trace, 2026-11-02 (run 20261102-190923): a segmented
        // control's Two and Three both centred in its Background, each given
        // its own slot, and One centred in the Selection that moves in later
        // looks. Refused three times as words on words, the control was left
        // off the sheet.
        let spec = try Self.plain(##"""
            {"firstLook":"One","labels":true,"looks":[{"changes":[{"part":"Selection","x":82},{"opacity":0.6,"part":"Label One"},{"opacity":1,"part":"Label Two"}],"name":"Two"},{"changes":[{"part":"Selection","x":162},{"opacity":0.6,"part":"Label One"},{"opacity":0.6,"part":"Label Two"},{"opacity":1,"part":"Label Three"}],"name":"Three"}],"name":"Segmented Control","parts":[{"cornerRadius":8,"fill":"#F2F2F7","height":32,"name":"Background","shape":"rectangle","width":240,"x":0,"y":0},{"cornerRadius":6,"fill":"#FFFFFF","height":28,"name":"Selection","shadow":{"color":"#000000","opacity":0.1,"radius":2},"shape":"rectangle","width":78,"x":2,"y":2},{"centerIn":"Selection","color":"#1C1C1E","fontSize":13,"height":28,"name":"Label One","shape":"text","text":"One","weight":"medium","width":78,"x":2,"y":2},{"centerIn":"Background","color":"#1C1C1E","fontSize":13,"height":28,"name":"Label Two","shape":"text","text":"Two","weight":"regular","width":80,"x":80,"y":2},{"centerIn":"Background","color":"#1C1C1E","fontSize":13,"height":28,"name":"Label Three","shape":"text","text":"Three","weight":"regular","width":78,"x":160,"y":2}],"x":24,"y":520}
            """##)
        #expect(spec.problem == nil, "\(spec.problem ?? "")")
        #expect(spec.looks.map(\.name) == ["One", "Two", "Three"])
        for look in spec.looks {
            let shown = spec.inLook(look)
            let spots = ["Label One", "Label Two", "Label Three"].compactMap { name in
                shown.parts.first { $0.name == name }.flatMap { shown.wordsSpot($0) }
            }
            #expect(spots.count == 3)
            #expect(spots.map(\.midX) == spots.map(\.midX).sorted() && spots[0].maxX < spots[1].minX && spots[1].maxX < spots[2].minX,
                    "in \(look.name), One, Two and Three sit side by side: \(spots)")
        }
        // Words centred in a box with no box of their own stay centred.
        let card = try Self.plain(##"""
            {"name": "Badge", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 40, "height": 24, "cornerRadius": 12, "fill": "#FF3B30"},
                       {"name": "Count", "shape": "text", "text": "3", "fontSize": 13, "x": 0, "y": 0, "width": 0, "height": 0, "centerIn": "Back", "color": "#FFFFFF"}],
             "looks": [{"name": "Hover", "changes": [{"part": "Back", "fill": "#C4170C"}]}]}
            """##)
        #expect(card.parts.last?.centerIn == "Back")
    }

    @Test("A Disabled field drawn faint grey with fainter words never ends with words darker than Default's")
    func disabledFieldNeverDarker() throws {
        // Ask's trace, 2026-11-02 (run 20261102-200517), the call as the
        // model sent it: every judge of two runs read "the disabled text
        // field's placeholder is darker than the enabled one's".
        let spec = try Self.plain(##"""
            {"firstLook":"Default","labels":true,"looks":[{"changes":[{"part":"Background","stroke":"#007AFF","strokeWidth":2}],"name":"Focused"},{"changes":[{"fill":"#F2F2F7","part":"Background","stroke":"#F2F2F7"},{"color":"#E5E5EA","part":"Placeholder"}],"name":"Disabled"}],"name":"Text Field","parts":[{"cornerRadius":8,"fill":"#FFFFFF","height":36,"name":"Background","shape":"rectangle","stroke":"#E5E5EA","strokeWidth":1,"width":240,"x":0,"y":0},{"alignment":"left","color":"#C7C7CC","fontSize":15,"height":36,"name":"Placeholder","shape":"text","text":"Placeholder","weight":"regular","width":216,"x":12,"y":0}],"x":240,"y":440}
            """##)
        let read = { (hex: String?, ground: String?) in
            abs(RGBA.lightnessContrast(text: RGBA(hex: hex ?? "") ?? RGBA(r: 0, g: 0, b: 0), on: RGBA(hex: ground ?? "#FFFFFF") ?? RGBA(r: 1, g: 1, b: 1)))
        }
        #expect(spec.looks.map(\.name) == ["Default", "Focused", "Disabled"])
        let words = Self.part("Placeholder", in: spec, look: "Disabled")?.colorHex
        let ground = Self.part("Background", in: spec, look: "Disabled")?.look.fill?.hexValue
        let first = spec.parts.last?.colorHex
        #expect(read(words, ground) <= read(first, "#FFFFFF") + AgentNewComponent.disabledLeeway,
                "Disabled \(words ?? "") on \(ground ?? "") against Default \(first ?? "") on white")
        #expect(read(words, ground) >= AgentNewComponent.leastWordLightness, "still reads")
        #expect(spec.problem == nil)
    }

    @Test("A look named with a number on the end is named its state; one that would repeat a name is left out")
    func numberedLooks() throws {
        // Ask's segmented control, 2026-10-24: a header read "Selected2", and
        // every judge called it a typo.
        let two = try Self.plain(##"""
            {"name": "Segmented Control", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Track", "shape": "rectangle", "x": 0, "y": 0, "width": 200, "height": 32, "fill": "#E5E5EA"},
                       {"name": "Selection", "shape": "rectangle", "x": 2, "y": 2, "width": 96, "height": 28, "fill": "#FFFFFF"}],
             "looks": [{"name": "Selected2", "changes": [{"part": "Selection", "x": 102}]}]}
            """##)
        #expect(two.looks.map(\.name) == ["Default", "Selected"])
        let three = try Self.plain(##"""
            {"name": "Segmented Control", "x": 0, "y": 0, "labels": true, "firstLook": "Selected 1",
             "parts": [{"name": "Track", "shape": "rectangle", "x": 0, "y": 0, "width": 300, "height": 32, "fill": "#E5E5EA"},
                       {"name": "Selection", "shape": "rectangle", "x": 2, "y": 2, "width": 96, "height": 28, "fill": "#FFFFFF"}],
             "looks": [{"name": "Selected 2", "changes": [{"part": "Selection", "x": 102}]},
                       {"name": "Disabled", "changes": [{"part": "Track", "opacity": 0.4}]},
                       {"name": "Selected 3", "changes": [{"part": "Selection", "x": 202}]}]}
            """##)
        #expect(three.looks.map(\.name) == ["Selected", "Disabled"])
    }

    @Test("A look that barely differs from an earlier one is left out: a shadow, or one small part a shade off")
    func barelyDifferent() throws {
        // Judges of Ask's sheets, 2026-10-24: "the hover versions of the nav
        // bar, badge, alert and card match their defaults".
        let card = try Self.plain(##"""
            {"name": "Card", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 260, "height": 150, "cornerRadius": 12, "fill": "#FFFFFF", "stroke": "#E5E5EA", "strokeWidth": 1},
                       {"name": "Title", "shape": "text", "text": "Card Title", "fontSize": 17, "x": 16, "y": 100, "width": 228, "height": 24, "color": "#1C1C1E"}],
             "looks": [{"name": "Hover", "changes": [{"part": "Background", "shadow": {"color": "#000000", "opacity": 0.2, "radius": 24}}]}]}
            """##)
        #expect(card.looks.map(\.name) == ["Default"])
        let alert = try Self.plain(##"""
            {"name": "Alert", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 260, "height": 150, "cornerRadius": 12, "fill": "#FFFFFF", "stroke": "#E5E5EA", "strokeWidth": 1},
                       {"name": "Title", "shape": "text", "text": "Alert Title", "fontSize": 17, "x": 16, "y": 16, "width": 228, "height": 24, "color": "#1C1C1E"},
                       {"name": "Button1", "shape": "rectangle", "x": 140, "y": 104, "width": 100, "height": 32, "cornerRadius": 8, "fill": "#007AFF"},
                       {"name": "OK", "shape": "text", "text": "OK", "fontSize": 15, "centerIn": "Button1", "x": 0, "y": 0, "width": 0, "height": 0, "color": "#FFFFFF"}],
             "looks": [{"name": "Hover", "changes": [{"part": "Button1", "fill": "#0071E6"}]}]}
            """##)
        #expect(alert.looks.map(\.name) == ["Default"])
        // A word faded to 70%, a knob grown 24 to 28 with a thicker edge.
        let navigation = try Self.plain(##"""
            {"name": "Navigation Bar", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 300, "height": 44, "fill": "#F2F2F7"},
                       {"name": "Title", "shape": "text", "text": "Title", "fontSize": 17, "weight": "semibold", "alignment": "center", "x": 100, "y": 12, "width": 100, "height": 20, "color": "#000000"},
                       {"name": "Left Button", "shape": "text", "text": "Back", "fontSize": 17, "x": 12, "y": 12, "width": 60, "height": 20, "color": "#007AFF"}],
             "looks": [{"name": "Hover", "changes": [{"part": "Left Button", "opacity": 0.7}]}]}
            """##)
        #expect(navigation.looks.map(\.name) == ["Default"])
        let slider = try Self.plain(##"""
            {"name": "Slider", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Track", "shape": "rectangle", "x": 0, "y": 15, "width": 160, "height": 4, "cornerRadius": 2, "fill": "#C7C7CC"},
                       {"name": "Fill", "shape": "rectangle", "x": 0, "y": 15, "width": 80, "height": 4, "cornerRadius": 2, "fill": "#007AFF"},
                       {"name": "Knob", "shape": "ellipse", "x": 72, "y": 5, "width": 24, "height": 24, "fill": "#FFFFFF", "stroke": "#C7C7CC", "strokeWidth": 1}],
             "looks": [{"name": "Hover", "changes": [{"part": "Knob", "x": 72, "width": 28, "height": 28, "strokeWidth": 2}]},
                       {"name": "Moved", "changes": [{"part": "Knob", "x": 120}, {"part": "Fill", "width": 128}]}]}
            """##)
        #expect(slider.looks.map(\.name) == ["Default", "Moved"])
        // Twins: a Pressed the same as Hover goes, Hover stays.
        let toggle = try Self.plain(##"""
            {"name": "Button", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 120, "height": 36, "cornerRadius": 8, "fill": "#007AFF"},
                       {"name": "Label", "shape": "text", "text": "Button", "fontSize": 15, "centerIn": "Background", "x": 0, "y": 0, "width": 0, "height": 0, "color": "#FFFFFF"}],
             "looks": [{"name": "Hover", "changes": [{"part": "Background", "fill": "#0056CC"}]},
                       {"name": "Pressed", "changes": [{"part": "Background", "fill": "#0056CC"}]},
                       {"name": "Disabled", "changes": [{"part": "Background", "fill": "#E5E5EA"}, {"part": "Label", "color": "#8E8E93"}]}]}
            """##)
        #expect(toggle.looks.map(\.name) == ["Default", "Hover", "Disabled"])
        // What plainly shows stays: an edge round a field, a tick, a word turned blue.
        let field = try Self.plain(##"""
            {"name": "Field", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 200, "height": 36, "cornerRadius": 8, "fill": "#FFFFFF", "stroke": "#C7C7CC", "strokeWidth": 1},
                       {"name": "Label", "shape": "text", "text": "Name", "fontSize": 15, "x": 12, "y": 0, "width": 176, "height": 36, "color": "#8E8E93"}],
             "looks": [{"name": "Focused", "changes": [{"part": "Background", "stroke": "#007AFF", "strokeWidth": 2}]}]}
            """##)
        #expect(field.looks.map(\.name) == ["Default", "Focused"])
        let nav = try Self.plain(##"""
            {"name": "Tabs", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 240, "height": 44, "fill": "#F2F2F7"},
                       {"name": "Home", "shape": "text", "text": "Home", "fontSize": 15, "x": 16, "y": 0, "width": 60, "height": 44, "color": "#1C1C1E"},
                       {"name": "About", "shape": "text", "text": "About", "fontSize": 15, "x": 96, "y": 0, "width": 60, "height": 44, "color": "#1C1C1E"}],
             "looks": [{"name": "Selected", "changes": [{"part": "About", "color": "#007AFF"}]}]}
            """##)
        #expect(nav.looks.map(\.name) == ["Default", "Selected"])
    }

    @Test("Blue words left unreadable on a blue look are set white, not near black")
    func whiteOnColour() throws {
        let spec = try Self.plain(##"""
            {"name": "Secondary Button", "x": 0, "y": 0, "labels": true, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 120, "height": 40, "cornerRadius": 8, "fill": "#FFFFFF", "stroke": "#007AFF", "strokeWidth": 1.5},
                       {"name": "Label", "shape": "text", "text": "Secondary", "fontSize": 15, "centerIn": "Background", "x": 0, "y": 0, "width": 0, "height": 0, "color": "#007AFF"}],
             "looks": [{"name": "Hover", "changes": [{"part": "Background", "fill": "#007AFF"}]}]}
            """##)
        #expect(Self.part("Label", in: spec, look: "Hover")?.colorHex == "#FFFFFF")
        #expect(Self.part("Label", in: spec, look: "Default")?.colorHex == "#007AFF")
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

    @Test("A Pressed a shade off its Hover is set plainly apart from it, the way it already leaned; a Hover already plain is kept")
    func laterLooksStepApart() throws {
        // The eval, 2026-11-02: Default #007AFF, Hover #006CDF, Pressed
        // #0065D1, and all three judges: "Hover and Pressed look almost the same".
        let spec = try Self.plain(##"""
            {"name":"Button","x":0,"y":0,"labels":false,"firstLook":"Default",
             "parts":[{"name":"Back","shape":"rectangle","x":0,"y":0,"width":120,"height":32,"fill":"#007AFF"},
                      {"name":"Label","shape":"text","text":"Button","color":"#FFFFFF","x":34,"y":5,"width":0,"height":0}],
             "looks":[{"name":"Hover","changes":[{"part":"Back","fill":"#006CDF"}]},
                      {"name":"Pressed","changes":[{"part":"Back","fill":"#0065D1"}]},
                      {"name":"Disabled","changes":[{"part":"Back","fill":"#E5E5EA"},{"part":"Label","color":"#8E8E93"}]}]}
            """##)
        #expect(spec.looks.map(\.name) == ["Default", "Hover", "Pressed", "Disabled"])
        let hover = try #require(Self.part("Back", in: spec, look: "Hover")?.look.fill?.hexValue)
        let pressed = try #require(Self.part("Back", in: spec, look: "Pressed")?.look.fill?.hexValue)
        #expect(RGBA(hex: hover) == RGBA(hex: "#006CDF"), "a Hover already plain from Default is left as the model gave it")
        #expect(AgentNewComponent.plainlyApart(pressed, hover) == true, "\(pressed) beside \(hover)")
        #expect(AgentNewComponent.plainlyApart(pressed, "#007AFF") == true)
        let one = try #require(RGBA(hex: pressed)), two = try #require(RGBA(hex: hover))
        #expect(one.b < two.b && one.r <= two.r + 0.5 / 255, "Pressed goes on darker, the way it leaned: \(pressed)")
        #expect(RGBA(hex: Self.part("Back", in: spec, look: "Disabled")?.look.fill?.hexValue ?? "") == RGBA(hex: "#E5E5EA"),
                "a Disabled look is not stepped away from the others")
        // The model's own call that day: a Hover too near Default is widened
        // first, to beside the Pressed, and Pressed then steps on from it.
        let widened = try Self.plain(##"""
            {"name":"Button","x":0,"y":0,"labels":false,"firstLook":"Default",
             "parts":[{"name":"Back","shape":"rectangle","x":0,"y":0,"width":120,"height":32,"fill":"#007AFF"},
                      {"name":"Label","shape":"text","text":"Button","color":"#FFFFFF","x":34,"y":5,"width":0,"height":0}],
             "looks":[{"name":"Hover","changes":[{"part":"Back","fill":"#0071EB"}]},
                      {"name":"Pressed","changes":[{"part":"Back","fill":"#0065D1"}]}]}
            """##)
        let fills = ["Default", "Hover", "Pressed"].compactMap { Self.part("Back", in: widened, look: $0)?.look.fill?.hexValue }
        #expect(fills.count == 3)
        #expect(AgentNewComponent.plainlyApart(fills[0], fills[1]) == true, "\(fills)")
        #expect(AgentNewComponent.plainlyApart(fills[1], fills[2]) == true, "\(fills)")
    }


    @Test("Words a later look shows and restyles stay shown in the first look; words a look only shows start hidden")
    func restyledWordsStayShown() throws {
        // The eval, 2026-11-02: a segmented control whose Two look set
        // "Label One" visible and plain lost its "One" in the first look.
        let spec = try Self.plain(##"""
            {"name":"Segmented Control","x":0,"y":0,"labels":false,"firstLook":"One",
             "parts":[{"name":"Background","shape":"rectangle","x":0,"y":0,"width":240,"height":32,"fill":"#E9E9EA"},
                      {"name":"Selected","shape":"rectangle","x":2,"y":2,"width":78,"height":28,"fill":"#FFFFFF"},
                      {"name":"Label One","shape":"text","text":"One","color":"#1C1C1E","weight":"medium","x":2,"y":2,"width":78,"height":28,"alignment":"center"},
                      {"name":"Label Two","shape":"text","text":"Two","color":"#1C1C1E","x":80,"y":2,"width":78,"height":28,"alignment":"center"},
                      {"name":"Note","shape":"text","text":"Saved","color":"#1C1C1E","x":0,"y":40,"width":0,"height":0}],
             "looks":[{"name":"Two","changes":[{"part":"Selected","x":80},
                      {"part":"Label One","visible":true,"color":"#1C1C1E"},
                      {"part":"Note","visible":true}]}]}
            """##)
        #expect(Self.part("Label One", in: spec, look: "One")?.hidden == false)
        #expect(Self.part("Note", in: spec, look: "One")?.hidden == true, "words a look only shows start hidden")
        #expect(Self.part("Note", in: spec, look: "Two")?.hidden == false)
    }

    @Test("Words a later look hides while rewriting them to what another part says stay as they were; words only hidden stay hidden")
    func hiddenAndRewrittenWordsStay() throws {
        // The eval, 2026-11-02, the model's own call: the Second look set
        // Label 1 to "Second" and hid it, so "First" was gone from the
        // Second and Third looks (every judge: "loses its First label").
        let spec = try Self.plain(##"""
            {"name":"Segmented Control","x":240,"y":520,"labels":true,"firstLook":"First",
             "parts":[{"name":"Background","shape":"rectangle","x":0,"y":0,"width":240,"height":32,"cornerRadius":8,"fill":"#E9E9EA"},
                      {"name":"Segment 1","shape":"rectangle","x":2,"y":2,"width":78,"height":28,"cornerRadius":6,"fill":"#FFFFFF"},
                      {"name":"Label 1","shape":"text","text":"First","color":"#1C1C1E","fontSize":13,"weight":"medium","x":2,"y":2,"width":78,"height":28,"alignment":"center"},
                      {"name":"Label 2","shape":"text","text":"Second","color":"#1C1C1E","fontSize":13,"x":82,"y":2,"width":78,"height":28,"alignment":"center"},
                      {"name":"Label 3","shape":"text","text":"Third","color":"#1C1C1E","fontSize":13,"x":162,"y":2,"width":76,"height":28,"alignment":"center"}],
             "looks":[{"name":"Second","changes":[{"part":"Segment 1","x":82},{"part":"Label 1","text":"Second","visible":false},{"part":"Label 2","text":"Second","visible":true}]},
                      {"name":"Third","changes":[{"part":"Segment 1","x":162},{"part":"Label 1","text":"Third","visible":false},{"part":"Label 3","text":"Third","visible":true}]}]}
            """##)
        for look in ["First", "Second", "Third"] {
            let label = Self.part("Label 1", in: spec, look: look)
            #expect(label?.hidden == false, "\(look)")
            #expect(label?.text == "First", "\(look)")
        }
        #expect(Self.part("Label 2", in: spec, look: "First")?.hidden == false)
        // A badge whose Empty look hides its count keeps it hidden.
        let badge = try Self.plain(##"""
            {"name":"Badge","x":0,"y":0,"labels":true,"firstLook":"Default",
             "parts":[{"name":"Dot","shape":"ellipse","x":0,"y":0,"width":24,"height":24,"fill":"#FF3B30"},
                      {"name":"Count","shape":"text","text":"3","color":"#FFFFFF","fontSize":13,"x":0,"y":0,"width":24,"height":24,"alignment":"center"}],
             "looks":[{"name":"Empty","changes":[{"part":"Count","visible":false}]}]}
            """##)
        #expect(Self.part("Count", in: badge, look: "Empty")?.hidden == true)
    }

    @Test("A part a later look grows both ways stays centred on what it was centred on; one grown one way keeps its edge")
    func grownPartStaysCentred() throws {
        // The eval, 2026-11-02: a Pressed slider knob grown 26 to 36 from
        // its top left sat 5 points below its track (every judge: "the
        // pressed slider's track sits off the thumb's centre").
        let spec = try Self.plain(##"""
            {"name":"Slider","x":0,"y":0,"labels":true,"firstLook":"Default",
             "parts":[{"name":"Track","shape":"rectangle","x":0,"y":14,"width":240,"height":4,"cornerRadius":2,"fill":"#E5E5EA"},
                      {"name":"Fill","shape":"rectangle","x":0,"y":14,"width":120,"height":4,"cornerRadius":2,"fill":"#007AFF"},
                      {"name":"Knob","shape":"ellipse","x":105,"y":3,"width":26,"height":26,"fill":"#FFFFFF","stroke":"#D1D1D6","strokeWidth":1}],
             "looks":[{"name":"Pressed","changes":[{"part":"Knob","x":100,"y":3,"width":36,"height":36}]}]}
            """##)
        let track = try #require(Self.part("Track", in: spec, look: "Pressed"))
        let knob = try #require(Self.part("Knob", in: spec, look: "Pressed"))
        #expect(abs(knob.frame.midY - track.frame.midY) < 0.5, "\(knob.frame) on \(track.frame)")
        #expect(abs(knob.frame.midX - 118) < 0.5, "the knob's own across centre is kept: \(knob.frame)")
        #expect(knob.frame.width == 36 && knob.frame.height == 36)
        let rest = try #require(Self.part("Knob", in: spec, look: "Default"))
        #expect(rest.frame == CGRect(x: 105, y: 3, width: 26, height: 26))
        // A progress fill grown across only keeps its left edge.
        let bar = try Self.plain(##"""
            {"name":"Progress","x":0,"y":0,"labels":true,"firstLook":"Default",
             "parts":[{"name":"Track","shape":"rectangle","x":0,"y":0,"width":240,"height":4,"fill":"#E5E5EA"},
                      {"name":"Fill","shape":"rectangle","x":0,"y":0,"width":144,"height":4,"fill":"#007AFF"}],
             "looks":[{"name":"Complete","changes":[{"part":"Fill","width":240,"fill":"#34C759"}]}]}
            """##)
        #expect(Self.part("Fill", in: bar, look: "Complete")?.frame == CGRect(x: 0, y: 0, width: 240, height: 4))
        // A toggle knob that only moves along keeps where the model put it.
        let toggle = try Self.plain(##"""
            {"name":"Toggle","x":0,"y":0,"labels":true,"firstLook":"Off",
             "parts":[{"name":"Track","shape":"rectangle","x":0,"y":0,"width":51,"height":31,"cornerRadius":15.5,"fill":"#E9E9EA"},
                      {"name":"Knob","shape":"ellipse","x":2,"y":2,"width":27,"height":27,"fill":"#FFFFFF"}],
             "looks":[{"name":"On","changes":[{"part":"Track","fill":"#34C759"},{"part":"Knob","x":22}]}]}
            """##)
        #expect(Self.part("Knob", in: toggle, look: "On")?.frame == CGRect(x: 22, y: 2, width: 27, height: 27))
    }

}

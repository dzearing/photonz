import Foundation
@testable import PhotonzCore
import Testing

/// Ask in the app (`docs/design/ask.md`): a request in plain words, turned by a
/// model on this Mac into a plan of the agent tools. The model may look (the
/// read-only tools answer at once) but every editing call is only written
/// into the plan, checked against its schema, and nothing runs until Run plan.
@Suite("Ask: planning on a local model")
struct AskPlanningTests {

    static func json(_ text: String) throws -> AgentJSON { try AgentJSON.parse(Data(text.utf8)) }

    static func reply(_ calls: [(String, String)], content: String = "") throws -> AgentJSON {
        let toolCalls: [AgentJSON] = try calls.map { name, args in
            ["function": ["name": .string(name), "arguments": try json(args)]]
        }
        return ["message": ["role": "assistant", "content": .string(content), "tool_calls": .array(toolCalls)]]
    }

    static func conversation(_ request: String = "add a title") -> AskConversation {
        AskConversation(request: request, documentRead: #"{"kind":"picture","width":800,"height":600}"#)
    }

    // MARK: The tools offered

    @Test("Every tool Ask offers is a real agent tool, and looking and doing never overlap")
    func offeredToolsAreReal() {
        for name in AskTools.looking + AskTools.doing {
            #expect(AgentTools.tool(named: name) != nil, "\(name) is not an agent tool")
        }
        #expect(Set(AskTools.looking).isDisjoint(with: AskTools.doing))
    }

    @Test("Nothing Ask offers opens a window, writes a file, or steps the history")
    func noToolLeavesTheDocument() {
        let offered = Set(AskTools.looking + AskTools.doing)
        for name in ["new_picture", "new_video", "open_document", "export", "export_video", "undo", "redo",
                     "list_documents", "list_history"] {
            #expect(!offered.contains(name), "\(name) should not be offered to Ask")
        }
    }

    @Test("The model is shown each tool without a document argument, and every property has a type")
    func modelSchemas() throws {
        let tools = AskTools.modelTools
        #expect(tools.count == AskTools.looking.count + AskTools.doing.count)
        for tool in tools {
            let function = try #require(tool["function"])
            let name = try #require(function["name"]?.stringValue)
            let properties = function["parameters"]?["properties"]?.objectValue ?? [:]
            #expect(properties["document"] == nil, "\(name) still shows document")
            for (key, property) in properties {
                #expect(property["type"] != nil, "\(name).\(key) has no type")
            }
        }
    }

    // MARK: Planning

    @Test("An editing call is planned, not run: it is answered with its step number")
    func doingIsPlanned() throws {
        var talk = Self.conversation()
        let outcome = talk.take(try Self.reply([("add_text", #"{"text":"Pricing","x":64,"y":48}"#)]))
        #expect(outcome == .again(looks: []))
        #expect(talk.steps.map(\.tool) == ["add_text"])
        #expect(talk.messages.last?["role"] == "tool")
        #expect(talk.messages.last?["content"]?.stringValue?.contains("step 1") == true)
    }

    @Test("Every call the model makes is counted, and the broken ones apart: wrong arguments, an unknown tool, or a call written as text")
    func brokenCallsAreCounted() throws {
        var talk = Self.conversation()
        _ = talk.take(try Self.reply([("add_text", #"{"text":"Pricing","x":64,"y":48}"#), ("find_elements", #"{"limit":20}"#)]))
        #expect(talk.calls == 2)
        #expect(talk.brokenCalls == 0)
        _ = talk.take(try Self.reply([("add_text", #"{"x":"left"}"#), ("draw_unicorn", "{}")]))
        #expect(talk.calls == 4)
        #expect(talk.brokenCalls == 2)
        _ = talk.take(try Self.reply([], content: #"<tool_call>{"name":"add_text","arguments":{"text":"Hi","x":1,"y":2}}</tool_call>"#))
        #expect(talk.calls == 5)
        #expect(talk.brokenCalls == 3, "a call written as text still runs, but it came back broken")
    }

    @Test("A looking call is handed back to be run, and its answer goes to the model")
    func lookingIsRun() throws {
        var talk = Self.conversation()
        let outcome = talk.take(try Self.reply([("find_elements", #"{"limit":20}"#)]))
        guard case .again(let looks) = outcome else { Issue.record("expected again"); return }
        #expect(looks.map(\.tool) == ["find_elements"])
        #expect(talk.steps.isEmpty)
        talk.answer(looks[0], with: #"[{"x":1}]"#)
        #expect(talk.messages.last?["content"]?.stringValue == #"[{"x":1}]"#)
        #expect(talk.messages.last?["tool_name"]?.stringValue == "find_elements")
    }

    @Test("A call that fails its schema is refused back to the model and never enters the plan")
    func badCallRefused() throws {
        var talk = Self.conversation()
        _ = talk.take(try Self.reply([("add_text", #"{"words":"Pricing"}"#)]))
        #expect(talk.steps.isEmpty)
        let said = talk.messages.last?["content"]?.stringValue ?? ""
        #expect(said.contains("add_text"))
    }

    @Test("A refused call sent back unchanged twice ends the planning with the steps already written")
    func stuckOnARefusal() throws {
        var talk = Self.conversation()
        _ = talk.take(try Self.reply([("add_text", #"{"text":"Hi","x":8,"y":8}"#)]))
        let stuck = ("add_text", #"{"words":"Pricing"}"#)
        #expect(talk.take(try Self.reply([stuck])) == .again(looks: []))
        #expect(talk.take(try Self.reply([stuck])) == .again(looks: []))
        guard case .planned(let plan) = talk.take(try Self.reply([stuck])) else {
            Issue.record("still asking after the same refusal three times"); return
        }
        #expect(plan.steps.map(\.tool) == ["add_text"])
        // A model that moves on from a refusal is not stuck.
        var moving = Self.conversation()
        _ = moving.take(try Self.reply([("add_text", #"{"text":"Hi","x":8,"y":8}"#)]))
        _ = moving.take(try Self.reply([stuck]))
        _ = moving.take(try Self.reply([stuck]))
        #expect(moving.take(try Self.reply([("add_text", #"{"text":"Bye","x":8,"y":40}"#)])) == .again(looks: []))
    }

    static func sheet() -> AskConversation {
        AskConversation(request: "base components", documentRead: #"{"kind":"picture","canvas":{"width":1440,"height":1024}}"#)
    }

    static func component(_ name: String, x: Int, y: Int, width: Int, height: Int = 32,
                          labels: Bool = true) -> (String, String) {
        ("add_component", """
            {"name":"\(name)","x":\(x),"y":\(y),"labels":\(labels),"firstLook":"Default",\
            "parts":[{"name":"Back","shape":"rectangle","x":0,"y":0,"width":\(width),"height":\(height)}],\
            "looks":[{"name":"Hover","changes":[{"part":"Back","opacity":0.8}]}]}
            """)
    }

    @Test("Labelled components line up as one sheet: the first one's x, no nearer the edge than the page margin, one column step that fits the canvas")
    func sheetLinesUp() throws {
        var talk = Self.sheet()
        _ = talk.take(try Self.reply([Self.component("Button", x: 80, y: 100, width: 120)]))
        _ = talk.take(try Self.reply([Self.component("Field", x: 300, y: 200, width: 200)]))
        _ = talk.take(try Self.reply([Self.component("Loose", x: 900, y: 300, width: 60, labels: false)]))
        let args = talk.steps.map(\.arguments)
        #expect(args.map { $0["x"]?.doubleValue } == [80, 80, 900])
        // A sheet and its title set at 40 start on the page margin instead:
        // judges read 40 as "the right column nearly touches the edge"
        // (the eval, 2026-10-24).
        var tight = Self.sheet()
        _ = tight.take(try Self.reply([("add_text", #"{"text":"Base Components","x":40,"y":40,"fontSize":32}"#)]))
        _ = tight.take(try Self.reply([Self.component("Button", x: 40, y: 100, width: 120)]))
        #expect(tight.steps.map { $0.arguments["x"]?.doubleValue } == [64, 64])
        // Rows stack straight under one another: 32 tall, 25 for the state names, 24 apart.
        #expect(args.map { $0["y"]?.doubleValue } == [100, 181, 300])
        #expect(args[0]["step"]?.doubleValue == 224 && args[1]["step"]?.doubleValue == 224,
                "the widest look plus 24, for every labelled row")
        #expect(args[2]["step"] == nil, "a component with no labels is left as asked")
        // A look too wide to share a column with the rest keeps its own step,
        // and the rest still share theirs.
        var wide = Self.sheet()
        _ = wide.take(try Self.reply([Self.component("Button", x: 40, y: 100, width: 120)]))
        _ = wide.take(try Self.reply([Self.component("Banner", x: 40, y: 200, width: 900)]))
        _ = wide.take(try Self.reply([Self.component("Field", x: 40, y: 300, width: 200)]))
        #expect(wide.steps.map { $0.arguments["step"]?.doubleValue } == [224, nil, 224])
    }

    @Test("Words a labelled row already sets are refused, naming the step that sets them")
    func labelsNotTwice() throws {
        var talk = Self.sheet()
        _ = talk.take(try Self.reply([Self.component("Button", x: 40, y: 100, width: 120)]))
        _ = talk.take(try Self.reply([("add_text", #"{"text":"button","x":40,"y":150}"#)]))
        #expect(talk.steps.count == 1)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("step 1") == true)
        _ = talk.take(try Self.reply([("add_text", #"{"text":"Base Components","x":40,"y":40}"#)]))
        #expect(talk.steps.count == 2, "a title is words of its own")
    }

    @Test("Ask is never shown the Library's starters: it builds, or uses the document's own")
    func noStarters() {
        let listing = #"[{"id":"S-1","name":"Button","from":"starter","detail":"starter"},{"id":"D-1","name":"Hero","from":"document","detail":"main"}]"#
        let shown = AskTools.withoutStarters(listing)
        #expect(!shown.contains("S-1"))
        #expect(shown.contains("D-1"))
        #expect(AskTools.withoutStarters(#"[{"id":"S-1","name":"Button","from":"starter"}]"#) == "[]")
        #expect(AskTools.withoutStarters("not json") == "not json")
    }

    @Test("A sheet longer than the canvas plans no canvas size: the table grows the canvas as it lands")
    func sheetPlansNoCanvasSize() throws {
        var talk = Self.sheet()
        for index in 0..<5 {
            _ = talk.take(try Self.reply([Self.component("Kind \(index)", x: 40, y: 100, width: 80 + index * 8, height: 200)]))
        }
        #expect(talk.steps.map(\.tool) == Array(repeating: "add_component", count: 5))
        #expect(talk.messages.last?["content"]?.stringValue?.contains("step 5") == true)
    }

    @Test("A component that passes its checks but cannot be built is refused while planning, with the reason, so no kind is lost when the plan runs")
    func componentThatCannotBeBuilt() throws {
        var talk = Self.sheet()
        // A shape given words in a look: the call reads fine, the build fails
        // (the eval, 2026-10-24: a planned Navigation skipped at run time as
        // "AgentToolError error 1").
        _ = talk.take(try Self.reply([("add_component", """
            {"name":"Chip","x":40,"y":100,"labels":true,"firstLook":"Default",\
            "parts":[{"name":"Back","shape":"rectangle","x":0,"y":0,"width":60,"height":24}],\
            "looks":[{"name":"Hover","changes":[{"part":"Back","text":"Hi"}]}]}
            """)]))
        #expect(talk.steps.isEmpty)
        let said = talk.messages.last?["content"]?.stringValue ?? ""
        #expect(said.contains("Back"), "\(said)")
    }

    @Test("A tool's refusal reads as its own words wherever it is shown, not as an error number")
    func toolErrorWords() {
        let error: Error = AgentToolError("add_component: Back has no words to change.")
        #expect(error.localizedDescription == "add_component: Back has no words to change.")
    }

    @Test("A component drawn the same as one already planned is refused, naming it, so the sheet shows each kind once")
    func sameKindTwice() throws {
        var talk = Self.sheet()
        _ = talk.take(try Self.reply([Self.component("Toggle", x: 40, y: 100, width: 51)]))
        _ = talk.take(try Self.reply([Self.component("Switch", x: 40, y: 200, width: 51)]))
        #expect(talk.steps.count == 1)
        let said = talk.messages.last?["content"]?.stringValue ?? ""
        #expect(said.contains("Toggle") && said.contains("step 1"), "\(said)")
        _ = talk.take(try Self.reply([Self.component("Slider", x: 40, y: 200, width: 200)]))
        #expect(talk.steps.count == 2, "a different drawing is a different kind")
    }

    @Test("A labelled row named like one already planned is sent back to be named for what makes it different")
    func sameNameTwice() throws {
        // The eval, 2026-10-24: a filled and a grey button, both rows
        // labelled "Button", and every judge named it.
        var talk = Self.sheet()
        _ = talk.take(try Self.reply([Self.component("Button", x: 40, y: 100, width: 120)]))
        _ = talk.take(try Self.reply([Self.component("button ", x: 40, y: 200, width: 200, height: 44)]))
        #expect(talk.steps.count == 1)
        let said = talk.messages.last?["content"]?.stringValue ?? ""
        #expect(said.contains("called button") && said.contains("step 1"), "\(said)")
        _ = talk.take(try Self.reply([Self.component("Secondary Button", x: 40, y: 200, width: 200, height: 44)]))
        #expect(talk.steps.count == 2)
        // A component on its own, with no row name, may share a name.
        _ = talk.take(try Self.reply([Self.component("Button", x: 900, y: 600, width: 300, height: 60, labels: false)]))
        #expect(talk.steps.count == 3)
    }

    @Test("Ask's planner makes a look a shade off plain and edges a white surface itself, rather than refusing a small model")
    func madePlainForTheModel() throws {
        var talk = Self.sheet()
        _ = talk.take(try Self.reply([("add_component", ##"""
            {"name":"Card","x":40,"y":100,"labels":true,"firstLook":"Default",
            "parts":[{"name":"Back","shape":"rectangle","x":0,"y":0,"width":200,"height":100,"fill":"#FFFFFF"},
            {"name":"Title","shape":"text","text":"Title","color":"#1C1C1E","x":16,"y":16,"width":0,"height":0}],
            "looks":[{"name":"Hover","changes":[{"part":"Back","fill":"#FAFAFA"}]},
            {"name":"Pressed","changes":[{"part":"Title","color":"#2C2C2E"},{"part":"Back","opacity":0.95}]}]}
            """##)]))
        #expect(talk.steps.count == 1, "\(talk.messages.last?["content"]?.stringValue ?? "")")
        let planned = try #require(talk.steps.first?.arguments)
        let back = planned["parts"]?.arrayValue?.first
        #expect(back?["stroke"]?.stringValue != nil && back?["strokeWidth"]?.doubleValue == 1, "a white card on white gets a hairline edge")
        guard case .success(.addComponent(_, let spec)) = AgentTools.request(tool: "add_component", arguments: planned) else {
            Issue.record("the plain call is still refused"); return
        }
        #expect(spec.problem == nil)
        // A shade already plain is left as the model gave it.
        let button = AgentNewComponent.madePlain(try AgentJSON.parse(Data(##"""
            {"name":"Button","x":0,"y":0,"labels":false,"firstLook":"Default",
             "parts":[{"name":"Back","shape":"rectangle","x":0,"y":0,"width":120,"height":40,"fill":"#007AFF"}],
             "looks":[{"name":"Pressed","changes":[{"part":"Back","fill":"#0062CC"}]}]}
            """##.utf8)))
        #expect(button["looks"]?.arrayValue?.first?["changes"]?.arrayValue?.first?["fill"]?.stringValue == "#0062CC")
    }

    @Test("A model sending a refused component back unchanged is stopped, with the plan it has")
    func stuckOnTheSameKind() throws {
        var talk = Self.sheet()
        _ = talk.take(try Self.reply([Self.component("Button", x: 40, y: 100, width: 120)]))
        var outcome: AskConversation.Outcome?
        var told: [String] = []
        for _ in 0..<5 {
            outcome = talk.take(try Self.reply([Self.component("Button", x: 40, y: 200, width: 120)]))
            told.append(talk.messages.last?["content"]?.stringValue ?? "")
            if case .planned = outcome { break }
        }
        #expect(!told[0].contains("Leave Button out"))
        #expect(told[1].contains("Leave Button out"), "sent back unchanged, it is asked for the next kind: \(told[1])")
        #expect(talk.messages.filter { $0["role"]?.stringValue == "tool" && $0["content"]?.stringValue?.hasPrefix("Not planned") == true }.count < told.count,
                "the unchanged repeat is taken out of the talk")
        guard case .planned(let plan) = outcome else { Issue.record("still asking after five refusals"); return }
        #expect(plan.steps.count == 1)
        #expect(talk.rounds <= 6)
    }

    @Test("Once a sheet has labelled rows, words of the model's own are refused: the table names its rows and states")
    func noWordsOverTheTable() throws {
        var talk = Self.sheet()
        _ = talk.take(try Self.reply([("add_text", #"{"text":"Base Components","x":40,"y":40}"#)]))
        _ = talk.take(try Self.reply([Self.component("Button", x: 40, y: 100, width: 120)]))
        _ = talk.take(try Self.reply([("add_text", #"{"text":"Cards and Containers","x":40,"y":400}"#)]))
        #expect(talk.steps.map(\.tool) == ["add_text", "add_component"])
        #expect(talk.messages.last?["content"]?.stringValue?.contains("table") == true)
    }

    @Test("Words the model wrote as web text are set as the characters they stand for")
    func entitiesDecoded() throws {
        var talk = Self.sheet()
        _ = talk.take(try Self.reply([("add_text", #"{"text":"Cards &amp; Containers &lt;1&gt;","x":40,"y":40}"#)]))
        #expect(talk.steps.first?.arguments["text"]?.stringValue == "Cards & Containers <1>")
    }

    @Test("A sheet planned with no title is asked for one once, and the title goes first")
    func sheetGetsATitle() throws {
        var talk = Self.sheet()
        _ = talk.take(try Self.reply([Self.component("Button", x: 40, y: 100, width: 120)]))
        guard case .again = talk.take(try Self.reply([])) else { Issue.record("planned with no title"); return }
        #expect(talk.messages.last?["content"]?.stringValue?.contains("title") == true)
        _ = talk.take(try Self.reply([("add_text", #"{"text":"Base Components","x":40,"y":40,"fontSize":32}"#)]))
        #expect(talk.steps.map(\.tool) == ["add_text", "add_component"])
        guard case .planned = talk.take(try Self.reply([])) else { Issue.record("asked twice"); return }
    }

    @Test("A sheet offered after an unreadable reply is still asked for its title, once")
    func titleAfterAnUnreadableReply() throws {
        var talk = Self.sheet()
        _ = talk.take(try Self.reply([Self.component("Button", x: 40, y: 100, width: 120)]))
        let first = talk.askForTitle()
        #expect(first)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("title") == true)
        let second = talk.askForTitle()
        #expect(!second, "asked once")
    }

    @Test("Past a sheet's worth of components, more are refused and the model told to finish")
    func enoughComponents() throws {
        var talk = Self.sheet()
        for index in 0..<(AskConversation.mostComponents + 2) {
            _ = talk.take(try Self.reply([Self.component("Kind \(index)", x: 40, y: 100 + index * 60, width: 80 + index * 8, labels: false)]))
        }
        #expect(talk.steps.count == AskConversation.mostComponents)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("finish") == true)
    }

    @Test("A reply the model runner could not read as a call is told apart from other trouble")
    func unreadableReply() {
        #expect(AskConversation.isUnreadableReply("Failed to parse tool call arguments as JSON: [json.exception.parse_error.101] parse error at line 1"))
        #expect(!AskConversation.isUnreadableReply("Stopped. Nothing was changed."))
        #expect(!AskConversation.isUnreadableReply("the model is not running"))
    }

    @Test("The same step twice is refused, naming the step it repeats")
    func duplicateRefused() throws {
        var talk = Self.conversation()
        let call = ("add_text", #"{"text":"Hi","x":8,"y":8}"#)
        _ = talk.take(try Self.reply([call, call]))
        #expect(talk.steps.count == 1)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("step 1") == true)
    }

    @Test("Measuring a box already measured, give or take a few points, is refused")
    func sameBoxRefused() throws {
        var talk = Self.conversation()
        _ = talk.take(try Self.reply([
            ("add_measurement", #"{"kind":"size","box":{"x":96,"y":234,"width":1240,"height":90}}"#),
            ("add_measurement", #"{"kind":"size","box":{"x":96,"y":235,"width":1240,"height":89}}"#),
            ("add_measurement", #"{"kind":"size","box":{"x":1260,"y":167,"width":84,"height":48}}"#),
        ]))
        #expect(talk.steps.count == 2)
    }

    @Test("Elements are labelled by what they look like, controls first, the same box once")
    func elementsSorted() throws {
        let found = #"{"count":5,"elements":[{"x":64,"y":148,"width":1312,"height":264},{"x":96,"y":234,"width":1240,"height":90},{"x":96,"y":235,"width":1240,"height":89},{"x":116,"y":279,"width":4,"height":517},{"x":1260,"y":167,"width":84,"height":48}],"readsThePicture":true}"#
        let sorted = try AgentJSON.parse(Data(AskElements.sorted(found, canvasWidth: 1440).utf8))
        let elements = try #require(sorted["elements"]?.arrayValue)
        #expect(elements.map { $0["looksLike"]?.stringValue } == ["control", "card", "row", "strip"])
        #expect(elements.first?["width"] == 84)
    }

    @Test("A find_elements answer is sorted before the model reads it")
    func findElementsAnsweredSorted() throws {
        var talk = AskConversation(request: "measure", documentRead: #"{"canvas":{"width":1440,"height":960}}"#)
        guard case .again(let looks) = talk.take(try Self.reply([("find_elements", "{}")])) else { return }
        talk.answer(looks[0], with: #"{"elements":[{"x":0,"y":0,"width":1400,"height":80},{"x":10,"y":10,"width":84,"height":48}]}"#)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("control") == true)
    }

    @Test("A plan holds at most a dozen measurements, so the picture stays readable")
    func measurementCap() throws {
        var talk = Self.conversation()
        let calls = (0..<15).map { i in
            ("add_measurement", #"{"kind":"size","box":{"x":"# + "\(i * 100)" + #","y":0,"width":40,"height":40}}"#)
        }
        _ = talk.take(try Self.reply(calls))
        #expect(talk.steps.count == AskConversation.mostMeasurements)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("finish") == true)
    }

    @Test("A tool Ask does not offer is refused, even a real one")
    func unofferedRefused() throws {
        var talk = Self.conversation()
        _ = talk.take(try Self.reply([("export", #"{"format":"png","path":"/tmp/x.png"}"#)]))
        #expect(talk.steps.isEmpty)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("export") == true)
    }

    @Test("Words with no tool call end the plan, with the model's sentence as its summary")
    func finished() throws {
        var talk = Self.conversation()
        _ = talk.take(try Self.reply([("add_text", #"{"text":"Hi","x":8,"y":8}"#)]))
        let outcome = talk.take(try Self.reply([], content: "Adds a heading."))
        #expect(outcome == .planned(AskPlan(steps: talk.steps, summary: "Adds a heading.")))
    }

    @Test("No steps at all, asked twice, is the model saying it cannot, in its own short sentence")
    func cannot() throws {
        var talk = Self.conversation()
        // The first refusal is asked once more to try with the tools.
        #expect(talk.take(try Self.reply([], content: "I can't")) == .again(looks: []))
        #expect(talk.messages.last?["role"] == "user")
        let outcome = talk.take(try Self.reply([], content: "I can't change the sound of a picture."))
        #expect(outcome == .cannot("I can't change the sound of a picture."))
    }

    @Test("A model that writes its call as text instead of a tool call is still understood")
    func textToolCall() throws {
        var talk = Self.conversation()
        let content = #"{"name": "add_text", "arguments": {"text": "Hi", "x": 8, "y": 8}}</tool_call>"#
        let outcome = talk.take(try Self.reply([], content: content))
        #expect(outcome == .again(looks: []))
        #expect(talk.steps.map(\.tool) == ["add_text"])
    }

    @Test("Thinking a model prints before it answers is not shown as the summary")
    func thinkingDropped() throws {
        var talk = Self.conversation()
        _ = talk.take(try Self.reply([("add_text", #"{"text":"Hi","x":8,"y":8}"#)]))
        let outcome = talk.take(try Self.reply([], content: "<think>hmm</think>\nAdds a heading."))
        #expect(outcome == .planned(AskPlan(steps: talk.steps, summary: "Adds a heading.")))
    }

    @Test("The request body asks for no thinking, a big enough window, and offers the tools")
    func chatBody() {
        let talk = Self.conversation("make it pop")
        let body = talk.chatBody(model: "qwen3:30b")
        #expect(body["model"] == "qwen3:30b")
        #expect(body["stream"] == false)
        #expect(body["think"] == false)
        #expect((body["options"]?["num_ctx"]?.intValue ?? 0) >= 16384)
        #expect(body["tools"]?.arrayValue?.count == AskTools.modelTools.count)
        let messages = body["messages"]?.arrayValue ?? []
        #expect(messages.first?["role"] == "system")
        #expect(messages.first?["content"]?.stringValue?.contains(#""width":800"#) == true)
        #expect(messages.last?["content"] == "make it pop")
    }

    // MARK: Running a step

    @Test("A step names what a planned step made with $N, and runs on the asking document")
    func resolvesReferences() throws {
        let step = AskStep(tool: "set_layer", arguments: try Self.json(##"{"layer":"$2","fill":"#FF0000"}"##))
        let made = [2: "8C1A3E4B-0000-4000-8000-000000000000"]
        let request = try step.request(document: "d3", made: made).get()
        let direct = try AgentTools.request(tool: "set_layer", arguments: try Self.json(
            ##"{"document":"d3","layer":"8C1A3E4B-0000-4000-8000-000000000000","fill":"#FF0000"}"##)).get()
        #expect(request == direct)
    }

    @Test("References inside lists are resolved too")
    func resolvesInLists() throws {
        let step = AskStep(tool: "apply_style", arguments: try Self.json(#"{"style":"Accent","layers":["$1","$2"]}"#))
        let resolved = step.resolvedArguments(document: "d1", made: [1: "A", 2: "B"])
        #expect(resolved["layers"] == ["A", "B"])
        #expect(resolved["document"] == "d1")
    }

    @Test("What a step made is read from its answer: a layer, a clip or a title")
    func madeID() {
        #expect(AskStep.madeID(fromAnswer: #"{"layer":"L1","name":"Box"}"#) == "L1")
        #expect(AskStep.madeID(fromAnswer: #"{"clip":"C1","name":"Clip"}"#) == "C1")
        #expect(AskStep.madeID(fromAnswer: #"{"title":"T1","style":"Clean"}"#) == "T1")
        #expect(AskStep.madeID(fromAnswer: "Done.") == nil)
    }

    @Test("A plan knows whether a later step names what a step makes")
    func referenced() throws {
        let plan = AskPlan(steps: [
            AskStep(tool: "add_shape", arguments: try Self.json(#"{"kind":"rectangle"}"#)),
            AskStep(tool: "add_text", arguments: try Self.json(#"{"text":"A","x":0,"y":0}"#)),
            AskStep(tool: "apply_style", arguments: try Self.json(#"{"style":"S","layers":["$1"]}"#)),
        ], summary: "")
        #expect(plan.isNamedLater(1))
        #expect(!plan.isNamedLater(2))
        #expect(!plan.isNamedLater(3))
    }

    // MARK: Reading a plan

    @Test("A plan line names the tool and a short detail a person can read")
    func lines() throws {
        func line(_ tool: String, _ args: String) throws -> AskStep.Line {
            AskStep(tool: tool, arguments: try Self.json(args)).line
        }
        #expect(try line("add_text", #"{"text":"Choose Studio","x":0,"y":0}"#) == .init(name: "add_text", detail: "\u{201C}Choose Studio\u{201D}"))
        #expect(try line("add_measurement", #"{"kind":"size","box":{"x":0,"y":0,"width":120,"height":40}}"#).detail == "size 120 × 40")
        #expect(try line("add_shape", #"{"kind":"rectangle","box":{"x":0,"y":0,"width":320,"height":200}}"#).detail == "rectangle 320 × 200")
        #expect(try line("run_command", #"{"command":"group"}"#).detail == "group")
        #expect(try line("set_layer", ##"{"layer":"x","fill":"#FFFFFF","width":10}"##).detail == "fill, width")
        let long = try line("add_text", #"{"text":"A very long headline that goes on and on","x":0,"y":0}"#)
        #expect(long.detail.count <= AskStep.Line.detailBudget)
        #expect(long.detail.hasSuffix("\u{2026}\u{201D}"))
    }

    @Test("A placed component reads by the name list_components gave it")
    func componentNames() throws {
        var talk = Self.conversation()
        guard case .again(let looks) = talk.take(try Self.reply([("list_components", "{}")])) else { return }
        talk.answer(looks[0], with: #"[{"id":"C-1","name":"Card","from":"starter","detail":""}]"#)
        _ = talk.take(try Self.reply([("place_component", #"{"component":"C-1","x":100,"y":100}"#)]))
        guard case .planned(let plan) = talk.take(try Self.reply([], content: "Done.")) else { return }
        #expect(plan.line(1).detail == "Card")
    }

    @Test("The Library handed over up front is in the instructions, and names its components")
    func libraryUpFront() throws {
        var talk = AskConversation(request: "pricing", documentRead: "{}",
                                   components: #"[{"id":"C-1","name":"Card","from":"starter","detail":""}]"#,
                                   styles: ##"{"colors":[{"name":"Brand","hex":"#6E4BFF"}]}"##)
        let system = talk.messages.first?["content"]?.stringValue ?? ""
        #expect(system.contains("Card") && system.contains("Brand"))
        _ = talk.take(try Self.reply([("place_component", #"{"component":"C-1","x":1,"y":1}"#)]))
        guard case .planned(let plan) = talk.take(try Self.reply([], content: "Done.")) else { return }
        #expect(plan.line(1).detail == "Card")
    }

    @Test("A component named by its name reads by that name")
    func componentByName() throws {
        let step = AskStep(tool: "place_component", arguments: try Self.json(#"{"component":"Card","x":1,"y":1}"#))
        #expect(step.line.detail == "Card")
    }

    @Test("A video's title styles handed over up front are in the instructions")
    func titlesUpFront() {
        let talk = AskConversation(request: "add a title", documentRead: "{}", titles: #"[{"style":"Keynote Clean"}]"#)
        #expect(talk.messages.first?["content"]?.stringValue?.contains("Keynote Clean") == true)
    }

    @Test("A step with nothing else to say reads by the name it gives its layer")
    func nameFallback() throws {
        let step = AskStep(tool: "add_shape", arguments: try Self.json(#"{"name":"Backdrop"}"#))
        #expect(step.line.detail == "Backdrop")
    }

    // MARK: Which model

    @Test("Automatic picks the best measured model on the Mac that fits in its memory")
    func automaticModel() throws {
        let best = try #require(AskModels.ranked.first)
        let everything = AskModels.ranked.map(\.tag) + ["llama3.2-vision:latest"]
        #expect(AskModels.automatic(installed: everything, memoryGigabytes: 68.7) == best.tag)
        #expect(AskModels.automatic(installed: ["llama3.2-vision:latest", "qwen3:30b"], memoryGigabytes: 68.7) == "qwen3:30b")
        #expect(AskModels.automatic(installed: ["gemma3:4b"], memoryGigabytes: 68.7) == nil)
        #expect(AskModels.automatic(installed: [], memoryGigabytes: 68.7) == nil)
        // A smaller Mac skips what it cannot hold beside the app and a browser.
        let small = AskModels.automatic(installed: everything, memoryGigabytes: 34.4)
        let picked = try #require(AskModels.ranked.first { $0.tag == small })
        #expect(AskModels.fits(picked, memoryGigabytes: 34.4))
        #expect(!AskModels.fits(best, memoryGigabytes: 34.4))
        #expect(AskModels.ranked.prefix { $0.tag != small }.allSatisfy { !AskModels.fits($0, memoryGigabytes: 34.4) })
    }

    @Test("A model fits when it holds no more than three fifths of the Mac's memory")
    func fitsRule() {
        let model = AskModels.Choice(tag: "x", gigabytes: 30, download: 20, sees: true)
        #expect(AskModels.fits(model, memoryGigabytes: 68.7))
        #expect(!AskModels.fits(model, memoryGigabytes: 34.4))
        #expect(AskModels.fits(model, memoryGigabytes: 50))
    }

    @Test("A Mac with no model is offered the best one it can hold")
    func recommendedFitsTheMac() throws {
        #expect(AskModels.recommended(memoryGigabytes: 68.7) == AskModels.ranked.first)
        let small = try #require(AskModels.recommended(memoryGigabytes: 34.4))
        #expect(AskModels.fits(small, memoryGigabytes: 34.4))
        #expect(small != AskModels.ranked.first)
        #expect(AskModels.recommended(memoryGigabytes: 17.2) == nil)
    }

    @Test("The measured list is best first, every model in it plans with tools, and the default can see")
    func rankedList() throws {
        #expect(Set(AskModels.ranked.map(\.tag)).count == AskModels.ranked.count)
        #expect(try #require(AskModels.ranked.first).sees)
        #expect(AskModels.ranked.allSatisfy { $0.gigabytes > $0.download })
    }

    @Test("A model chosen in Settings wins while it is still on the Mac")
    func chosenModel() {
        #expect(AskModels.resolve(chosen: "qwen3:8b", installed: ["qwen3:8b", "qwen3:30b"], memoryGigabytes: 68.7) == "qwen3:8b")
        #expect(AskModels.resolve(chosen: "gone:1b", installed: ["qwen3:30b"], memoryGigabytes: 68.7) == "qwen3:30b")
        #expect(AskModels.resolve(chosen: nil, installed: ["qwen3:30b"], memoryGigabytes: 68.7) == "qwen3:30b")
    }
}

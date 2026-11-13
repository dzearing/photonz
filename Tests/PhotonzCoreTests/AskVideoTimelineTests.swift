import Foundation
import Testing
@testable import PhotonzCore

/// Ask on a video reaches what the agent skill reaches for a timeline: the
/// recordings in History and add_clip to put one on, and (for a model that
/// sees) frames of the video to find a moment by what happens in it.
@Suite("Ask on a video: History, add_clip and frames")
struct AskVideoTimelineTests {

    static let videoRead = #"{"kind":"video","canvas":{"width":1280,"height":800},"durationSeconds":8}"#
    static let pictureRead = #"{"kind":"picture","canvas":{"width":800,"height":600}}"#

    static func offered(_ talk: AskConversation) -> [String] {
        (talk.chatBody(model: "m")["tools"]?.arrayValue ?? []).compactMap { $0["function"]?["name"]?.stringValue }
    }

    /// A 1 by 1 PNG header is enough for the token estimate to read a size.
    static let png: Data = {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
        bytes += [0, 0, 2, 0, 0, 0, 1, 0x40]
        return Data(bytes)
    }()

    @Test("A video is offered list_history to look and add_clip to plan; a picture is offered neither")
    func historyAndAddClipOnAVideo() {
        let video = AskConversation(request: "put my latest recording after this one", documentRead: Self.videoRead)
        let names = Self.offered(video)
        #expect(names.contains("list_history"))
        #expect(names.contains("add_clip"))
        #expect(AskTools.looking.contains("list_history"))
        #expect(AskTools.doing.contains("add_clip"))
        let picture = AskConversation(request: "put my latest recording after this one", documentRead: Self.pictureRead)
        #expect(!Self.offered(picture).contains("list_history"))
        #expect(!Self.offered(picture).contains("add_clip"))
    }

    @Test("list_history is run as a look and add_clip is planned as a step")
    func historyLooksAndClipPlans() throws {
        var talk = AskConversation(request: "put my latest recording after this one", documentRead: Self.videoRead)
        let looked = talk.take(try AskPlanningTests.reply([("list_history", "{}")]))
        #expect(looked == .again(looks: [AskLook(tool: "list_history", arguments: [:])]))
        _ = talk.take(try AskPlanningTests.reply([("add_clip", #"{"historyIndex": 2}"#)]))
        #expect(talk.steps.map(\.tool) == ["add_clip"])
        let request = try talk.steps[0].request(document: "d1", made: [:]).get()
        #expect(request == .addClip(document: "d1", clip: .history(index: 2), atMS: nil, track: nil))
    }

    @Test("A look runs on the asking document when its tool takes one, and list_history, which takes none, still runs")
    func looksTakeTheDocumentOnlyWhenTheyCan() throws {
        let history = try AskLook(tool: "list_history", arguments: [:]).request(document: "d1").get()
        #expect(history == .listHistory(limit: 20))
        let read = try AskLook(tool: "read_document", arguments: [:]).request(document: "d1").get()
        if case .readDocument(let document, _, _) = read { #expect(document == "d1") } else { Issue.record("not a read: \(read)") }
        let sheet = try AskLook(tool: "contact_sheet", arguments: ["count": 6]).request(document: "d1").get()
        if case .contactSheet(let document, _, _, let count, _, _) = sheet {
            #expect(document == "d1" && count == 6)
        } else {
            Issue.record("not a sheet: \(sheet)")
        }
    }

    @Test("Frames are offered on a video only to a model that sees, and named in the rules")
    func framesOnlyForAModelThatSees() {
        let sees = AskConversation(request: "cut where the copying starts", documentRead: Self.videoRead, sees: true)
        #expect(Self.offered(sees).contains("contact_sheet"))
        let system = sees.messages.first?["content"]?.stringValue ?? ""
        #expect(system.contains("contact_sheet"))
        let blind = AskConversation(request: "cut where the copying starts", documentRead: Self.videoRead)
        #expect(!Self.offered(blind).contains("contact_sheet"))
        let blindRules = blind.messages.first?["content"]?.stringValue ?? ""
        #expect(blindRules.range(of: "contact_sheet") == nil, "\(blindRules.components(separatedBy: "contact_sheet").first?.suffix(200) ?? "")")
        let picture = AskConversation(request: "cut where the copying starts", documentRead: Self.pictureRead, sees: true)
        #expect(!Self.offered(picture).contains("contact_sheet"))
    }

    @Test("A sheet asked for is held to a size the window can take")
    func sheetIsKeptSmall() throws {
        var talk = AskConversation(request: "cut where the copying starts", documentRead: Self.videoRead, sees: true)
        let outcome = talk.take(try AskPlanningTests.reply([
            ("contact_sheet", #"{"fromSeconds": 1, "toSeconds": 3, "count": 48, "cellWidth": 640}"#),
        ]))
        guard case .again(let looks) = outcome, let look = looks.first else {
            Issue.record("the sheet was not handed back as a look: \(outcome)")
            return
        }
        #expect(look.tool == "contact_sheet")
        #expect(look.arguments["count"]?.intValue == AskConversation.mostSheetFrames)
        #expect(look.arguments["cellWidth"]?.intValue == AskConversation.sheetCellWidth)
        #expect(look.arguments["fromSeconds"]?.doubleValue == 1)
    }

    @Test("A sheet's picture follows the tool's answer in a message of its own, as the model sees")
    func sheetPictureGoesToTheModel() throws {
        var talk = AskConversation(request: "cut where the copying starts", documentRead: Self.videoRead, sees: true)
        _ = talk.take(try AskPlanningTests.reply([("contact_sheet", "{}")]))
        let look = AskLook(tool: "contact_sheet", arguments: [:])
        talk.answer(look, with: "Tutorial Sample.mp4: 12 frames at 0:00.0, 0:00.7", picture: Self.png)
        talk.showPictures()
        let messages = talk.chatBody(model: "m")["messages"]?.arrayValue ?? []
        let tool = try #require(messages.dropLast().last)
        #expect(tool["role"] == "tool")
        #expect(tool["content"]?.stringValue?.contains("12 frames") == true)
        let shown = try #require(messages.last)
        #expect(shown["role"] == "user")
        #expect(shown["images"]?.arrayValue?.first?.stringValue == Self.png.base64EncodedString())
        // Nothing is said twice: with no picture held, nothing more is added.
        let count = talk.messages.count
        talk.showPictures()
        #expect(talk.messages.count == count)
    }

    @Test("After the most sheets a request may look at, another is answered in words, with no picture")
    func sheetsAreCounted() throws {
        var talk = AskConversation(request: "cut where the copying starts", documentRead: Self.videoRead, sees: true)
        for _ in 0..<AskConversation.mostSheets {
            guard case .again(let looks) = talk.take(try AskPlanningTests.reply([("contact_sheet", "{}")])) else {
                Issue.record("a sheet within the limit was not looked at")
                return
            }
            #expect(looks.count == 1)
            for look in looks { talk.answer(look, with: "frames", picture: Self.png) }
            talk.showPictures()
        }
        let outcome = talk.take(try AskPlanningTests.reply([("contact_sheet", "{}")]))
        #expect(outcome == .again(looks: []))
        let said = talk.messages.last?["content"]?.stringValue ?? ""
        #expect(said.hasPrefix("Not looked at"))
    }

    @Test("When the talk outgrows the window, a sheet's picture goes before any words do")
    func sheetGoesWhenTheWindowIsFull() throws {
        var talk = AskConversation(request: "cut where the copying starts", documentRead: Self.videoRead,
                                   window: 1, sees: true)
        _ = talk.take(try AskPlanningTests.reply([("contact_sheet", "{}")]))
        talk.answer(AskLook(tool: "contact_sheet", arguments: [:]), with: "frames", picture: Self.png)
        talk.showPictures()
        #expect(talk.messages.last?["images"] != nil)
        let fitted = talk.fittedMessages()
        #expect(fitted.last?["images"] == nil)
        #expect(fitted.last?["content"]?.stringValue == AskConversation.sheetLeftOut)
    }

    @Test("A clip added says so in the plan's row")
    func clipRow() {
        let step = AskStep(tool: "add_clip", arguments: ["historyIndex": 2])
        #expect(AskChangeWords.sentence([step]).contains("clip"))
    }
}

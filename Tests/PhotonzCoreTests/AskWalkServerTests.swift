import Foundation
@testable import PhotonzCore
import Testing

/// Walks share one Ask model server (`AskWalkServer`): every walk starts a new
/// probe, and before this every probe loaded the whole model (about 23 GB) for
/// itself. Inside a walk run the first probe that needs the model starts one
/// server outside itself, gently, and every later walk adopts it.
@Suite("Ask: walks share one model server")
struct AskWalkServerTests {

    static let folder = "/Users/someone/Library/Application Support/Photonz/Models"
    static let record = AskWalkServer.Record(model: "qwen3.8-27b", port: 18_444, folder: folder, draft: true)

    // MARK: Adopt, start or keep its own

    @Test("Outside a walk Photonz always runs its own server, whatever is recorded")
    func outsideAWalkIsAlwaysItsOwn() {
        #expect(AskWalkServer.use(walkShares: false, model: "qwen3.8-27b", folder: Self.folder,
                                  record: Self.record, serverAlive: true) == .own)
        #expect(AskWalkServer.use(walkShares: false, model: "qwen3.8-27b", folder: Self.folder,
                                  record: nil, serverAlive: false) == .own)
    }

    @Test("The first walk that needs the model starts the shared server")
    func firstWalkStartsIt() {
        #expect(AskWalkServer.use(walkShares: true, model: "qwen3.8-27b", folder: Self.folder,
                                  record: nil, serverAlive: false) == .start)
    }

    @Test("A walk adopts the shared server when it runs the same model from the same folder")
    func laterWalksAdopt() {
        #expect(AskWalkServer.use(walkShares: true, model: "qwen3.8-27b", folder: Self.folder,
                                  record: Self.record, serverAlive: true) == .adopt(port: 18_444))
    }

    @Test("A record whose server is gone is started over, never adopted")
    func deadServerIsStartedAgain() {
        #expect(AskWalkServer.use(walkShares: true, model: "qwen3.8-27b", folder: Self.folder,
                                  record: Self.record, serverAlive: false) == .start)
    }

    @Test("A walk that wants another model gets its own, and the shared one is left alone")
    func anotherModelRunsItsOwn() {
        #expect(AskWalkServer.use(walkShares: true, model: "qwen3.6-35b-a3b", folder: Self.folder,
                                  record: Self.record, serverAlive: true) == .own)
    }

    @Test("A walk with its own models folder gets its own server")
    func anotherFolderRunsItsOwn() {
        #expect(AskWalkServer.use(walkShares: true, model: "qwen3.8-27b", folder: "/tmp/photonz-walk-ask-models",
                                  record: Self.record, serverAlive: true) == .own)
    }

    @Test("A walk shares only when its setup leaves the Mac's models as they are")
    func whichWalksShare() {
        #expect(AskWalkServer.walkShares(modelMissing: false, modelsOnly: nil))
        #expect(!AskWalkServer.walkShares(modelMissing: true, modelsOnly: nil))
        #expect(!AskWalkServer.walkShares(modelMissing: false, modelsOnly: ["qwen3.8-27b"]))
        #expect(!AskWalkServer.walkShares(modelMissing: false, modelsOnly: []))
    }

    // MARK: Gentle settings

    @Test("The shared server runs gently: small batches, low priority, no busy polling, four threads")
    func gentleArguments() throws {
        let choice = try #require(AskBuiltInModels.choice(id: "qwen3.8-27b"))
        let base = AskBuiltInServerPlan.arguments(for: choice, in: URL(fileURLWithPath: Self.folder), port: 18_444,
                                                  draftOnDisk: true)
        let gentle = AskWalkServer.arguments(base)
        func value(_ flag: String) -> String? {
            gentle.firstIndex(of: flag).flatMap { gentle.indices.contains($0 + 1) ? gentle[$0 + 1] : nil }
        }
        #expect(value("--ubatch-size") == "128")
        #expect(value("--batch-size") == "512")
        #expect(value("--prio") == "-1")
        #expect(value("--poll") == "0")
        #expect(value("--threads") == "4")
        // Everything the app's own server is given is still there, unchanged.
        #expect(Array(gentle.prefix(base.count)) == base)
        // Each flag once: a second copy would leave llama.cpp to pick.
        for flag in ["--ubatch-size", "--batch-size", "--prio", "--poll", "--threads"] {
            #expect(gentle.filter { $0 == flag }.count == 1)
        }
    }

    @Test("Gentle settings replace a value the base already gives rather than repeat it")
    func gentleReplaces() {
        let gentle = AskWalkServer.arguments(["--model", "m.gguf", "--threads", "12", "--port", "1"])
        #expect(gentle.filter { $0 == "--threads" }.count == 1)
        #expect(gentle.firstIndex(of: "--threads").map { gentle[$0 + 1] } == "4")
        #expect(gentle.contains("--model") && gentle.contains("m.gguf"))
        #expect(gentle.firstIndex(of: "--port").map { gentle[$0 + 1] } == "1")
    }

    @Test("The shared server is run under the Mac's background policy")
    func backgroundPolicy() {
        let line = AskWalkServer.command(server: "/x/llama-server", arguments: ["--port", "1"])
        #expect(line == ["/usr/sbin/taskpolicy", "-b", "/x/llama-server", "--port", "1"])
    }

    // MARK: Its life

    @Test("It lets go after a few idle minutes, sooner than the app's own")
    func idleRule() {
        #expect(AskWalkServer.idleSeconds >= 60)
        #expect(AskWalkServer.idleSeconds <= AskBuiltInServerPlan.idleSeconds)
    }

    @Test("Its watch stops it when the run is gone, when idle, and on a signal")
    func watchStopsIt() {
        let watch = AskWalkServer.watchScript
        // The run that owns it.
        #expect(watch.contains("RUN_PID"))
        #expect(watch.contains("kill -0 \"$RUN_PID\""))
        // The idle clock, refreshed while it is answering.
        #expect(watch.contains("is_processing"))
        #expect(watch.contains("last-used"))
        // A stop: TERM ends the server too, and the record goes with it.
        #expect(watch.contains("trap"))
        #expect(watch.contains("record.json"))
    }

    @Test("Its record reads back as written, and anything else reads as none")
    func recordRoundTrips() throws {
        let data = try AskWalkServer.encode(Self.record)
        #expect(AskWalkServer.decode(data) == Self.record)
        #expect(AskWalkServer.decode(Data("not json".utf8)) == nil)
        #expect(AskWalkServer.decode(Data()) == nil)
    }

    @Test("The pid file names the server first and its watch second")
    func pidFile() {
        #expect(AskWalkServer.pids(fromPidFile: "123 456\n") == AskWalkServer.Pids(server: 123, watch: 456))
        #expect(AskWalkServer.pids(fromPidFile: "123") == nil)
        #expect(AskWalkServer.pids(fromPidFile: "") == nil)
        #expect(AskWalkServer.pids(fromPidFile: "0 456") == nil)
    }

    @Test("Its files live in one folder every build and script finds the same way")
    func folderIsFixed() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(AskWalkServer.folder(home: home).path == "/Users/someone/Library/Caches/Photonz/ask-walk-server")
    }
}

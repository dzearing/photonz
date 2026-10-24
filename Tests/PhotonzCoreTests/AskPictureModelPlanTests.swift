import Foundation
@testable import PhotonzCore
import Testing

/// The picture model Ask paints its drawings with is set up and run by
/// Photonz itself (`docs/design/ask.md`, "The picture model"): its weights are
/// a pinned download, its tools are a private environment Photonz builds with
/// the `uv` it ships, and its server runs offline on a port Photonz picks.
/// Nobody installs Python, runs a script or keeps anything open.
@Suite("Ask: the picture model Photonz sets up and runs")
struct AskPictureModelPlanTests {

    let folder = URL(fileURLWithPath: "/Users/someone/Library/Application Support/Photonz/Models")

    @Test("The weights are pinned files with sizes, under the model's own folder")
    func weightsArePinned() {
        let files = AskPictureModelPlan.modelFiles
        #expect(files.count == 13)
        for file in files {
            #expect(file.bytes > 0)
            #expect(file.name.hasPrefix(AskPictureModelPlan.id + "/"), "\(file.name)")
            #expect(file.url.host() == "huggingface.co")
            #expect(file.url.path().contains("/resolve/\(AskPictureModelPlan.revision)/"), "\(file.url)")
            #expect(file.url.path().hasSuffix(String(file.name.dropFirst(AskPictureModelPlan.id.count + 1))))
        }
        #expect(Set(files.map(\.name)).count == files.count)
        // About 11 GB of weights, the transformer, text encoder and decoder.
        let weights = files.reduce(Int64(0)) { $0 + $1.bytes }
        #expect(weights > 10_500_000_000 && weights < 11_500_000_000, "\(weights)")
        #expect(AskPictureModelPlan.downloadBytes == weights + AskPictureModelPlan.toolsBytes)
        #expect(AskBuiltInModels.sizeWords(AskPictureModelPlan.downloadBytes) == "11.2 GB")
    }

    @Test("Its tools are exact versions, with nothing the picture never uses")
    func toolsArePinnedAndLean() {
        let packages = AskPictureModelPlan.packages
        #expect(!packages.isEmpty)
        for package in packages {
            #expect(package.split(separator: "=").count == 2 && package.contains("=="), "\(package)")
        }
        let names = packages.map { String($0.prefix { $0 != "=" }) }
        for needed in ["mflux", "mlx", "mlx-metal", "vtracer", "numpy", "pillow", "transformers", "safetensors"] {
            #expect(names.contains(needed), "\(needed)")
        }
        // Torch, OpenCV and matplotlib are mflux's for other models: about
        // 700 MB a person would download for nothing.
        for unneeded in ["torch", "opencv-python", "matplotlib", "sympy"] {
            #expect(!names.contains(unneeded), "\(unneeded)")
        }
    }

    @Test("Everything it keeps lives in the models folder")
    func layout() {
        let tools = AskPictureModelPlan.toolsFolder(in: folder)
        #expect(tools.path == folder.path + "/picture-tools")
        #expect(AskPictureModelPlan.modelFolder(in: folder).path == folder.path + "/" + AskPictureModelPlan.id)
        #expect(AskPictureModelPlan.python(in: folder).path == tools.path + "/env/bin/python")
        #expect(AskPictureModelPlan.stampFile(in: folder).path.hasPrefix(tools.path))
    }

    @Test("Setting up the tools is two runs of the uv Photonz ships, kept inside the tools folder")
    func setupCommands() {
        let commands = AskPictureModelPlan.setupCommands(in: folder)
        #expect(commands.count == 2)
        let tools = AskPictureModelPlan.toolsFolder(in: folder).path
        #expect(commands[0].prefix(2) == ["venv", "--python"])
        #expect(commands[0].contains(AskPictureModelPlan.pythonVersion))
        #expect(commands[0].last == tools + "/env")
        #expect(commands[1].prefix(2) == ["pip", "install"])
        #expect(commands[1].contains("--no-deps"))
        #expect(Array(commands[1].suffix(AskPictureModelPlan.packages.count)) == AskPictureModelPlan.packages)
        let environment = AskPictureModelPlan.setupEnvironment(in: folder)
        // uv's Python and its download cache stay in the tools folder, never
        // in the person's own ~/.cache or ~/.local, and it reads no
        // configuration of theirs.
        #expect(environment["UV_PYTHON_INSTALL_DIR"]?.hasPrefix(tools) == true)
        #expect(environment["UV_CACHE_DIR"]?.hasPrefix(tools) == true)
        #expect(environment["UV_PYTHON_PREFERENCE"] == "only-managed")
        #expect(environment["UV_NO_CONFIG"] == "1")
    }

    @Test("The tools count as set up only when they match this build's list")
    func stamp() {
        let stamp = AskPictureModelPlan.toolsStamp
        #expect(stamp.contains(AskPictureModelPlan.pythonVersion))
        for package in AskPictureModelPlan.packages { #expect(stamp.contains(package)) }
        #expect(AskPictureModelPlan.toolsMatch(stamp: stamp))
        #expect(!AskPictureModelPlan.toolsMatch(stamp: nil))
        #expect(!AskPictureModelPlan.toolsMatch(stamp: stamp + "\nmflux==0.1.0"))
    }

    @Test("The server runs offline on a port Photonz picks, away from the chat model's and Ollama's")
    func server() throws {
        for _ in 0..<200 {
            let port = AskPictureModelPlan.pickPort()
            #expect(AskPictureModelPlan.ports.contains(port))
            #expect(!AskBuiltInServerPlan.ports.contains(port))
            #expect(port != AskRuntime.ollamaPort)
        }
        let environment = AskPictureModelPlan.serverEnvironment(in: folder, port: 18_950)
        #expect(environment["PHOTONZ_PICTURE_PORT"] == "18950")
        #expect(environment["PHOTONZ_PICTURE_MODEL"] == AskPictureModelPlan.modelFolder(in: folder).path)
        #expect(environment["HF_HUB_OFFLINE"] == "1")
        #expect(environment["HF_HOME"]?.hasPrefix(AskPictureModelPlan.toolsFolder(in: folder).path) == true)
        // Python never writes compiled files into the signed app bundle.
        #expect(environment["PYTHONPYCACHEPREFIX"]?.hasPrefix(AskPictureModelPlan.toolsFolder(in: folder).path) == true)
        #expect(environment["PYTHONNOUSERSITE"] == "1")
        #expect(environment["PYTHONPATH"] == nil)
        let script = URL(fileURLWithPath: "/Applications/Photonz.app/Contents/Helpers/PictureModel/server.py")
        #expect(AskPictureModelPlan.serverArguments(script: script) == ["-I", script.path])
        let base = try #require(AskPictureModelPlan.base(port: 18_950))
        #expect(base.host() == "127.0.0.1")
        #expect(base.port == 18_950)
    }

    @Test("It is offered only on a Mac that can hold it beside the chat model")
    func fits() throws {
        let chat = try #require(AskBuiltInModels.choice(id: "qwen3.6-35b-a3b"))
        #expect(AskPictureModelPlan.fits(memoryGigabytes: 64, beside: chat))
        #expect(!AskPictureModelPlan.fits(memoryGigabytes: 48, beside: chat))
        // The default since 2026-10-24 still leaves room for it on a 64 GB Mac.
        let newer = try #require(AskBuiltInModels.choice(id: "qwen3.8-27b"))
        #expect(AskPictureModelPlan.fits(memoryGigabytes: 64, beside: newer))
        #expect(AskPictureModelPlan.fits(memoryGigabytes: 24, beside: nil))
        #expect(!AskPictureModelPlan.fits(memoryGigabytes: 16, beside: nil))
    }

    @Test("A pinned file this Mac already keeps for the Hugging Face tools is found there, not downloaded again")
    func huggingFaceCache() throws {
        let home = URL(fileURLWithPath: "/Users/someone")
        let file = try #require(AskPictureModelPlan.modelFiles.first { $0.name.hasSuffix("transformer/0.safetensors") })
        let cached = try #require(AskBuiltInModels.huggingFaceCache(for: file.url, home: home))
        #expect(cached.path == "/Users/someone/.cache/huggingface/hub/models--mflux-community--z-image-turbo-mflux-q8"
                + "/snapshots/\(AskPictureModelPlan.revision)/transformer/0.safetensors")
        let chat = try #require(AskBuiltInModels.ranked.first).model
        #expect(AskBuiltInModels.huggingFaceCache(for: chat.url, home: home)?.lastPathComponent == chat.name)
        #expect(AskBuiltInModels.huggingFaceCache(for: URL(fileURLWithPath: "/dev/null"), home: home) == nil)
        #expect(AskBuiltInModels.huggingFaceCache(
            for: try #require(URL(string: "https://example.com/a/b/resolve/r/f")), home: home) == nil)
    }
}

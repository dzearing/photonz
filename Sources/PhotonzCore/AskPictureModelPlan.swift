import Foundation

/// The picture model Ask paints its drawings with, set up and run by Photonz
/// (`docs/design/ask.md`, "The picture model"): Z-Image Turbo (Apache 2.0),
/// run by mflux (MIT) on MLX and traced into layers by vtracer (MIT), behind a
/// loopback port.
///
/// Settings > Ask downloads the weights (pinned files, like the chat model's)
/// and builds the tools: a private Python environment made by the `uv` Photonz
/// ships in its bundle, holding exactly `packages` and nothing of the person's.
/// Photonz then starts the server the first time Ask paints and lets it go
/// after a few idle minutes or when it quits. Nobody installs Python, runs a
/// script or keeps a program open.
public enum AskPictureModelPlan {

    public static let id = "z-image-turbo-q8"
    public static let name = "Z-Image Turbo"
    public static let repo = "mflux-community/z-image-turbo-mflux-q8"
    public static let revision = "4ccff28917346aa9daae49cd3c477cf5260a242c"

    private static func file(_ path: String, _ bytes: Int64) -> AskBuiltInModels.File {
        // A literal address: only a typo could make it nil, and the tests read every one.
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(path)")
            ?? URL(fileURLWithPath: "/dev/null")
        return AskBuiltInModels.File(name: "\(id)/\(path)", url: url, bytes: bytes)
    }

    /// The weights, in the folder layout mflux reads from a local path.
    public static let modelFiles: [AskBuiltInModels.File] = [
        file("tokenizer/tokenizer_config.json", 692),
        file("tokenizer/tokenizer.json", 11_422_650),
        file("tokenizer/chat_template.jinja", 4168),
        file("transformer/model.safetensors.index.json", 61606),
        file("transformer/0.safetensors", 2_134_613_189),
        file("transformer/1.safetensors", 2_146_080_675),
        file("transformer/2.safetensors", 2_130_413_997),
        file("transformer/3.safetensors", 129_578_808),
        file("text_encoder/model.safetensors.index.json", 51332),
        file("text_encoder/0.safetensors", 2_145_936_704),
        file("text_encoder/1.safetensors", 2_128_216_857),
        file("vae/model.safetensors.index.json", 17378),
        file("vae/0.safetensors", 165_702_761),
    ]

    /// About what the tools download: Python itself and the packages' wheels
    /// (about 450 MB once unpacked).
    public static let toolsBytes: Int64 = 200_000_000

    public static var downloadBytes: Int64 { modelFiles.reduce(toolsBytes) { $0 + $1.bytes } }

    /// Memory the server holds once loaded, in GB (11.2 measured resident on
    /// 2026-10-22, M4 Max). While it paints a picture MLX briefly asks for
    /// more, up to about 25 GB, and gives it back after.
    public static let gigabytes = 12.0

    /// Whether a Mac can hold it beside the chat model Ask uses.
    public static func fits(memoryGigabytes: Double, beside chat: AskBuiltInModels.Choice?) -> Bool {
        (chat?.gigabytes ?? 0) + gigabytes <= memoryGigabytes * AskModels.memoryShare
    }

    // MARK: The tools

    public static let pythonVersion = "3.12.11"

    /// Exactly what the server imports, at exact versions, installed without
    /// their declared extras: mflux declares torch, OpenCV and matplotlib for
    /// other models it runs, about 700 MB this one never touches (measured
    /// 2026-10-22: a picture painted and traced with none of them present).
    public static let packages: [String] = [
        "annotated-doc==0.0.5", "anyio==4.15.1", "certifi==2026.10.19", "charset-normalizer==3.5.2",
        "click==8.5.0", "filelock==4.2.4", "fonttools==4.67.0", "fsspec==2026.9.0", "h11==0.16.0",
        "httpcore==1.0.9", "httpx==0.28.1", "huggingface-hub==1.33.0", "idna==3.20", "jinja2==3.1.6",
        "markdown-it-py==4.2.0", "markupsafe==3.0.4", "mdurl==0.1.2", "mflux==0.23.0", "mlx==0.32.4",
        "mlx-metal==0.32.4", "numpy==2.5.4", "packaging==26.3", "piexif==1.1.3", "pillow==12.3.0",
        "platformdirs==4.13.5", "protobuf==7.36.2", "pygments==2.21.0", "pyyaml==6.0.3", "regex==2026.9.29",
        "requests==2.34.2", "rich==15.0.0", "safetensors==0.8.0", "sentencepiece==0.2.2", "shellingham==1.5.4",
        "tokenizers==0.23.3", "toml==0.10.2", "tqdm==4.70.1", "transformers==5.20.2", "typer==0.27.3",
        "typing-extensions==4.16.0", "tzdata==2026.5", "urllib3==2.8.0", "vtracer==0.6.15",
    ]

    public static func toolsFolder(in folder: URL) -> URL { folder.appending(path: "picture-tools") }
    public static func modelFolder(in folder: URL) -> URL { folder.appending(path: id) }
    public static func python(in folder: URL) -> URL { toolsFolder(in: folder).appending(path: "env/bin/python") }

    /// Written once the tools are installed; holds `toolsStamp`.
    public static func stampFile(in folder: URL) -> URL { toolsFolder(in: folder).appending(path: "installed.txt") }

    /// What a finished install wrote: a build whose list differs installs again.
    public static var toolsStamp: String { ([pythonVersion] + packages).joined(separator: "\n") }

    public static func toolsMatch(stamp: String?) -> Bool { stamp == toolsStamp }

    /// The arguments of each `uv` run that builds the tools, in order.
    public static func setupCommands(in folder: URL) -> [[String]] {
        let env = toolsFolder(in: folder).appending(path: "env").path
        return [
            ["venv", "--python", pythonVersion, "--clear", env],
            ["pip", "install", "--python", python(in: folder).path, "--no-deps", "--only-binary", ":all:"] + packages,
        ]
    }

    /// `uv`'s environment for those runs: its Python and its cache inside the
    /// tools folder, and nothing read from the person's own setup.
    public static func setupEnvironment(in folder: URL) -> [String: String] {
        let tools = toolsFolder(in: folder).path
        return [
            "UV_PYTHON_INSTALL_DIR": tools + "/python",
            "UV_CACHE_DIR": tools + "/cache",
            "UV_PYTHON_PREFERENCE": "only-managed",
            "UV_NO_CONFIG": "1",
            "UV_NO_PROGRESS": "1",
        ]
    }

    // MARK: The server

    /// Ports Photonz picks from: away from the chat model's
    /// (`AskBuiltInServerPlan.ports`) and Ollama's.
    public static let ports: ClosedRange<Int> = 18_900...19_699

    public static func pickPort() -> Int { Int.random(in: ports) }

    public static func base(port: Int) -> URL? { URL(string: "http://127.0.0.1:\(port)") }

    /// The server's environment, offline: everything is already on the Mac,
    /// and Python writes nothing into the app bundle.
    public static func serverEnvironment(in folder: URL, port: Int) -> [String: String] {
        let tools = toolsFolder(in: folder).path
        return [
            "PHOTONZ_PICTURE_PORT": String(port),
            "PHOTONZ_PICTURE_MODEL": modelFolder(in: folder).path,
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_HUB_DISABLE_TELEMETRY": "1",
            "HF_HOME": tools + "/hf",
            "PYTHONPYCACHEPREFIX": tools + "/pycache",
            "PYTHONNOUSERSITE": "1",
        ]
    }

    public static func serverArguments(script: URL) -> [String] { ["-I", script.path] }
}

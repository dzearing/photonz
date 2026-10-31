import Foundation

/// One Ask model server for a whole walk run (`docs/design/ask.md`, "Walks
/// share one model").
///
/// Every walk starts a new probe, and every probe used to load the whole model
/// for itself: about 23 GB and the GPU flat out for a minute or more, a dozen
/// times in a row in a walk check with a dozen Ask walks. Now the first probe
/// in a run that needs the model starts one server OUTSIDE itself, gently, and
/// every later probe in the run adopts it. A small watch lets it go when the
/// run that owns it is gone, or after a few idle minutes; the walk scripts and
/// the go loop stop it on their way out (`Scripts/ask-walk-server.sh`).
///
/// Only walks share. A person's Ask (the dev app, the release app) starts and
/// lets go of its own server exactly as before, and so does a walk that sets
/// up its own models (`askModelMissing`, `askModelsOnly`) or wants a model the
/// shared server is not running.
public enum AskWalkServer {

    /// What the shared server is running, written beside it by whoever started it.
    public struct Record: Codable, Sendable, Equatable {
        /// The model's id (`AskBuiltInModels.Choice.id`).
        public var model: String
        public var port: Int
        /// The models folder it loaded from.
        public var folder: String
        /// Whether it was started with the model's draft.
        public var draft: Bool

        public init(model: String, port: Int, folder: String, draft: Bool) {
            self.model = model
            self.port = port
            self.folder = folder
            self.draft = draft
        }
    }

    public enum Use: Sendable, Equatable {
        /// Run a server of its own, tied to this app, as a person's Ask does.
        case own
        /// Use the shared server on this port.
        case adopt(port: Int)
        /// Start the shared server, for this walk and the ones after it.
        case start
    }

    /// Whether a walk's setup leaves the Mac's models as they are, so its Ask
    /// can share: one that empties them or keeps only some sets up its own.
    public static func walkShares(modelMissing: Bool, modelsOnly: [String]?) -> Bool {
        !modelMissing && modelsOnly == nil
    }

    /// What a probe does for `model` from `folder`, given what is recorded and
    /// whether that recorded server is still there.
    public static func use(walkShares: Bool, model: String, folder: String, record: Record?,
                           serverAlive: Bool) -> Use {
        guard walkShares else { return .own }
        guard let record, serverAlive else { return .start }
        guard record.model == model, record.folder == folder else { return .own }
        return .adopt(port: record.port)
    }

    /// The gentle settings, measured on 2026-10-25 and again on 2026-10-30
    /// (`docs/design/ask.md`): smaller GPU batches, low thread priority, no
    /// busy polling for work, four threads. A walk loses about a tenth of the
    /// speed and the rest of the Mac keeps its GPU.
    public static let gentle: [(flag: String, value: String)] = [
        ("--ubatch-size", "128"),
        ("--batch-size", "512"),
        ("--prio", "-1"),
        ("--poll", "0"),
        ("--threads", "4"),
    ]

    /// `base` (the app's own command line) with the gentle settings, each
    /// replacing a value `base` already gives rather than repeating it.
    public static func arguments(_ base: [String]) -> [String] {
        var args = base
        for (flag, value) in gentle {
            if let at = args.firstIndex(of: flag), args.indices.contains(at + 1) {
                args[at + 1] = value
            } else {
                args += [flag, value]
            }
        }
        return args
    }

    /// The command line, under the Mac's background policy (`taskpolicy -b`:
    /// background priority for its CPU, disk and GPU work).
    public static func command(server: String, arguments: [String]) -> [String] {
        ["/usr/sbin/taskpolicy", "-b", server] + arguments
    }

    /// How long it stays loaded with nothing asked of it. Shorter than the
    /// app's own five minutes: walks follow each other within seconds, and a
    /// run that ended without saying so should not hold 23 GB for long.
    public static let idleSeconds: TimeInterval = 180

    /// Where its record, pid file, idle clock and log live: one folder every
    /// build of Photonz and every script finds the same way.
    public static func folder(home: URL) -> URL {
        home.appending(path: "Library/Caches/Photonz/ask-walk-server")
    }

    public struct Pids: Sendable, Equatable {
        public var server: Int32
        public var watch: Int32
    }

    /// `server.pid`: "<server pid> <watch pid>", written by the watch.
    public static func pids(fromPidFile text: String) -> Pids? {
        let fields = text.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
        guard fields.count >= 2, fields[0] > 0, fields[1] > 0 else { return nil }
        return Pids(server: fields[0], watch: fields[1])
    }

    public static func encode(_ record: Record) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }

    public static func decode(_ data: Data) -> Record? {
        try? JSONDecoder().decode(Record.self, from: data)
    }

    /// The watch, run by `/bin/sh -c` with the command line as its arguments
    /// and the folder, port, idle seconds and owning run's pid in
    /// `PHOTONZ_WALK_SERVER_DIR`, `_PORT`, `_IDLE` and `PHOTONZ_WALK_RUN_PID`.
    /// It is started detached, so the probe quitting between walks leaves it
    /// running; it stops the server when the run is gone, when nothing has
    /// been asked of it for `idleSeconds` (it is never idle while answering:
    /// `/slots` says so), or when it is told to (TERM, from the scripts).
    public static let watchScript = #"""
    trap '' HUP
    dir="$PHOTONZ_WALK_SERVER_DIR"
    port="$PHOTONZ_WALK_SERVER_PORT"
    idle="$PHOTONZ_WALK_SERVER_IDLE"
    RUN_PID="$PHOTONZ_WALK_RUN_PID"
    "$@" >>"$dir/log" 2>&1 &
    s=$!
    echo "$s $$" > "$dir/server.pid"
    touch "$dir/last-used"
    finish() {
      kill $s 2>/dev/null; wait $s 2>/dev/null
      if [ "$(cut -d' ' -f2 "$dir/server.pid" 2>/dev/null)" = "$$" ]; then
        rm -f "$dir/server.pid" "$dir/record.json"
      fi
      echo "== $(date) shared walk server let go: $1" >>"$dir/log"
      exit 0
    }
    trap 'finish told' TERM INT
    while kill -0 $s 2>/dev/null; do
      sleep 5 & wait $!
      if [ -n "$RUN_PID" ] && ! kill -0 "$RUN_PID" 2>/dev/null; then finish "the run is gone"; fi
      if curl -s -m 2 "http://127.0.0.1:$port/slots" | grep -q '"is_processing": *true'; then
        touch "$dir/last-used"
      fi
      used=$(stat -f %m "$dir/last-used" 2>/dev/null || echo 0)
      [ $(( $(date +%s) - used )) -gt "$idle" ] && finish "idle"
    done
    finish "it quit"
    """#
}

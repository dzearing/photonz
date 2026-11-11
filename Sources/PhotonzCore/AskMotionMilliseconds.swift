import Foundation

extension AskMotion {

    // MARK: Key times written in milliseconds

    /// `arguments` of a set_keys call with key times written in milliseconds
    /// read as seconds: every key a whole number, the last past the lap's end
    /// and none past the lap in milliseconds. The design is timed in
    /// milliseconds and the model at times copies those numbers straight into
    /// `seconds`: on 2026-11-10 and twice on 2026-11-11 the rocket's shake
    /// and smoke were keyed at 100 to 3000 on a 3 second lap, so the whole
    /// story played over fifty minutes and the lap showed a rocket that barely
    /// moved. With no lap set yet, a lap of `lapIfNone` is assumed. Keys
    /// already in seconds, or times that fit no reading, are left alone.
    public static func keysInSeconds(_ arguments: AgentJSON, lap: Double?) -> AgentJSON {
        guard var object = arguments.objectValue, let keys = object["keys"]?.arrayValue, !keys.isEmpty else { return arguments }
        let times = keys.compactMap { $0["seconds"]?.doubleValue }
        let lap = lap ?? lapIfNone
        guard times.count == keys.count, let last = times.max(), last > lap + 0.0005, last <= lap * 1000 + 0.5,
              times.allSatisfy({ $0 == $0.rounded() }), times.filter({ $0 > 0 }).allSatisfy({ $0 >= 10 }) else { return arguments }
        object["keys"] = .array(keys.map { key in
            guard var one = key.objectValue, let seconds = one["seconds"]?.doubleValue else { return key }
            one["seconds"] = .number(seconds / 1000)
            return .object(one)
        })
        return .object(object)
    }

    /// The lap a set_keys call is read against before set_timing has said one.
    static let lapIfNone = 10.0
}

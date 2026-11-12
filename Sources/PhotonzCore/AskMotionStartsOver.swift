import CoreGraphics
import Foundation

extension AskMotion {
    /// How long a line that drew itself stays drawn, still, before it fades
    /// to start over: long enough to read as done.
    static let startOverHold = 0.4
    /// How long it takes to fade out.
    static let startOverFade = 0.3
    /// The longest lap the fade may grow a story to.
    static let longestStory = 4.0

    /// `steps` with every line that draws itself (trimEnd or trimStart) and
    /// ends the lap drawn, on a lap that loops, made to start over unseen:
    /// after everything has stopped moving it holds drawn for
    /// `startOverHold`, fades out over `startOverFade`, and is undrawn again
    /// only at the start of the next lap, when it cannot be seen. Stillness
    /// already at the end of the lap is used first; the lap grows for the
    /// rest, up to `longestStory`. A part with a fade of its own is left as
    /// planned. The rules say this to the model in words and it was not
    /// done: on 2026-11-12 the eval's tick drew itself, bounced, and snapped
    /// from a ticked box to an empty one at every lap ("no hold or fade",
    /// nine looks of nine). Keys and time only: any line that draws itself.
    public static func startsOver(_ steps: [AskStep]) -> [AskStep] {
        guard let timing = steps.lastIndex(where: { $0.tool == "set_timing" }),
              steps[timing].arguments["loop"]?.boolValue != false,
              let lap = steps[timing].arguments["seconds"]?.doubleValue else { return steps }
        let trims: Set<String> = [MotionProperty.trimEnd.rawValue, MotionProperty.trimStart.rawValue]
        func layer(_ step: AskStep) -> String? { step.arguments["layer"]?.stringValue }
        let keyed = steps.filter { $0.tool == "set_keys" }
        let faded = Set(keyed.filter { $0.arguments["property"]?.stringValue == MotionProperty.opacity.rawValue }.compactMap(layer))
        // The lines that end the lap drawn otherwise than they start it.
        let lines = keyed.compactMap { step -> String? in
            guard trims.contains(step.arguments["property"]?.stringValue ?? ""), let name = layer(step), !faded.contains(name),
                  let first = AskMotionCheck.value(of: step, at: 0)?.doubleValue,
                  let last = AskMotionCheck.value(of: step, at: lap)?.doubleValue, abs(first - last) > 0.5 else { return nil }
            return name
        }
        guard !lines.isEmpty else { return steps }
        // The last moment anything changes in the lap.
        let settled = keyed.map { step -> Double in
            let keys = AskMotionCheck.timed(step)
            return zip(keys, keys.dropFirst()).filter { $0.0.value != $0.1.value }.map(\.1.seconds).max() ?? 0
        }.max() ?? 0
        let fadeStart = settled + startOverHold
        let end = max(lap, fadeStart + startOverFade)
        guard end <= longestStory + 0.0005 else { return steps }
        var out = steps
        if end > lap + 0.0005 {
            guard var object = out[timing].arguments.objectValue else { return steps }
            object["seconds"] = .number(Double(rounded(CGFloat(end))))
            out[timing] = AskStep(tool: out[timing].tool, arguments: .object(object))
        }
        for name in Set(lines).sorted() {
            let keys: [AgentJSON] = [["seconds": 0, "value": 100, "curve": .string(AgentKeyCurve.hold)],
                                     ["seconds": .number(Double(rounded(CGFloat(fadeStart)))), "value": 100,
                                      "curve": .string(AgentKeyCurve.easeInOut)],
                                     ["seconds": .number(Double(rounded(CGFloat(end)))), "value": 0]]
            out.append(AskStep(tool: "set_keys", arguments: ["layer": .string(name), "property": .string(MotionProperty.opacity.rawValue),
                                                             "keys": .array(keys)]))
        }
        return out
    }
}

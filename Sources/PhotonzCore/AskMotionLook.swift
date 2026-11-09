import Foundation

/// A moving icon is looked at before it lands: frames of what its plan made,
/// across one lap, go to the planning model with the request, and it says
/// which frames show each beat the request tells and what looks wrong. What it
/// saw goes back to the plan once (`AskConversation.reviseMotion(seen:)`).
///
/// Why: the six story cases of task
/// `an-animated-icon-told-as-a-little-story-moves-th` read as asked at 6 at
/// best on 2026-11-08, with the faults a person sees at once in the frames
/// (trash appearing where it lands instead of being thrown in, a bounce that
/// is a splash, two rings blurred into one). Shown last run's frames, the
/// planning model (Qwen3.8 27B) named those same faults in 20 to 30 seconds.
/// Nothing here knows what any icon is of: the request and the frames are all
/// it is shown.
public enum AskMotionLook {

    /// Frames across one lap. Twelve leaves a beat of 200 ms in a 2.4 s lap
    /// a frame of its own, and the sheet stays about a thousand tokens.
    public static let frames = 12
    /// Frames across, so twelve make a sheet of four by three.
    public static let columns = 4
    /// The side of one frame on the sheet, in pixels.
    public static let cellSide = 240

    /// How many times a plan goes back for what the look saw. Each costs a
    /// look (about 25 s) and a re-plan, inside the five minutes a request has.
    public static let mostLooks = 1

    /// The latest a look may start, in seconds since the request was sent.
    /// The look and its re-plan take 40 to 90 seconds, and a plan that is
    /// already slow would carry the request past five minutes: on 2026-11-08
    /// a heart's story did, and landed nothing at all.
    public static let latestStart: TimeInterval = 150

    /// Whether a moving icon that landed `seconds` after it was asked is
    /// looked at, having been looked at `looked` times already.
    public static func looks(after seconds: TimeInterval, looked: Int) -> Bool {
        looked < mostLooks && seconds < latestStart
    }

    /// The last line of an answer that saw nothing wrong.
    public static let allGood = "All good."

    /// The most of the model's answer sent back to the plan.
    public static let mostCritique = 1200

    static let question = """
        These are frames of a moving icon, evenly across one lap, left to right then top to bottom, each labelled \
        with its time. It was made for this request: "{{request}}"

        Go through the beats the request tells, in its order. For each beat write one line: the beat in a few \
        words, then the times of the frames where you can plainly see it happening, or: not seen. A beat is seen \
        only if it happens the way the words say: what hits, bounces off or knocks something touches that thing \
        in a frame; what goes in or into something passes behind its front and is hidden by it; what closes ends \
        closed and what opens ends open; what flies off or leaves goes out of the frame. Then one line for each \
        thing that looks wrong: a part that appears or vanishes in place instead of travelling, a part cut off by \
        the edge while it stays, a change too small to notice, beats in \
        the wrong order, a part left behind when the rest moves, a part drawn over what it should be behind. A \
        part that flies out of the frame, is gone a moment and comes back in from another edge is travelling, \
        not vanishing, and is cut by the edge only while it crosses it: that is fine. Be \
        strict: a beat counts only if a person watching would see it. If every beat is seen, in order, and \
        nothing looks wrong, end with: All good.
        """

    /// The moments the frames show: `frames` evenly over the lap, from its
    /// start to just before it starts again.
    public static func times(lapMS: Int) -> [Int] {
        let lap = max(1, lapMS)
        return (0..<frames).map { lap * $0 / frames }
    }

    /// The one call that looks: the planning model, its own window, the sheet
    /// and the question, no tools.
    public static func body(model: String, png: Data, request: String) -> AgentJSON {
        let body = AskDrawingCheck.visionBody(model: model, png: png, planner: true,
                                              question: question.replacingOccurrences(of: "{{request}}", with: request))
        guard var whole = body.objectValue, var options = body["options"]?.objectValue else { return body }
        options["num_predict"] = 400
        whole["options"] = .object(options)
        return .object(whole)
    }

    /// What the look saw, to send back, or nil when every beat was seen and
    /// nothing looks wrong (or it said nothing, which never holds a plan up).
    public static func critique(fromAnswer answer: String) -> String? {
        let said = AskConversation.withoutThinking(answer)
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return nil }
        let lower = said.lowercased()
        let missed = lower.contains("not seen")
        let lastLine = lower.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        if !missed, lastLine.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .punctuationCharacters)
            .hasSuffix("all good") {
            return nil
        }
        // The verdict line is no fault to mend.
        let kept = said.split(separator: "\n", omittingEmptySubsequences: false).filter {
            $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .punctuationCharacters).lowercased() != "all good"
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return kept.count > mostCritique ? String(kept.prefix(mostCritique)) : kept
    }

    /// Said to the plan with what the look saw.
    static func sendBack(_ seen: String) -> String {
        """
        Frames of the motion you planned were looked at, across one lap. This is what they show:
        \(seen)

        Mend every beat not seen and everything wrong, and keep what already reads. The drawing stays: call \
        set_keys again with replace true and all of its keys for each value that must change, and set_timing \
        again only if the lap must be longer. Each beat at least 200 ms and in the order the request tells; \
        what is thrown or put in travels there from out of view; what a beat causes starts where the parts \
        touch. Then finish with one last line, Left out: and any beat you still cannot show, or Left out: nothing.
        """
    }
}

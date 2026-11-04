import CoreGraphics
import Foundation

// Hovering a row of the Agent group's history shows a card to the left of the
// panel (the user, 2026-11-04: "if i hover over one, there's a popover on the
// left side which shows how it was interpreted and the before/after thumbs").
// What it says and where it sits are worked out here, away from any view.

/// How Ask understood a request, in a few plain lines: the model's own
/// sentence, what a drawing's plan took the words to mean, and what each kind
/// of step that landed did. Never a tool's name.
public enum AskUnderstanding {

    /// The most lines shown before the card says how many more there were.
    public static let mostLines = 5
    /// The longest a line runs, the model's sentence included.
    public static let lineBudget = 120

    public static func lines(summary: String, steps: [AskStep]) -> [String] {
        var lines: [String] = []
        func add(_ words: String) {
            let tidy = plain(words)
            if !tidy.isEmpty, !lines.contains(tidy) { lines.append(tidy) }
        }
        add(summary)
        for step in steps {
            for statement in step.arguments["plan"]?.arrayValue ?? [] {
                add(statement.stringValue ?? "")
            }
        }
        for run in runs(of: steps) {
            let said = AskChangeWords.sentence(run)
            if said != AskChangeWords.fallback { add(said) }
        }
        guard lines.count > mostLines else { return lines }
        return Array(lines.prefix(mostLines)) + ["and \(lines.count - mostLines) more"]
    }

    /// Steps of one kind side by side say it once: "Drew 2 shapes".
    private static func runs(of steps: [AskStep]) -> [[AskStep]] {
        var runs: [[AskStep]] = []
        for step in steps {
            if let last = runs.last?.last, last.tool == step.tool {
                runs[runs.count - 1].append(step)
            } else {
                runs.append([step])
            }
        }
        return runs
    }

    /// One line, trimmed and cut to the budget, with no em dash whatever the
    /// model wrote.
    private static func plain(_ words: String) -> String {
        let flat = words.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: " \u{2014} ", with: ", ")
            .replacingOccurrences(of: "\u{2014}", with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > lineBudget else { return flat }
        return String(flat.prefix(lineBudget - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }
}

/// Where the card sits. The rule is the panel's: never over the panel, beside
/// the row it is about, and off the thing that row made when there is room.
public enum AskHistoryCardPlacement {

    /// How far the card stands off the panel.
    public static let gap: CGFloat = 10
    /// How close to the window's edge it may come.
    public static let margin: CGFloat = 8
    /// The card's width, narrower only when the window is.
    public static let width: CGFloat = 288
    /// The longest side of a thumbnail, in pixels: two points to the pixel on
    /// a Retina screen, on a thumbnail about 130 points wide.
    public static let thumbnailSide: CGFloat = 272

    /// The card's frame, in the same coordinates as everything handed in.
    /// `avoiding` is what the row made, on screen.
    public static func frame(size: CGSize, row: CGRect, panelLeft: CGFloat, bounds: CGRect,
                             avoiding object: CGRect?) -> CGRect {
        let right = panelLeft - gap
        let left = max(bounds.minX + margin, right - size.width)
        let width = right - left
        func inside(_ y: CGFloat) -> CGFloat {
            max(bounds.minY + margin, min(y, bounds.maxY - margin - size.height))
        }
        let beside = CGRect(x: left, y: inside(row.minY), width: width, height: size.height)
        guard let object, beside.intersects(object) else { return beside }
        // The nearer of just above it and just below it, if either is free.
        let tries = [object.minY - gap - size.height, object.maxY + gap]
            .map { CGRect(x: left, y: $0, width: width, height: size.height) }
            .filter { $0.minY >= bounds.minY + margin && $0.maxY <= bounds.maxY - margin }
            .sorted { abs($0.minY - beside.minY) < abs($1.minY - beside.minY) }
        return tries.first ?? beside
    }

    /// The scale a thumbnail of `canvas` is drawn at: its longest side fits,
    /// and a small canvas is never enlarged.
    public static func thumbnailScale(canvas: CGSize) -> CGFloat {
        let longest = max(canvas.width, canvas.height)
        guard longest > thumbnailSide else { return 1 }
        return thumbnailSide / longest
    }
}

import Foundation
import Testing

/// One segmented control in the app, drawn by us.
///
/// Until 2026-09-29 there were three: the system's segmented picker (about
/// forty of them across the panel, the dialogs and the colour picker), a bare
/// `NSSegmentedControl` for View | Edit in the title bar, and a drawn one the
/// video panel kept to itself. Every one of them is now `SegmentedControl`
/// (Sources/Photonz/DesignSystem). For one day it was the Mac's own
/// `NSSegmentedControl`; the user sent it back on 2026-09-30 ("this IS the
/// native slider, but it's ugly and I want to go back to our custom one"),
/// with the picked choice as a tinted Liquid Glass chip that moves as glass.
/// Current keeps the SwiftUI segmented picker it always had.
///
/// This keeps a fourth from appearing. The walk harness is the one other place
/// allowed to name `NSSegmentedControl`: it READS the system control Current
/// draws so a walk can press its segments, and builds none.
@Suite("Every segmented control is the one we draw, made in one place")
struct SegmentedControlUsageTests {

    private static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/PhotonzCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("Sources/Photonz")
    }

    /// Where a segmented control may be made some other way.
    static let allowed = ["DesignSystem/SegmentedControl.swift", "Playtest/"]

    /// Whether a line of code makes a segmented control that is not ours.
    static func makesASegmentedControl(_ line: String) -> Bool {
        let code = line.drop { $0 == " " }
        guard !code.hasPrefix("//") else { return false }
        return code.contains("NSSegmentedControl")
            || code.contains(".segmented)")
            || code.contains("SegmentedPickerStyle")
    }

    @Test("The rule catches every way to make one and leaves comments alone")
    func theRuleReadsLinesRight() {
        #expect(Self.makesASegmentedControl("    .pickerStyle(.segmented)"))
        #expect(Self.makesASegmentedControl(".labelsHidden().pickerStyle(.segmented).controlSize(.small)"))
        #expect(Self.makesASegmentedControl("        let control = NSSegmentedControl(labels: titles,"))
        #expect(Self.makesASegmentedControl("    .pickerStyle(SegmentedPickerStyle())"))
        #expect(!Self.makesASegmentedControl("    // was an NSSegmentedControl until today"))
        #expect(!Self.makesASegmentedControl("    SegmentedControl(\"Unit\", selection: $unit, options: units)"))
    }

    @Test("Nothing in the app makes a segmented control except SegmentedControl")
    func onlyTheSharedControl() throws {
        let root = Self.appSources
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            Issue.record("could not read \(root.path)")
            return
        }
        var offences: [String] = []
        var sawTheSharedControl = false
        for case let file as URL in walk where file.pathExtension == "swift" {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            if relative == "DesignSystem/SegmentedControl.swift" { sawTheSharedControl = true }
            guard !Self.allowed.contains(where: { relative.hasPrefix($0) }) else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where Self.makesASegmentedControl(String(line)) {
                offences.append("\(relative):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(sawTheSharedControl, "Sources/Photonz/DesignSystem/SegmentedControl.swift is missing")
        #expect(offences.isEmpty, """
            These make a segmented control that is not the design system's. Use `SegmentedControl` \
            (Sources/Photonz/DesignSystem/SegmentedControl.swift): it draws the component on \
            comp-segmented.html in Next and the system control in Current.
            \(offences.joined(separator: "\n"))
            """)
    }
    /// Words that mean a second look or a second motion for the chip, or the
    /// Mac's own control back in Next. There is one style: a solid rail and a
    /// tinted Liquid Glass chip moved by SwiftUI's animation of its frame.
    static let secondStyleWords = ["plateStyle", "PlateStyle", "SegmentThumbMorph", "TimelineView",
                                   "systemGlassThumbEnabled", "NSSegmentedControl()", "segmentStyle"]

    @Test("The shared control has one look: a solid rail and a tinted Liquid Glass chip")
    func oneStyle() throws {
        let root = Self.appSources
        let control = try String(contentsOf: root.appendingPathComponent("DesignSystem/SegmentedControl.swift"),
                                 encoding: .utf8)
        let code = control.split(separator: "\n").filter {
            !$0.drop { $0 == " " }.hasPrefix("//")
        }.joined(separator: "\n")
        for word in Self.secondStyleWords {
            #expect(!code.contains(word), "SegmentedControl.swift has \(word) again: one style, the tinted glass chip")
        }
        // The chip is the system's glass, tinted.
        #expect(code.contains(".glassEffect(") && code.contains(".regular.tint(fill)"),
                "the chip is a pane of tinted Liquid Glass")
        // Interactive glass swells past the chip under a press, outside any
        // clip (filmed 2026-09-30), so the chip's glass is not interactive.
        #expect(!code.contains(".interactive()"), "the chip's glass never swells past the chip")
        // One pane, never in a container: a container springs its glass on a
        // curve of its own, and filmed on 2026-09-30 the pane overshot the
        // rail by 6pt while the chip's colour stayed inside it.
        #expect(!code.contains("GlassEffectContainer"), "the chip's glass is one pane, moved by SwiftUI's curve alone")
        // The colours are SegmentInk's, which are tested at 4.5:1 for every
        // state (SegmentInkTests), and the words are drawn twice so a word
        // the chip passes over is never grey on the accent.
        #expect(code.contains("SegmentInk.chip(accent:"), "the chip takes its colour from SegmentInk")
        #expect(code.contains("SegmentInk.rail("), "the rail takes its colour from SegmentInk")
        #expect(code.contains("wordsOnChip"), "the words are drawn again in the chip's ink inside the chip")
        // A disabled control never fades its words below 4.5:1.
        #expect(!code.contains("0.42"), "a faded control cannot keep its words readable")

        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            Issue.record("could not read \(root.path)")
            return
        }
        var offences: [String] = []
        for case let file as URL in walk where file.pathExtension == "swift" {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where !line.drop(while: { $0 == " " }).hasPrefix("//")
                && (line.contains("plateStyle:") || line.contains("SegmentThumbMorph")) {
                offences.append("\(relative):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offences.isEmpty, """
            A segmented control asks for a look of its own. There is one: the tinted glass chip.
            \(offences.joined(separator: "\n"))
            """)
    }
}

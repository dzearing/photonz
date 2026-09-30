import Foundation
import Testing

/// One segmented control in the app, and it is the system's own.
///
/// Until 2026-09-29 there were three: the system's segmented picker (about
/// forty of them across the panel, the dialogs and the colour picker), a bare
/// `NSSegmentedControl` for View | Edit in the title bar, and a drawn one the
/// video panel kept to itself. The user turned the title bar's down because it
/// was not the component on `comp-segmented.html`. Every one of them is now
/// `SegmentedControl` (Sources/Photonz/DesignSystem). Later that day the user
/// asked for the system's Liquid Glass control rather than a drawn one, so in
/// Next it is `NSSegmentedControl` as one capsule, and Current keeps the
/// SwiftUI segmented picker it always had.
///
/// This keeps a fourth from appearing. The walk harness is the one other place
/// allowed to name `NSSegmentedControl`: it READS the system control Current
/// draws so a walk can press its segments, and builds none.
@Suite("Every segmented control is the system's, made in one place")
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
            (Sources/Photonz/DesignSystem/SegmentedControl.swift): it is the system's segmented \
            control as one capsule, the same everywhere.
            \(offences.joined(separator: "\n"))
            """)
    }
    /// Words that mean the control is being DRAWN again. The user,
    /// 2026-09-29: "what happened to using the native liquid glass segmented
    /// control." The drawn rail, its sliding pane of glass, the thumb's own
    /// motion and the plate styles before it produced an unreadable
    /// white-on-white filter and a thumb that overshot its rail; the system
    /// control owns its look, its contrast and its motion.
    static let drawnControlWords = ["plateStyle", "PlateStyle", "SegmentThumbMorph", "SegmentThumbDrag",
                                    "TimelineView", ".glassEffect(", "GlassEffectContainer",
                                    "DesignedSegments", "segRail"]

    @Test("The shared control is the system's own, one capsule, drawing nothing")
    func theSystemControl() throws {
        let root = Self.appSources
        let control = try String(contentsOf: root.appendingPathComponent("DesignSystem/SegmentedControl.swift"),
                                 encoding: .utf8)
        let code = control.split(separator: "\n").filter {
            !$0.drop { $0 == " " }.hasPrefix("//")
        }.joined(separator: "\n")
        for word in Self.drawnControlWords {
            #expect(!code.contains(word), "SegmentedControl.swift draws its own control again (\(word)): it is the system's")
        }
        #expect(code.contains("NSSegmentedControl()"), "the control is AppKit's own segmented control")
        // Never `.automatic`: the first View | Edit switch, on automatic, was
        // seen in the title bar as two loose buttons.
        #expect(code.contains("segmentStyle = .rounded"), "one capsule, pinned, never .automatic")
        #expect(code.contains("trackingMode = .selectOne"), "one pick")

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
                && (line.contains("plateStyle:") || line.contains("SegmentThumbMorph")
                    || line.contains("DesignedSegments")) {
                offences.append("\(relative):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offences.isEmpty, """
            A segmented control asks for a look of its own. There is one: the system's.
            \(offences.joined(separator: "\n"))
            """)
    }
}

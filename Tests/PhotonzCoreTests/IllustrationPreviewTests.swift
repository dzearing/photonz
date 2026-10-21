import Foundation
import Testing
@testable import PhotonzCore

/// Writes every eval illustration, pass by pass, as SVG when
/// PHOTONZ_ILLUSTRATION_PREVIEW names a folder: how the illustrator is
/// looked at while it is tuned (`Scripts/illustration-preview.sh`). Does
/// nothing in a normal run.
struct IllustrationPreviewTests {
    static let cases: [(String, String, String?)] = [
        ("sun-over-mountains", "sun over mountains", nil),
        ("sun-mountains-line-art", "sun over mountains", "line art"),
        ("sun-mountains-silhouette-badge", "sun over mountains with pines", "black silhouette badge"),
        ("sun-mountains-sunset", "sun over mountains", "layered sunset"),
        ("sun-mountains-flat", "sun over mountains", "flat"),
        ("forest-at-dusk", "forest at dusk", "illustration"),
        ("lighthouse-on-a-cliff", "lighthouse on a cliff", "illustration"),
        ("fox", "fox", "illustration"),
        ("city-skyline-at-night", "city skyline at night", "illustration"),
        ("mountain-lake-day", "mountain lake on a sunny day", "illustration"),
    ]

    @Test func writePreviews() throws {
        guard let folder = ProcessInfo.processInfo.environment["PHOTONZ_ILLUSTRATION_PREVIEW"] else { return }
        let base = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var report = ""
        for (name, subject, style) in Self.cases {
            let brief = try #require(IllustrationBrief.make(subject: subject, style: style))
            let passes = Illustrator.passes(brief)
            for pass in passes {
                try pass.scene.svg().write(to: base.appendingPathComponent("\(name)-\(pass.number).svg"), atomically: true, encoding: .utf8)
                for check in pass.checks {
                    report += "\(name) \(pass.number) \(check.name) \(check.passed ? "ok" : "FAIL") \(check.detail)\n"
                }
            }
        }
        try report.write(to: base.appendingPathComponent("checks.txt"), atomically: true, encoding: .utf8)
    }
}

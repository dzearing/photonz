import AVFoundation
import AppKit
import CoreGraphics
import PhotonzCore

/// The ONE place the app decides whether to raise a macOS permission dialog.
/// Every request the app makes (Screen Recording, microphone) asks here first,
/// and nothing else in the app may call into macOS in a way that asks: capture
/// code checks the grant before it touches ScreenCaptureKit, because on macOS 15
/// and later ANY ScreenCaptureKit call without the grant queues a dialog too.
///
/// The rule is `PermissionAskPolicy`: never ask for what is granted; the
/// person's own app asks at most once per launch; the loop's probe asks at most
/// once ever, remembered in `probe-permission-asks.json` beside its bundle.
/// Why: on macOS 26 a Screen Recording request from an app without the grant
/// puts up "would like to record this computer's screen and audio" every time,
/// Deny records nothing, and each dialog waits behind the one on screen after
/// the app has quit. A probe asking once per launch, launched hundreds of times
/// a night, left the person a stack of them on 2026-11-26.
@MainActor
enum PermissionGate {
    private static var askedThisLaunch: Set<PermissionService> = []

    /// Who is asking: a person's app, or the loop's probe.
    static var asker: PermissionAskPolicy.Asker {
        AppInfo.flavor == .probe ? .unmannedProbe : .person
    }

    /// Whether the permission is granted right now. Reads macOS, never asks.
    static func isGranted(_ service: PermissionService) -> Bool {
        #if PHOTONZ_PLAYTEST
        if drill != nil { return false }
        #endif
        switch service {
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    /// Whether the caller may raise the system's request for `service` now.
    /// A yes is recorded before it is returned, so the caller asks exactly
    /// once for it; a no means do not ask, and show what is missing instead.
    static func mayAsk(_ service: PermissionService) -> Bool {
        let ledger = readLedger()
        let answer = PermissionAskPolicy.decide(service, granted: isGranted(service), asker: asker,
                                                askedThisLaunch: askedThisLaunch, ledger: ledger)
        #if PHOTONZ_PLAYTEST
        drillNote("\(service.rawValue) \(describe(answer))")
        #endif
        guard answer == .ask else {
            if case .askedBefore(let at) = answer {
                NSLog("[permissions] not asking for \(service.rawValue) again: this probe asked once already, at \(at)")
            }
            return false
        }
        askedThisLaunch.insert(service)
        if let url = ledgerURL {
            let stamp = ISO8601DateFormatter().string(from: Date())
            let next = PermissionAskPolicy.recording(service, at: stamp, in: ledger)
            if let data = try? JSONEncoder().encode(next) { try? data.write(to: url) }
        }
        #if PHOTONZ_PLAYTEST
        // The drill counts the asks; it never puts a dialog in front of anyone.
        if drill != nil { return false }
        #endif
        return true
    }

    /// Whether a Settings pane may be opened on the person's screen. The
    /// probe never opens one: nobody launched it, so a System Settings window
    /// coming up over the person's work is the same intrusion as a dialog.
    static var mayOpenSettings: Bool { asker == .person }

    // MARK: - The probe's memory

    /// `probe-permission-asks.json` beside the probe's bundle, or the drill's
    /// own file. Nil for a person's app, which keeps nothing between launches.
    static var ledgerURL: URL? {
        #if PHOTONZ_PLAYTEST
        if let drill { return drill.appendingPathComponent("ledger.json") }
        #endif
        guard asker == .unmannedProbe else { return nil }
        return Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("probe-permission-asks.json")
    }

    private static func readLedger() -> PermissionAskLedger {
        PermissionAskLedger.read(ledgerURL.flatMap { try? Data(contentsOf: $0) })
    }

    #if PHOTONZ_PLAYTEST
    // MARK: - The drill (`queue/bin/permission-drill.sh`)

    /// `--permission-drill <folder>`, probe only: every permission reads as
    /// missing, the ledger lives in the folder, every decision is written to
    /// `decisions.log` there, and no request ever reaches macOS. Ten launches
    /// in a row must write exactly one `ask` per service the launch path asks
    /// for, and `asked before` after it.
    static let drill: URL? = {
        guard AppInfo.flavor == .probe else { return nil }
        let args = CommandLine.arguments
        guard let at = args.firstIndex(of: "--permission-drill"), at + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[at + 1], isDirectory: true)
    }()

    private static func drillNote(_ line: String) {
        guard let drill else { return }
        let url = drill.appendingPathComponent("decisions.log")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func describe(_ answer: PermissionAskPolicy.Answer) -> String {
        switch answer {
        case .ask: return "ask"
        case .alreadyGranted: return "granted"
        case .askedThisLaunch: return "asked this launch"
        case .askedBefore(let at): return "asked before \(at)"
        }
    }
    #endif
}

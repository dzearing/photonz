// Which privacy grants the terminal running this script holds. Prints one
// `key=value` per line for Scripts/probe-app.sh to fold into its status line.
//
//   swift Scripts/permcheck.swift
//   accessibility=granted|denied
//   automation=granted|denied|undetermined|unknown
//   screenRecording=granted|denied
//
// NOTHING here prompts. macOS attributes a shell's grants to the app that owns
// the terminal, which is one a person already has open, so a prompt raised from
// an unmanned loop would land in the middle of their work once per probe
// launch. The loop reports what it has and names what to grant instead.
//
// Screen Recording for the probe APP is a different question with a different
// answer: only the probe can ask about its own grant, so it writes
// probe-grants.json beside its bundle at launch. See
// Sources/Photonz/Playtest/ProbeGrants.swift.
import ApplicationServices
import CoreGraphics
import Foundation

let trusted = AXIsProcessTrustedWithOptions(
    [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary)
print("accessibility=\(trusted ? "granted" : "denied")")

// Apple Events to System Events: what reads menu titles and sends keystrokes.
// The answer is only knowable while the target is running, and System Events is
// launched on demand, so "unknown" is an honest third state, not a failure.
var target = AEAddressDesc()
let systemEvents = "com.apple.systemevents"
_ = systemEvents.withCString { AECreateDesc(typeApplicationBundleID, $0, strlen($0), &target) }
let permission = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
AEDisposeDesc(&target)
switch permission {
case noErr: print("automation=granted")
case OSStatus(errAEEventNotPermitted): print("automation=denied")
case OSStatus(errAEEventWouldRequireUserConsent): print("automation=undetermined")
default: print("automation=unknown")
}

print("screenRecording=\(CGPreflightScreenCaptureAccess() ? "granted" : "denied")")

import Foundation
import PhotonzCore
import Testing

/// Regression tests for the mic-recording crash: starting a recording with a
/// microphone selected while the app had no mic authorization let SCStream trip
/// the TCC machinery mid-start, which either blocked the start indefinitely
/// (prompt pending) or failed it instantly and silently (denied, prompt
/// suppressed) so the stop HUD vanished in under a second. The gate resolves
/// microphone access BEFORE any stream is created.
@Suite("Microphone permission gate")
struct MicrophonePermissionGateTests {

    // MARK: - No microphone requested: never gate

    @Test func configsWithoutMicrophoneAlwaysProceed() {
        for auth: MicrophoneAuthorization in [.notDetermined, .denied, .authorized] {
            #expect(MicrophonePermissionGate.decision(wantsMicrophone: false, authorization: auth) == .proceed)
        }
    }

    // MARK: - Microphone requested: decision follows authorization

    @Test func authorizedMicrophoneProceeds() {
        #expect(MicrophonePermissionGate.decision(wantsMicrophone: true, authorization: .authorized) == .proceed)
    }

    @Test func undeterminedMicrophoneRequestsAccessFirst() {
        #expect(MicrophonePermissionGate.decision(wantsMicrophone: true, authorization: .notDetermined) == .requestAccess)
    }

    @Test func deniedMicrophoneIsBlockedNotSilent() {
        #expect(MicrophonePermissionGate.decision(wantsMicrophone: true, authorization: .denied) == .blocked)
    }

    // MARK: - Fallback config for "record without microphone"

    @Test func withoutMicrophoneStripsMicButKeepsEverythingElse() {
        let config = RecordingConfig(source: .region(CGRect(x: 1, y: 2, width: 3, height: 4)),
                                     audio: [.systemAudio, .microphone],
                                     microphoneDeviceID: "mic-123",
                                     format: .gif)
        let stripped = config.withoutMicrophone
        #expect(stripped.audio == [.systemAudio])
        #expect(stripped.microphoneDeviceID == nil)
        #expect(stripped.source == config.source)
        #expect(stripped.format == config.format)
    }

    @Test func withoutMicrophoneLeavesMiclessConfigsUntouched() {
        let config = RecordingConfig(source: .fullDisplay, audio: [], microphoneDeviceID: nil, format: .mp4)
        #expect(config.withoutMicrophone == config)
    }
}

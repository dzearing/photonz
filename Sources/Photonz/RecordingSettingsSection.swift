import PhotonzCore
import SwiftUI

/// Settings' Recording section (Next, with
/// `next-a-recording-keeps-the-screens-colours`): how much of the screen's
/// picture a recording keeps. Best (the default) keeps every gradient as a
/// screenshot does, at four times the size of the Mac's own recordings while
/// the whole screen moves; Smaller files is about half their size, with faint
/// bands in dark gradients (`RecordingQuality`).
struct RecordingSettingsSection: View {
    @StoredSetting(RecordingQuality.settingKey) private var stored: String = RecordingQuality.best.rawValue

    var body: some View {
        Section {
            Picker("Quality", selection: Binding(
                get: { RecordingQuality(stored: stored) },
                set: { stored = $0.rawValue })) {
                    ForEach(RecordingQuality.allCases, id: \.self) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                .playtestControl("Recording Quality", detail: RecordingQuality(stored: stored).label)
        } header: {
            Text("Recording")
        }
    }
}

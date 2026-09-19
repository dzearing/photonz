import SwiftUI

/// One row of an Export sheet: what it is called on the left, and the control it
/// names beside it.
///
/// The label is never allowed to wrap, and it holds a column wide enough for the
/// short names, so Export, Format, Scale and Quality read down the sheet with
/// their controls starting in the same place. A name longer than the column
/// widens its own row rather than breaking, and rather than pushing every other
/// control across.
///
/// It lives here rather than inside one sheet because there are two now: a
/// picture leaves through `ExportDialog` and a recording through
/// `RecordingExportDialog`, and the promise the user was made is that those are
/// the same sheet. Sharing the row is what stops them drifting a point apart.
struct ExportSheetRow<Control: View>: View {
    let name: String
    @ViewBuilder let control: Control

    init(_ name: String, @ViewBuilder control: () -> Control) {
        self.name = name
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .fixedSize()
                .frame(minWidth: 56, alignment: .leading)
            control
        }
    }
}

/// How wide an Export sheet is.
///
/// Wide enough for the format row to hold its name and five buttons on one
/// line. At 320 the segments took every point there was and the word beside
/// them came out stacked two letters a line.
enum ExportSheetMetrics {
    static let width: CGFloat = 380
    static let padding: CGFloat = 20
    static let spacing: CGFloat = 16
}

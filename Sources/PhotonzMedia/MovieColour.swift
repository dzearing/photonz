import AVFoundation
import Foundation

/// What colours a written MP4 says it holds, shared by the recording's export
/// (`VideoExporter`) and the document's (`DocumentMovieWriter`) so the two
/// cannot drift apart.
///
/// **A file that says nothing is guessed at, and the guess is wrong.** Both
/// writers used to tag nothing, and VideoToolbox, which QuickTime, Safari and
/// the app's own reader all decode through, reads an untagged file as SMPTE-C
/// primaries, the 601 matrix and the 709 curve. The pixels handed over are
/// sRGB, so mid grey played lighter (sRGB 76 as 86, 128 as 139), the deepest
/// shadows darker (16 as 14) and pure red as (231, 23, 0). Measured in
/// QuickTime on 2026-10-04 (docs/progress/2026-10-04-export-brightness.md).
///
/// **Rec.709 primaries, the 709 matrix and the sRGB curve** is what sRGB
/// pixels are, so it is what the file says, and every grey and primary then
/// plays within a code value of the editor. Tagging the 709 curve instead does
/// NOT fix it: with the same pixels, 76 still plays as 86. Apple's own screen
/// recordings say 709 / 709 / 709, and the recording's export converts them to
/// these properties on the way through (`VideoExporter.writePictures`), so a
/// recording and a document come out tagged alike.
enum MovieColour {

    /// The writer's `AVVideoColorPropertiesKey`, and what the recording's
    /// reader converts its pictures to.
    static let properties: [String: String] = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ]
}

import AVFoundation
import CoreGraphics
import CoreVideo
import VideoToolbox

// Writes a movie exactly the way DocumentMovieWriter does (BGRA buffer drawn in
// an sRGB context, H.264, no colour properties), optionally tagged.
let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
let tag = args.count > 2 ? args[2] : "none"
try? FileManager.default.removeItem(at: out)
let W = 640, H = 360
let levels: [Int] = [0, 8, 16, 32, 64, 96, 128, 160, 192, 224, 255, 76]  // 76 = 0.297*255 approx
var settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
  AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]]
if tag == "709" {
  settings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
} else if tag == "srgb" {
  settings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
    AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
}
let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
for i in 0..<60 {
  while !input.isReadyForMoreMediaData { usleep(1000) }
  var buf: CVPixelBuffer?
  CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buf)
  let b = buf!
  CVPixelBufferLockBaseAddress(b, [])
  let ctx = CGContext(data: CVPixelBufferGetBaseAddress(b), width: W, height: H, bitsPerComponent: 8,
    bytesPerRow: CVPixelBufferGetBytesPerRow(b), space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
  let pw = W / levels.count
  for (k, l) in levels.enumerated() {
    let v = CGFloat(l) / 255
    ctx.setFillColor(red: v, green: v, blue: v, alpha: 1)
    ctx.fill(CGRect(x: k * pw, y: 0, width: pw, height: H))
  }
  CVPixelBufferUnlockBaseAddress(b, [])
  adaptor.append(b, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
}
input.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
print("wrote", out.path, writer.status.rawValue, writer.error as Any)

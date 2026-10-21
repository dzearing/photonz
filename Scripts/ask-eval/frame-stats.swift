// Whether each frame of a video is blank: one flat colour with nothing drawn
// on it (Scripts/ask-eval/README.md, "Video cases").
//
//   swift Scripts/ask-eval/frame-stats.swift <frame.png> [<frame.png> ...]
//
// Prints one line of JSON: for each frame, the share of its pixels that are
// not the frame's own most common colour. A frame where fewer than one pixel
// in five hundred differs is blank. A title page's words, a recording's
// window and a zoom's picture all clear that by far; a black or white frame,
// or a frame that never drew, does not.
import AppKit

let blankBelow = 0.002
let differs = 24 // out of 255 on any channel

var out: [[String: Any]] = []
for path in CommandLine.arguments.dropFirst() {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        out.append(["file": path, "error": "could not read"])
        continue
    }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { out.append(["file": path, "error": "could not draw"]); continue }
    // The most common colour, on a coarse grid so near shades count together.
    var counts: [Int: Int] = [:]
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let key = Int(pixels[i] >> 3) << 10 | Int(pixels[i + 1] >> 3) << 5 | Int(pixels[i + 2] >> 3)
        counts[key, default: 0] += 1
    }
    let common = counts.max { $0.value < $1.value }?.key ?? 0
    let r = (common >> 10 & 31) << 3 + 4, g = (common >> 5 & 31) << 3 + 4, b = (common & 31) << 3 + 4
    var off = 0
    for i in stride(from: 0, to: pixels.count, by: 4)
    where abs(Int(pixels[i]) - r) > differs || abs(Int(pixels[i + 1]) - g) > differs || abs(Int(pixels[i + 2]) - b) > differs {
        off += 1
    }
    let share = Double(off) / Double(width * height)
    out.append(["file": path, "drawn": (share * 10000).rounded() / 10000, "blank": share < blankBelow,
                "colour": String(format: "#%02X%02X%02X", r - 4, g - 4, b - 4)])
}
let data = try JSONSerialization.data(withJSONObject: out)
print(String(decoding: data, as: UTF8.self))

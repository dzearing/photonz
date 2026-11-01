import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
func write(_ img: CGImage, _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}
// A photo-like 4000x3000: gradients plus grain.
let w = 4000, h = 3000
var px = [UInt8](repeating: 0, count: w*h*4)
var seed: UInt64 = 12345
for y in 0..<h { for x in 0..<w {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    let n = Int((seed >> 33) % 24) - 12
    let i = (y*w+x)*4
    let fx = Double(x)/Double(w), fy = Double(y)/Double(h)
    px[i] = UInt8(max(0, min(255, Int(60 + 150*fx + 30*sin(fy*9)) + n)))
    px[i+1] = UInt8(max(0, min(255, Int(90 + 100*fy + 40*cos(fx*7)) + n)))
    px[i+2] = UInt8(max(0, min(255, Int(140 - 80*fx*fy + 20*sin((fx+fy)*13)) + n)))
    px[i+3] = 255
}}
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
write(ctx.makeImage()!, "photo-12mp.png")
// A 3456x2234 Retina screenshot: the app window fixture drawn to that size.
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let shot = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let sw = 3456, sh = 2234
let c2 = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
c2.interpolationQuality = .none
c2.draw(shot, in: CGRect(x: 0, y: 0, width: sw, height: sh))
write(c2.makeImage()!, "screenshot-3456x2234.png")

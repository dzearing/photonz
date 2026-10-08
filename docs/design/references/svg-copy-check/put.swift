// put <mode>: png+tiff+svg types (mode: svgtype | svgtext | both)
import AppKit
let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8" fill="#0A84FF"/></svg>"##
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.systemBlue.setFill(); NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 16, height: 16)).fill()
let pb = NSPasteboard.general
pb.clearContents()
pb.setData(rep.representation(using: .png, properties: [:])!, forType: .png)
pb.setData(rep.tiffRepresentation!, forType: .tiff)
let mode = CommandLine.arguments[1]
if mode != "svgtext" { pb.setData(svg.data(using: .utf8)!, forType: .init("public.svg-image")) }
if mode != "svgtype" { pb.setString(svg, forType: .string) }
print(pb.types!.map(\.rawValue))

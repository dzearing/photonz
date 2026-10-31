import Metal
import Foundation
// Times a 1 MB blit on the GPU every 50 ms for N seconds; prints p50/p99/max ms.
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "30") ?? 30
let dev = MTLCreateSystemDefaultDevice()!
let q = dev.makeCommandQueue()!
let a = dev.makeBuffer(length: 1 << 20, options: .storageModePrivate)!
let b = dev.makeBuffer(length: 1 << 20, options: .storageModePrivate)!
var times: [Double] = []
let end = Date().addingTimeInterval(seconds)
while Date() < end {
  let t0 = DispatchTime.now().uptimeNanoseconds
  let cb = q.makeCommandBuffer()!
  let e = cb.makeBlitCommandEncoder()!
  e.copy(from: a, sourceOffset: 0, to: b, destinationOffset: 0, size: 1 << 20)
  e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
  times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
  usleep(50_000)
}
times.sort()
func p(_ f: Double) -> Double { times[min(times.count - 1, Int(Double(times.count) * f))] }
print(String(format: "gpu blit n=%d p50=%.2f p99=%.2f max=%.2f ms", times.count, p(0.5), p(0.99), times.last!))

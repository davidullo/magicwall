// Generates a small animated test video (moving shapes + color sweep) for
// verifying the MagicWall desktop engine. Usage: swift make-test-video.swift <output.mp4>
import AVFoundation
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "test-pattern.mp4"
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.removeItem(at: outputURL)

let width = 1920
let height = 1080
let fps: Int32 = 30
let seconds = 6
let totalFrames = Int(fps) * seconds

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false

let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ]
)

writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let colorSpace = CGColorSpaceCreateDeviceRGB()

for frame in 0..<totalFrames {
    while !input.isReadyForMoreMediaData {
        usleep(2000)
    }
    guard let pool = adaptor.pixelBufferPool else { fatalError("no pixel buffer pool") }
    var maybeBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
    guard let buffer = maybeBuffer else { fatalError("no pixel buffer") }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else { fatalError("no CGContext") }

    let t = Double(frame) / Double(totalFrames)
    let hue = t

    // Background: vertical gradient between two hues.
    let top = CGColor(red: 0.10 + 0.5 * (1 - hue), green: 0.05, blue: 0.35 + 0.5 * hue, alpha: 1)
    let bottom = CGColor(red: 0.02, green: 0.12 + 0.4 * hue, blue: 0.10, alpha: 1)
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: [top, bottom] as CFArray, locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
    }

    // Moving ball (left → right).
    let ballX = 200 + t * Double(width - 400)
    let ballY = Double(height) / 2 + sin(t * .pi * 4) * 220
    context.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
    context.fillEllipse(in: CGRect(x: ballX - 90, y: ballY - 90, width: 180, height: 180))

    // Rotating square.
    context.saveGState()
    context.translateBy(x: Double(width) / 2, y: 260)
    context.rotate(by: t * .pi * 2)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    context.fill(CGRect(x: -80, y: -80, width: 160, height: 160))
    context.restoreGState()

    // Progress bar at the bottom.
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
    context.fill(CGRect(x: 0, y: 0, width: width, height: 14))
    context.setFillColor(CGColor(red: 1, green: 0.3, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: Double(width) * t, height: 14))

    let time = CMTime(value: CMTimeValue(frame), timescale: fps)
    adaptor.append(buffer, withPresentationTime: time)
}

input.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting { semaphore.signal() }
semaphore.wait()

if writer.status == .completed {
    print("Wrote \(outputPath) (\(totalFrames) frames, \(width)x\(height)@\(fps))")
} else {
    print("FAILED: \(writer.error?.localizedDescription ?? "unknown")")
    exit(1)
}

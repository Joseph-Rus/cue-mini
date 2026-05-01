import Foundation
import AVFoundation

/// Anything that can produce audio buffers + level updates and can be started/stopped.
/// Both the mic-based (AVAudioEngine) and system-audio (ScreenCaptureKit) capturers
/// conform to this so ShazamRecognizer doesn't need to care which is which.
protocol AudioCapturer: AnyObject {
    /// Called for every audio buffer produced. The capturer guarantees a sample
    /// time appropriate for SHSession.matchStreamingBuffer(_:at:).
    var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)? { get set }

    /// Called when the user-facing audio level changes. 0…1 normalized.
    var onLevel: ((Float) -> Void)? { get set }

    /// Called when capture fails after start. Capturer is considered stopped.
    var onError: ((String) -> Void)? { get set }

    func start() async throws
    func stop()
}

/// Helpers shared across capturer implementations.
enum AudioLevelMeter {
    /// Lift quiet RMS into a meter-friendly 0…1 range.
    static func normalized(rms: Float) -> Float {
        min(1.0, max(0.0, rms * 6.0))
    }

    static func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sumSquares: Float = 0
        let samples = channelData[0]
        for i in 0..<frameLength {
            let s = samples[i]
            sumSquares += s * s
        }
        return sqrt(sumSquares / Float(frameLength))
    }
}

import Foundation
import AVFoundation
import ScreenCaptureKit

/// Captures system-wide audio output via ScreenCaptureKit. Requires Screen
/// Recording permission (TCC). Doesn't actually capture the screen — the
/// SCStream is configured for audio only with a 2×2 placeholder video track
/// (the smallest accepted) which we discard.
@available(macOS 13.0, *)
final class SystemAudioCapturer: NSObject, AudioCapturer, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?

    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "com.josephrussell.cuemini.sysaudio", qos: .userInitiated)

    func start() async throws {
        // Resolve a display we're allowed to "share" — we won't actually use the
        // video, but SCStream requires a content filter built from one.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "CueMini", code: -10, userInfo: [
                NSLocalizedDescriptionKey: "No display available for system audio capture."
            ])
        }

        // Exclude our own app from capture so we don't record any sounds we make.
        let ourBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedApps = content.applications.filter { $0.bundleIdentifier == ourBundleID }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        // Tiny placeholder video — required by API, ignored by us.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps, effectively idle
        config.queueDepth = 5
        // Audio config — what we actually want.
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
        // We're forced to take a video stream too, but we don't process its samples.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)

        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        Task {
            try? await stream.stopCapture()
        }
        self.stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let pcm = pcmBuffer(from: sampleBuffer) else { return }
        let pts = sampleBuffer.presentationTimeStamp
        let sampleRate = pcm.format.sampleRate
        let sampleTime = AVAudioFramePosition(pts.seconds * sampleRate)
        let time = AVAudioTime(sampleTime: sampleTime, atRate: sampleRate)

        onBuffer?(pcm, time)
        let level = AudioLevelMeter.normalized(rms: AudioLevelMeter.rms(buffer: pcm))
        onLevel?(level)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error.localizedDescription)
    }

    // MARK: - CMSampleBuffer → AVAudioPCMBuffer

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = formatDescription.audioStreamBasicDescription else {
            return nil
        }
        var mutableASBD = asbd
        guard let format = AVAudioFormat(streamDescription: &mutableASBD) else {
            return nil
        }

        // Ask CoreMedia how big the AudioBufferList needs to be (depends on
        // channel count + interleaved/deinterleaved layout).
        var listSize: Int = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &listSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard status == noErr, listSize > 0 else { return nil }

        // We *copy* the audio out of the CoreMedia-owned memory rather than
        // alias it via bufferListNoCopy — the source memory is reclaimed when
        // this function returns, so a no-copy wrap would be a use-after-free.
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        pcm.frameLength = frameCount

        // Stack-fill an appropriately-sized AudioBufferList using malloc'd memory.
        let srcListRaw = UnsafeMutableRawPointer.allocate(
            byteCount: listSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { srcListRaw.deallocate() }
        let srcListPtr = srcListRaw.bindMemory(to: AudioBufferList.self, capacity: 1)

        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: srcListPtr,
            bufferListSize: listSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }
        // blockBuffer is retained by us via the call; releasing happens at
        // scope exit (Swift handles the CMBlockBuffer ref).

        let srcList = UnsafeMutableAudioBufferListPointer(srcListPtr)
        let dstList = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
        let count = min(srcList.count, dstList.count)
        for i in 0..<count {
            let src = srcList[i]
            let dst = dstList[i]
            guard let srcData = src.mData, let dstData = dst.mData else { continue }
            let bytes = Int(min(src.mDataByteSize, dst.mDataByteSize))
            memcpy(dstData, srcData, bytes)
        }

        return pcm
    }
}


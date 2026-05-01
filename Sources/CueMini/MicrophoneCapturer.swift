import Foundation
import AVFoundation
import CoreAudio

final class MicrophoneCapturer: AudioCapturer, @unchecked Sendable {
    var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?

    private let deviceUID: String
    private var engine: AVAudioEngine?

    init(deviceUID: String) {
        self.deviceUID = deviceUID
    }

    func start() async throws {
        let engine = AVAudioEngine()
        self.engine = engine

        if !deviceUID.isEmpty {
            try setInputDevice(uid: deviceUID, on: engine)
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "CueMini", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Selected microphone has no usable input format. Try a different device."
            ])
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self else { return }
            self.onBuffer?(buffer, time)
            let level = AudioLevelMeter.normalized(rms: AudioLevelMeter.rms(buffer: buffer))
            self.onLevel?(level)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func setInputDevice(uid: String, on engine: AVAudioEngine) throws {
        guard let deviceID = AudioDevices.findDeviceID(uid: uid) else { return }
        let audioUnit = engine.inputNode.audioUnit!
        var id = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            throw NSError(domain: "CueMini", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Could not select that microphone (status \(status))."
            ])
        }
    }
}

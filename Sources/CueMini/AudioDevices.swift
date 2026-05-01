import Foundation
import CoreAudio

struct AudioInputDevice: Identifiable, Hashable {
    let id: String   // UID
    let name: String
    let deviceID: AudioDeviceID
}

enum AudioDevices {
    static func listInputs() -> [AudioInputDevice] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size
        )
        guard status == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceIDs
        )
        guard status == noErr else { return [] }

        var devices: [AudioInputDevice] = []
        for id in deviceIDs {
            guard hasInputChannels(id) else { continue }
            let name = stringProperty(id, selector: kAudioObjectPropertyName) ?? "Unknown"
            let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID) ?? "\(id)"
            devices.append(AudioInputDevice(id: uid, name: name, deviceID: id))
        }
        return devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func findDeviceID(uid: String) -> AudioDeviceID? {
        listInputs().first(where: { $0.id == uid })?.deviceID
    }

    private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer)
        guard status == noErr else { return false }

        let bufferList = buffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        var channels: UInt32 = 0
        for buf in abl { channels += buf.mNumberChannels }
        return channels > 0
    }

    private static func stringProperty(_ id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var name: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name)
        guard status == noErr, let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }
}

import Foundation
import CoreAudio

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let name: String
    let input: Bool
}
struct AudioReading: Equatable {
    var devices: [AudioDevice] = []
    var output: AudioObjectID = 0, input: AudioObjectID = 0
    var outputVolume: Double = 0, inputVolume: Double = 0
    var outputMuted = false, inputMuted = false
    var canSetOutput = false, canSetInput = false
    var sampleRate: Double = 0
    var outputName: String { devices.first { $0.id == output && !$0.input }?.name ?? "No output device" }
}

enum AudioControl {
    static func address(_ selector: AudioObjectPropertySelector, input: Bool = false, element: AudioObjectPropertyElement = 0) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput, mElement: element)
    }
    static func read<T>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, into value: inout T) -> Bool {
        var address = address; var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutableBytes(of: &value) { buffer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer.baseAddress!) == noErr
        }
    }
    static func set<T>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, value: T) -> OSStatus {
        var address = address; var value = value
        return withUnsafeBytes(of: &value) { buffer in
            AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<T>.size), buffer.baseAddress!)
        }
    }
    static func global(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
    }
    static func channels(_ id: AudioObjectID, input: Bool) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, input: input); var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }
    static func volumeElements(_ id: AudioObjectID, input: Bool) -> [AudioObjectPropertyElement] {
        var main = address(kAudioDevicePropertyVolumeScalar, input: input)
        var settable = DarwinBoolean(false)
        if AudioObjectHasProperty(id, &main), AudioObjectIsPropertySettable(id, &main, &settable) == noErr, settable.boolValue { return [0] }
        return (1...2).compactMap { element in
            var a = address(kAudioDevicePropertyVolumeScalar, input: input, element: UInt32(element))
            var writable = DarwinBoolean(false)
            return AudioObjectHasProperty(id, &a) && AudioObjectIsPropertySettable(id, &a, &writable) == noErr && writable.boolValue ? UInt32(element) : nil
        }
    }
    static func volume(_ id: AudioObjectID, input: Bool) -> Double {
        let elements = volumeElements(id, input: input)
        let values: [Double] = elements.compactMap { element in
            var value: Float32 = 0
            return read(id, address(kAudioDevicePropertyVolumeScalar, input: input, element: element), into: &value) ? Double(value) : nil
        }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    static func snapshot() -> AudioReading {
        var result = AudioReading()
        _ = read(AudioObjectID(kAudioObjectSystemObject), global(kAudioHardwarePropertyDefaultOutputDevice), into: &result.output)
        _ = read(AudioObjectID(kAudioObjectSystemObject), global(kAudioHardwarePropertyDefaultInputDevice), into: &result.input)
        var addr = global(kAudioHardwarePropertyDevices); var size: UInt32 = 0
        if AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr {
            var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            if !ids.isEmpty, AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr {
                for id in ids {
                    var name: Unmanaged<CFString>?
                    var nameAddress = global(kAudioObjectPropertyName)
                    var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                    let status = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
                    let label = status == noErr ? name?.takeRetainedValue() as String? ?? "Audio device" : "Audio device"
                    for input in [false, true] where channels(id, input: input) { result.devices.append(AudioDevice(id: id, name: label, input: input)) }
                }
            }
        }
        result.outputVolume = volume(result.output, input: false)
        result.inputVolume = volume(result.input, input: true)
        result.canSetOutput = !volumeElements(result.output, input: false).isEmpty
        result.canSetInput = !volumeElements(result.input, input: true).isEmpty
        var mute: UInt32 = 0
        _ = read(result.output, address(kAudioDevicePropertyMute), into: &mute); result.outputMuted = mute != 0
        mute = 0; _ = read(result.input, address(kAudioDevicePropertyMute, input: true), into: &mute); result.inputMuted = mute != 0
        _ = read(result.output, global(kAudioDevicePropertyNominalSampleRate), into: &result.sampleRate)
        return result
    }
    static func levels(_ existing: AudioReading) -> AudioReading {
        var result = existing
        result.outputVolume = volume(result.output, input: false)
        result.inputVolume = volume(result.input, input: true)
        var muted: UInt32 = 0
        _ = read(result.output, address(kAudioDevicePropertyMute), into: &muted); result.outputMuted = muted != 0
        muted = 0
        _ = read(result.input, address(kAudioDevicePropertyMute, input: true), into: &muted); result.inputMuted = muted != 0
        return result
    }
    static func setVolume(_ value: Double, device: AudioObjectID, input: Bool) -> OSStatus {
        let elements = volumeElements(device, input: input)
        guard !elements.isEmpty else { return kAudioHardwareUnsupportedOperationError }
        for element in elements {
            let status = set(device, address(kAudioDevicePropertyVolumeScalar, input: input, element: element), value: Float32(min(1, max(0, value))))
            if status != noErr { return status }
        }
        return noErr
    }
}

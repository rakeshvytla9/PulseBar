import Foundation
import CoreAudio

/// Listen while audio controls are visible; coalesce slider/hardware events.
@MainActor final class AudioWatcher {
    var changed: ((Bool) -> Void)?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var pending: DispatchWorkItem?
    private var devicesChanged = false
    @discardableResult func start() -> AudioReading {
        stop()
        let system = AudioObjectID(kAudioObjectSystemObject)
        for property in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            add(system, address: AudioControl.global(property), devices: true)
        }
        let current = AudioControl.snapshot()
        for (device, input) in [(current.output, false), (current.input, true)] where device != 0 {
            add(device, address: AudioControl.address(kAudioDevicePropertyMute, input: input), devices: false)
            for element in AudioControl.volumeElements(device, input: input) {
                add(device, address: AudioControl.address(kAudioDevicePropertyVolumeScalar, input: input, element: element), devices: false)
            }
        }
        return current
    }
    private func add(_ id: AudioObjectID, address: AudioObjectPropertyAddress, devices: Bool) {
        var address = address
        guard AudioObjectHasProperty(id, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.schedule(devices) }
        }
        if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr { listeners.append((id, address, block)) }
    }
    private func schedule(_ devices: Bool) {
        devicesChanged = devicesChanged || devices
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let changed = self.devicesChanged
            self.pending = nil; self.devicesChanged = false
            self.changed?(changed)
            if changed { self.start() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
    func stop() {
        pending?.cancel(); pending = nil
        for (id, original, block) in listeners {
            var address = original
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        listeners.removeAll()
    }
}

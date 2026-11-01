import Carbon

@MainActor final class HotKeys {
    var onSelect: ((PanelSection) -> Void)?
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    private let sections: [PanelSection] = [.audio, .wifi, .display, .power]
    func enable(_ enabled: Bool) -> Bool {
        for key in keys { UnregisterEventHotKey(key) }; keys.removeAll()
        guard enabled else { return true }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard result == noErr else { return result }
                MainActor.assumeIsolated {
                    let controller = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
                    let index = Int(id.id) - 1
                    if controller.sections.indices.contains(index) { controller.onSelect?(controller.sections[index]) }
                }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return false }
        }
        let codes = [kVK_ANSI_A, kVK_ANSI_N, kVK_ANSI_D, kVK_ANSI_P]
        for (index, code) in codes.enumerated() {
            var key: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x504C5342), id: UInt32(index + 1))
            let status = RegisterEventHotKey(UInt32(code), UInt32(cmdKey | controlKey), id, GetApplicationEventTarget(), 0, &key)
            guard status == noErr, let key else {
                for key in keys { UnregisterEventHotKey(key) }; keys.removeAll(); return false
            }
            keys.append(key)
        }
        return true
    }
    func stop() {
        _ = enable(false)
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}

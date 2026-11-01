import Combine

/// Cached pages keep their view tree, but only the attached page forwards live
/// model notifications into SwiftUI. Hidden pages record one dirty flag.
@MainActor final class PanelRefresh: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    private var active = false
    private var dirty = true
    private var observations: [AnyCancellable] = []
    init(sources: [ObservableObjectPublisher]) {
        observations = sources.map { source in
            source.sink { [weak self] in
                guard let self else { return }
                if self.active { self.revision &+= 1 } else { self.dirty = true }
            }
        }
    }
    func setActive(_ value: Bool, refreshClock: Bool = false) {
        let wasActive = active
        active = value
        if value && (dirty || (refreshClock && !wasActive)) { dirty = false; revision &+= 1 }
    }
}

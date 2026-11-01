import AppKit

@MainActor final class Media: ObservableObject {
    @Published var player = "Music"
    @Published var title = "No player loaded"
    @Published var artist = ""
    @Published var state = ""
    @Published var message: String?
    func read() {
        let bundle = player == "Spotify" ? "com.spotify.client" : "com.apple.Music"
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty else { message = "Open \(player) first."; return }
        let name = player == "Spotify" ? "Spotify" : "Music"
        let script = "tell application \"\(name)\"\nif player state is stopped then\nreturn \"Stopped\"\nelse\nreturn (name of current track) & linefeed & (artist of current track) & linefeed & (player state as string)\nend if\nend tell"
        run(script) { text in
            let parts = text.components(separatedBy: "\n")
            self.title = parts.first ?? "Stopped"; self.artist = parts.count > 1 ? parts[1] : ""; self.state = parts.count > 2 ? parts[2] : ""
        }
    }
    func control(_ action: String) {
        guard ["playpause", "previous track", "next track"].contains(action) else { return }
        let name = player == "Spotify" ? "Spotify" : "Music"
        run("tell application \"\(name)\" to \(action)") { _ in self.read() }
    }
    private func run(_ source: String, completion: @escaping (String) -> Void) {
        // Runs only on an explicit media action; no background AppleEvents polling.
        var error: NSDictionary?
        let value = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { message = error[NSAppleScript.errorMessage] as? String ?? "Player access was not granted." }
        else { message = nil; completion(value?.stringValue ?? "") }
    }
}

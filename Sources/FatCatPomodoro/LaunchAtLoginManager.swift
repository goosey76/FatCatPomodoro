import Foundation

class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? enable() : disable()
        }
    }

    private let agentLabel = "com.fatcat.FatCatPomodoro"

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    private init() {
        isEnabled = FileManager.default.fileExists(atPath:
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/com.fatcat.FatCatPomodoro.plist").path
        )
    }

    private func enable() {
        let execPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]

        let plist: [String: Any] = [
            "Label":           agentLabel,
            "ProgramArguments": [execPath],
            "RunAtLoad":       true,
            "KeepAlive":       false
        ]

        (plist as NSDictionary).write(to: plistURL, atomically: true)

        run("/bin/launchctl", args: ["load", "-w", plistURL.path])
    }

    private func disable() {
        run("/bin/launchctl", args: ["unload", "-w", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private func run(_ path: String, args: [String]) {
        let task = Process()
        task.launchPath = path
        task.arguments  = args
        try? task.run()
        task.waitUntilExit()
    }
}

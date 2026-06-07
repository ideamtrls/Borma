import OSLog

/// Categorized `Logger` instances. Subsystem matches the app's bundle id so
/// entries can be filtered in `Console.app` and the `log` CLI.
enum Log {
    private static let subsystem = AppInfo.bundleID

    static let app = Logger(subsystem: subsystem, category: "app")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let frecency = Logger(subsystem: subsystem, category: "frecency")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let scanner = Logger(subsystem: subsystem, category: "scanner")
}

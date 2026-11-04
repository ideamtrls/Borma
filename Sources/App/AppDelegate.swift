import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var panel: PanelController?
    private var hotkey: HotkeyController?
    private var configWatcher: FileWatcher?
    private var appWatcher: FileWatcher?

    private let welcome = WelcomeFlag()

    let config: ConfigStore = {
        let store = ConfigStore(fileURL: appSupportDir().appendingPathComponent("config.json"))
        store.load()
        return store
    }()

    private let frecency: FrecencyStore = {
        let store = FrecencyStore(fileURL: appSupportDir().appendingPathComponent("frecency.json"))
        store.load()
        return store
    }()

    private lazy var model: LauncherModel = {
        let m = LauncherModel(frecency: frecency)
        m.onLaunch = { [frecency] app, query in
            frecency.record(query: query, bundleId: app.bundleId)
            AppLauncher.launch(app)
        }
        return m
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = PanelController(model: model, config: config, welcome: welcome)
        self.panel = panel
        model.onDismissRequested = { [weak panel] in panel?.hide() }

        hotkey = HotkeyController(
            onTrigger: { [weak panel] in panel?.toggle() },
            onBindingChanged: { [weak self, weak panel] isOnFallback, activeShortcut in
                guard let self else { return }
                let conflictIsNew = isOnFallback && !self.model.conflictActive
                self.model.conflictActive = isOnFallback
                self.model.activeHotkey = activeShortcut
                // The usual hotkey just stopped working, so open the panel to
                // show the one that replaced it.
                if conflictIsNew { panel?.show() }
            }
        )

        Task { await rescan() }
        startConfigWatcher()
        startAppWatcher()

        if welcome.isActive, !model.conflictActive {
            panel.show()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        panel?.show()
        return false
    }

    /// Called by the Settings recorder whenever the user changes the hotkey.
    func refreshHotkeyBinding() {
        hotkey?.evaluateBinding()
    }

    private func rescan() async {
        let urls = config.searchPaths.map { URL(fileURLWithPath: $0) }
        model.apps = await AppScanner.scan(paths: urls)
    }

    private func startConfigWatcher() {
        let dir = config.fileURL.deletingLastPathComponent().path
        let watcher = FileWatcher(paths: [dir])
        configWatcher = watcher
        let events = watcher.events
        Task { [weak self] in
            for await _ in events {
                guard let self else { return }
                // The watcher covers the whole App Support directory, so
                // frecency saves and ConfigStore's own writes land here too.
                // Only rescan and re-attach the app watcher when the config
                // actually changed.
                let previous = self.config.config
                self.config.load()
                guard self.config.config != previous else { continue }
                await self.rescan()
                self.startAppWatcher()
            }
        }
    }

    private func startAppWatcher() {
        let paths = config.searchPaths
        guard !paths.isEmpty else {
            appWatcher = nil
            return
        }
        let watcher = FileWatcher(paths: paths)
        appWatcher = watcher
        let events = watcher.events
        Task { [weak self] in
            for await _ in events {
                guard let self else { return }
                await self.rescan()
            }
        }
    }
}

private func appSupportDir() -> URL {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent(AppInfo.bundleID, isDirectory: true)
    do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        Log.app.error("Failed to create application-support directory at \(dir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
    return dir
}

import AppKit
import SwiftUI

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelController {
    private let panel: FloatingPanel
    private let model: LauncherModel
    private let config: ConfigStore
    private let welcome: WelcomeFlag
    private let hosting: NSHostingView<SearchView>

    private var settingsWindow: NSWindow?

    init(model: LauncherModel, config: ConfigStore, welcome: WelcomeFlag) {
        self.model = model
        self.config = config
        self.welcome = welcome

        model.welcomeActive = welcome.isActive

        let contentRect = NSRect(
            x: 0, y: 0,
            width: LauncherDimensions.panelWidth,
            height: LauncherDimensions.fieldHeight
        )
        panel = FloatingPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false

        hosting = NSHostingView(rootView: SearchView(model: model, config: config))
        hosting.frame = contentRect
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func hide() {
        panel.orderOut(nil)
        model.reset()
        if welcome.isActive {
            welcome.retire()
            model.welcomeActive = false
        }
    }

    func show() {
        model.reset()
        resize()
        position()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        observeResults()
    }

    private func observeResults() {
        withObservationTracking {
            _ = model.results.count
            _ = model.query.isEmpty
            _ = model.welcomeActive
            _ = model.conflictActive
            _ = config.config.alwaysShowHint
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, panel.isVisible else { return }
                self.resize()
                self.observeResults()
            }
        }
    }

    @objc private func panelResignedKey(_ note: Notification) {
        if settingsWindow != nil { return }
        // Defer to the next runloop turn: AppKit hasn't installed the new key
        // window yet when this notification fires.
        Task { [weak self] in
            guard let self else { return }
            if let newKey = NSApp.keyWindow, newKey !== self.panel {
                self.adoptSettingsWindow(newKey)
            }
        }
    }

    private func adoptSettingsWindow(_ window: NSWindow) {
        settingsWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func settingsWindowWillClose(_ note: Notification) {
        if let win = settingsWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: win
            )
        }
        settingsWindow = nil

        if panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func position() {
        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main ?? NSScreen.screens.first!

        let frame = screen.visibleFrame
        let width = LauncherDimensions.panelWidth
        let height = panel.frame.height
        let x = frame.midX - width / 2
        let y = frame.maxY - (frame.height / 3) - height / 2
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
    }

    private func resize() {
        let width = LauncherDimensions.panelWidth
        let showHint = (model.welcomeActive || model.conflictActive || config.config.alwaysShowHint) && model.query.isEmpty
        let inputHeight = LauncherDimensions.inputSectionHeight(resultCount: model.results.count)
        let newHeight = inputHeight + (showHint ? LauncherDimensions.bibHeight : 0)

        var frame = panel.frame
        frame.origin.y -= newHeight - frame.height
        frame.size.height = newHeight
        frame.size.width = width
        panel.setFrame(frame, display: true, animate: false)
    }
}

import AppKit
import SwiftUI

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Where the panel stands from the hotkey's point of view.
enum PanelPresence: Equatable {
    case hidden
    /// On screen, but another window has keyboard focus.
    case unfocused
    case focused

    init(isVisible: Bool, isKey: Bool) {
        switch (isVisible, isKey) {
        case (false, _): self = .hidden
        case (true, false): self = .unfocused
        case (true, true): self = .focused
        }
    }
}

final class PanelController {
    private let panel: FloatingPanel
    private let model: LauncherModel
    private let config: ConfigStore
    private let welcome: WelcomeFlag
    private let hosting: NSHostingView<SearchView>

    private var settingsWindow: NSWindow?

    /// The app to hand focus back to when the panel is cancelled. `nil` when
    /// the panel opened over Borma itself.
    private var appBeneath: NSRunningApplication?

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

    /// What the hotkey and the menu bar's Show Borma do.
    func summon() {
        switch PanelPresence(isVisible: panel.isVisible, isKey: panel.isKeyWindow) {
        case .hidden:
            show()
        case .unfocused:
            rememberAppBeneath()
            takeFocus()
        case .focused:
            hide(.cancelled)
        }
    }

    func hide(_ dismissal: PanelDismissal) {
        panel.orderOut(nil)
        model.reset()
        if welcome.isActive {
            welcome.retire()
            model.welcomeActive = false
        }
        returnFocus(after: dismissal)
    }

    func show() {
        rememberAppBeneath()
        model.reset()
        resize()
        position()
        takeFocus()
        observeResults()
    }

    private func takeFocus() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Called before Borma activates. With Borma already frontmost there's
    /// nothing new to remember, and `hide(_:)` has already cleared any old app.
    private func rememberAppBeneath() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != NSRunningApplication.current.processIdentifier
        else { return }
        appBeneath = front
    }

    private func returnFocus(after dismissal: PanelDismissal) {
        let app = appBeneath
        appBeneath = nil
        switch dismissal {
        case .launching:
            return
        case .cancelled:
            // If Borma isn't active, the user has already moved on to another
            // app. An open Settings window keeps focus inside Borma.
            guard NSApp.isActive, settingsWindow == nil else { return }
            app?.activate()
        }
    }

    /// For callers with no user gesture behind them: opening clears the query,
    /// so a panel that's already up keeps what's being typed.
    func showIfHidden() {
        if !panel.isVisible { show() }
    }

    private func observeResults() {
        withObservationTracking {
            _ = model.results.count
            _ = model.query.isEmpty
            _ = model.welcomeActive
            _ = model.hotkeyBinding
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
            takeFocus()
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
        let y = LauncherDimensions.openingY(
            height: height,
            fullHeight: LauncherDimensions.inputSectionHeight(resultCount: LauncherModel.maxResults),
            in: frame
        )
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
    }

    private func resize() {
        let width = LauncherDimensions.panelWidth
        let showHint = (model.welcomeActive || model.hotkeyBinding == .fallback || config.config.alwaysShowHint) && model.query.isEmpty
        let inputHeight = LauncherDimensions.inputSectionHeight(resultCount: model.results.count)
        let newHeight = inputHeight + (showHint ? LauncherDimensions.bibHeight : 0)

        var frame = panel.frame
        frame.origin.y -= newHeight - frame.height
        frame.size.height = newHeight
        frame.size.width = width
        if let visible = panel.screen?.visibleFrame {
            frame.origin.y = LauncherDimensions.clampedY(frame.origin.y, height: newHeight, in: visible)
        }
        panel.setFrame(frame, display: true, animate: false)
    }
}

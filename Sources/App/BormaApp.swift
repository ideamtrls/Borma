import KeyboardShortcuts
import ServiceManagement
import SwiftUI

@main
struct BormaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        MenuBarExtra("Borma", image: "MenuBarIcon") {
            Button("Show Borma") { delegate.panel?.summon() }
            Button("Settings…") {
                // A menu click doesn't activate an accessory app, so without
                // this the window can open behind the frontmost app.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Quit Borma") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }

        Settings {
            SettingsView(
                config: delegate.config,
                onShortcutChange: { [delegate] in delegate.refreshHotkeyBinding() }
            )
        }
    }
}

private struct SettingsView: View {
    @Bindable var config: ConfigStore
    let onShortcutChange: () -> Void
    @State private var loginItemStatus = SMAppService.mainApp.status

    /// The side effect lives in the setter rather than an `onChange`, so
    /// refreshing `loginItemStatus` can't trigger another register or unregister.
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { loginItemStatus == .enabled },
            set: { setLaunchAtLogin($0) }
        )
    }

    private var useSystemAccent: Binding<Bool> {
        Binding(
            get: { config.config.highlightColor == nil },
            set: { config.config.highlightColor = $0 ? nil : HexColor(color: .accentColor) }
        )
    }

    private var highlightColor: Binding<Color> {
        Binding(
            get: { config.config.highlightColor?.color ?? .accentColor },
            set: { config.config.highlightColor = HexColor(color: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                KeyboardShortcuts.Recorder("Hotkey:", name: .toggleBorma) { _ in
                    onShortcutChange()
                }
                Toggle("Launch at login", isOn: launchAtLogin)
                if loginItemStatus == .requiresApproval {
                    Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Toggle("Always show hotkey", isOn: $config.config.alwaysShowHint)
                Toggle("Use system accent color", isOn: useSystemAccent)
                ColorPicker("Highlight color:", selection: highlightColor, supportsOpacity: false)
                    .disabled(config.config.highlightColor == nil)
            }
            .formStyle(.grouped)
            .onChange(of: config.config) { _, _ in config.save() }

            Text("an ideamtrls thing")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 420)
        // The status can change in System Settings, which sends no notification
        // of its own, so re-read it on the way back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemStatus = SMAppService.mainApp.status
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Failed to \(enabled ? "register" : "unregister", privacy: .public) launch-at-login: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
        loginItemStatus = SMAppService.mainApp.status
    }
}

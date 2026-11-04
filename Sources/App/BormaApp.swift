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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
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
            launchAtLogin = SMAppService.mainApp.status == .enabled
            NSSound.beep()
        }
    }
}

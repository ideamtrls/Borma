import AppKit
import KeyboardShortcuts
import SwiftUI

/// The launcher's outer silhouette. When `hasBib` is false this is a plain
/// rounded rectangle; otherwise it draws the input rectangle and a narrower
/// rounded bib hanging off the bottom, joined by two concave fillets so the
/// whole thing reads as a single continuous surface. Marked `nonisolated`
/// because `Shape` is a `Sendable` protocol whose `path(in:)` requirement is
/// nonisolated; SwiftUI calls it off the main actor.
private nonisolated struct LauncherSurface: Shape {
    var inputHeight: CGFloat
    var bibWidth: CGFloat
    var hasBib: Bool
    var cornerRadius: CGFloat = LauncherDimensions.cornerRadius
    var notchRadius: CGFloat = LauncherDimensions.notchRadius

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let r = cornerRadius

        guard hasBib, bibWidth > 0, inputHeight > 0, inputHeight < h else {
            return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        }

        let nr = notchRadius
        let bL = (w - bibWidth) / 2
        let bR = (w + bibWidth) / 2
        let iH = inputHeight

        var p = Path()
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: iH - r))
        p.addQuadCurve(to: CGPoint(x: w - r, y: iH), control: CGPoint(x: w, y: iH))
        p.addLine(to: CGPoint(x: bR + nr, y: iH))
        p.addQuadCurve(to: CGPoint(x: bR, y: iH + nr), control: CGPoint(x: bR, y: iH))
        p.addLine(to: CGPoint(x: bR, y: h - r))
        p.addQuadCurve(to: CGPoint(x: bR - r, y: h), control: CGPoint(x: bR, y: h))
        p.addLine(to: CGPoint(x: bL + r, y: h))
        p.addQuadCurve(to: CGPoint(x: bL, y: h - r), control: CGPoint(x: bL, y: h))
        p.addLine(to: CGPoint(x: bL, y: iH + nr))
        p.addQuadCurve(to: CGPoint(x: bL - nr, y: iH), control: CGPoint(x: bL, y: iH))
        p.addLine(to: CGPoint(x: r, y: iH))
        p.addQuadCurve(to: CGPoint(x: 0, y: iH - r), control: CGPoint(x: 0, y: iH))
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}

struct SearchView: View {
    @Bindable var model: LauncherModel
    let config: ConfigStore
    @FocusState private var isFieldFocused: Bool

    private var footerHintLine: String {
        formatShortcut(model.activeHotkey)
    }

    private func formatShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) -> String {
        guard let shortcut else { return "—" }
        var parts: [String] = []
        let mods = shortcut.modifiers
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option)  { parts.append("⌥") }
        if mods.contains(.shift)   { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        // KeyboardShortcuts has no public Key→glyph helper; strip the
        // modifier glyphs from `.description` (its public rendered form) to
        // recover the key name on its own.
        let modifierGlyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        let keyName = shortcut.description.filter { !modifierGlyphs.contains($0) }
        if !keyName.isEmpty {
            parts.append(keyName == "Space" ? "␣" : keyName)
        }
        return parts.joined(separator: " + ")
    }

    private var shouldShowHint: Bool {
        (model.welcomeActive || model.conflictActive || config.config.alwaysShowHint) && model.query.isEmpty
    }

    private var surface: LauncherSurface {
        LauncherSurface(
            inputHeight: LauncherDimensions.inputSectionHeight(resultCount: model.results.count),
            bibWidth: LauncherDimensions.bibWidth,
            hasBib: shouldShowHint
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            surface
                .fill(.ultraThinMaterial)

            VStack(spacing: 0) {
                inputContent

                if shouldShowHint {
                    Text(footerHintLine)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 3)
                        .frame(
                            width: LauncherDimensions.bibWidth,
                            height: LauncherDimensions.bibHeight
                        )
                }
            }
        }
        .clipShape(surface)
        .onAppear { isFieldFocused = true }
    }

    private var inputContent: some View {
        VStack(spacing: 0) {
            TextField("Search…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.primary)
                .focused($isFieldFocused)
                .padding(.horizontal, 20)
                .frame(height: LauncherDimensions.fieldHeight)
                .onSubmit { model.launchSelection() }
                .onKeyPress(.escape) {
                    model.onDismissRequested?()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.selectPrev()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    model.selectNext()
                    return .handled
                }

            let results = model.results
            if !results.isEmpty {
                let selected = model.selectedApp(in: results)
                Divider().opacity(0.2)
                VStack(spacing: 0) {
                    ForEach(results) { app in
                        ResultRow(
                            app: app,
                            isSelected: app.id == selected?.id,
                            highlight: config.highlightColor
                        )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selection = app.id
                                model.launchSelection()
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct ResultRow: View {
    let app: AppRecord
    let isSelected: Bool
    let highlight: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: LauncherDimensions.resultIconSize, height: LauncherDimensions.resultIconSize)
            Text(app.displayName)
                .font(.system(size: 22))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: LauncherDimensions.rowHeight)
        .background(isSelected ? highlight.opacity(0.22) : Color.clear)
    }
}

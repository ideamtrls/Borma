import Foundation

/// Pixel-grid dimensions for the launcher panel. Marked `nonisolated` so the
/// values can be read from `Shape.path(in:)`, which executes off the main
/// actor under strict concurrency.
nonisolated enum LauncherDimensions {
    static let panelWidth: CGFloat = 640
    static let fieldHeight: CGFloat = 79
    static let rowHeight: CGFloat = 64
    static let resultIconSize: CGFloat = 44
    static let resultsPadding: CGFloat = 9
    static let conflictHeight: CGFloat = 80
    static let bibHeight: CGFloat = 38
    static let bibWidth: CGFloat = 120
    static let cornerRadius: CGFloat = 12
    static let notchRadius: CGFloat = 8

    /// Height of the search field plus result list plus the optional
    /// hotkey-conflict banner. Excludes the welcome bib, which hangs off the
    /// bottom and is added by the panel layout separately.
    static func inputSectionHeight(resultCount: Int, hasConflict: Bool) -> CGFloat {
        var h = fieldHeight
        if resultCount > 0 {
            h += CGFloat(resultCount) * rowHeight + resultsPadding
        }
        if hasConflict {
            h += conflictHeight
        }
        return h
    }
}

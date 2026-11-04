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
    static let bibHeight: CGFloat = 38
    static let bibWidth: CGFloat = 120
    static let cornerRadius: CGFloat = 12
    static let notchRadius: CGFloat = 8

    /// Height of the search field plus result list. Excludes the bib, which
    /// hangs off the bottom and is added by the panel layout separately.
    static func inputSectionHeight(resultCount: Int) -> CGFloat {
        var h = fieldHeight
        if resultCount > 0 {
            h += CGFloat(resultCount) * rowHeight + resultsPadding
        }
        return h
    }

    /// The bottom edge for a panel opening on a screen: its center one-third
    /// from the top, moved up if needed so a full result list fits below the
    /// search field. Reserving the room up front keeps the field from jumping
    /// as results appear.
    static func openingY(height: CGFloat, fullHeight: CGFloat, in visible: CGRect) -> CGFloat {
        let preferred = visible.maxY - visible.height / 3 - height / 2
        let roomForFullList = visible.minY + fullHeight - height
        return clampedY(max(preferred, roomForFullList), height: height, in: visible)
    }

    /// Keeps a panel of `height` on screen. One too tall to fit stays aligned
    /// to the top, which keeps the search field reachable.
    static func clampedY(_ y: CGFloat, height: CGFloat, in visible: CGRect) -> CGFloat {
        min(max(y, visible.minY), visible.maxY - height)
    }
}

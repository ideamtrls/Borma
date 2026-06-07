import Foundation

/// The app's identity, read from the bundle at runtime. The bundle id is
/// defined once in `project.yml` (`PRODUCT_BUNDLE_IDENTIFIER`) and flows into
/// the generated Info.plist; reading it back here keeps the logging subsystem
/// and the Application Support directory name from drifting from it. The
/// literal is only a fallback for non-bundled contexts (unit tests, previews).
enum AppInfo {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.ideamtrls.borma"
}

---
scope: xcodegen project generation, build settings, signing, app sandbox behavior, SPM dependencies, asset catalog, dev loop
globs: [project.yml, Borma.entitlements, Sources/Resources/**]
keywords: [build, xcodegen, signing, entitlements, app sandbox, sandbox container, hardened runtime, SPM, dependency, Package.resolved, project.yml, xcodebuild, code signing, unsigned build, project file regenerated, new file not compiled, Xcode dev team not set, package dependency change, CI build fails on signing, version bump, MARKETING_VERSION, Info.plist, LSUIElement, deployment target, bundle id, asset catalog, AppIcon, menu bar icon, app icon blank or missing]
updated: 2026-11-03
---

# Build & run

Generating the Xcode project with xcodegen, build settings, signing and the app sandbox, SPM dependencies, the asset catalog, and the dev loop.

## Where things live
- Project spec (target, build settings, package): `project.yml`
- Entitlements: `Borma.entitlements`, wired by `CODE_SIGN_ENTITLEMENTS`
- Generated project, gitignored: `Borma.xcodeproj/`
- Resolved package versions, gitignored: `Borma.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Version numbers: `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` in `project.yml`
- Info.plist keys: `INFOPLIST_KEY_*` in `project.yml`
- Asset catalog: `Sources/Resources/Assets.xcassets`, sets `AppIcon.appiconset` and `MenuBarIcon.imageset`
- Menu bar icon reference: `Sources/App/BormaApp.swift`, `BormaApp.body`
- Bundle id read back at runtime: `Sources/App/AppInfo.swift`, `AppInfo.bundleID`
- Code the sandbox affects: `appSupportDir()` in `Sources/App/AppDelegate.swift`, `AppScanner` in `Sources/Search/Apps.swift`

## First-time setup

```bash
brew install xcodegen     # if not installed
xcodegen generate         # writes Borma.xcodeproj from project.yml
open Borma.xcodeproj      # then set your dev team in Signing & Capabilities
```

In Xcode: **Borma target → Signing & Capabilities → Team**, pick your own team. `CODE_SIGN_STYLE = Automatic` is already configured, so Xcode handles the certificate and provisioning profile. `project.yml` sets no `DEVELOPMENT_TEAM`, so the team lives only in the generated project and every `xcodegen generate` clears it. Pick it again after regenerating.

⌘R to build and run. A debug build and an installed `/Applications/Borma.app` share a bundle id, so they share a sandbox container (config, frecency, saved hotkey) and both try to register the hotkey. Quit the installed copy first.

## Build settings

All in `project.yml`, under the `Borma` target unless noted:

- **Swift:** `SWIFT_VERSION: "6.0"` plus `OTHER_SWIFT_FLAGS: "-default-isolation MainActor"`, so declarations are main-actor isolated unless marked otherwise.
- **Deployment target:** macOS 26.0, set in both `options.deploymentTarget.macOS` (project level) and `MACOSX_DEPLOYMENT_TARGET` (target level). Keep them in step.
- **Info.plist:** generated (`GENERATE_INFOPLIST_FILE: YES`). The repo has no `Info.plist`, so a new key goes in as an `INFOPLIST_KEY_*` setting. `INFOPLIST_KEY_LSUIElement: YES` is what removes the Dock icon.
- **Bundle id:** `PRODUCT_BUNDLE_IDENTIFIER`. `AppInfo.bundleID` reads it from the bundle for the log subsystem and the Application Support directory name, with a `com.ideamtrls.borma` literal as a fallback for non-bundled contexts. Change the literal along with the setting.
- **Version:** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Bump them here, then regenerate.

Built app bundles stay out of git: `/Borma/` is gitignored and builds are distributed through GitHub Releases. The repo has no release script.

## Signing & entitlements

`project.yml` wires three signing-related settings: `CODE_SIGN_STYLE = Automatic`, `ENABLE_HARDENED_RUNTIME = YES`, and `CODE_SIGN_ENTITLEMENTS = Borma.entitlements`. The entitlements file is tiny — it enables `com.apple.security.app-sandbox` only. Borma is sandboxed on purpose, so features work within the sandbox rather than around it. Add new capabilities (e.g. a security-scoped bookmark or network access) by editing `Borma.entitlements` directly; it's referenced by path from `project.yml`, so no `xcodegen generate` is needed for entitlement-only changes (regenerate only if you change the `CODE_SIGN_ENTITLEMENTS` wiring itself).

## App sandbox at runtime

Any build signed with `Borma.entitlements` runs sandboxed, which changes what file-touching code sees:

- **Home and Application Support resolve inside the container**, `~/Library/Containers/com.ideamtrls.borma/Data/`. Config, frecency, and `UserDefaults` all live there; `overview.md` ("Persistence") has the paths.
- **The container is named after the bundle id**, so changing `PRODUCT_BUNDLE_IDENTIFIER` starts from empty config, frecency, and hotkey bindings.
- **Other apps' preference files are unreadable**, including the symbolic hotkeys plist, which is why conflict detection goes through Carbon; see `hotkey.md` ("Spotlight detection").
- **Search roots:** `/Applications` and `/System/Applications` are readable. A `searchPaths` entry the sandbox can't read, such as a directory under the real home, still passes `AppScanner`'s `fileExists` check, then lists as empty, so it silently contributes no apps. Test custom roots in a signed build.
- **Unsigned builds have no sandbox.** With no entitlements, the app sees the real home directory, and keeps separate state in `~/Library/Application Support/com.ideamtrls.borma/`, so it behaves differently from a signed build in all of the above.

## Resources / asset catalog

`Sources/Resources/Assets.xcassets` holds the two image assets:

- **`AppIcon`** — the app icon set. Wired by `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in `project.yml`; if you rename the set, change that setting in the same edit. `actool` reports nothing for a name that matches no set, so the build passes and the app silently ships with no icon.
- **`MenuBarIcon`** — the status-item image, a template-rendered image set (20 pt, at @1x, @2x, and @3x) referenced by name in `MenuBarExtra("Borma", image: "MenuBarIcon")` (`Sources/App/BormaApp.swift`). The name is a string, so the compiler doesn't catch a renamed set.

The catalog sits under the `Sources` path, so `xcodegen` picks it up automatically and references it as a single asset-catalog folder. Adding a set, or adding or swapping an image inside one, needs no `xcodegen generate`. Regenerate only when you wire a *new* top-level setting (e.g. a second app icon via a new `ASSETCATALOG_*` key).

## Regenerating after project changes

Regenerate after any `project.yml` change (new dependency, build setting, version bump) and after adding, removing, or renaming a source file. `path: Sources` covers the whole tree without a `project.yml` edit, but the generated project lists each file individually, so a new `.swift` file doesn't compile until you regenerate.

```bash
xcodegen generate
```

Xcode picks up the regenerated project automatically.

## Never edit Borma.xcodeproj by hand

The generated `Borma.xcodeproj/` is gitignored, which keeps Xcode's randomly-ordered `project.pbxproj` out of diffs and merge conflicts. `project.pbxproj` is a build artifact, and direct edits are wiped on the next `xcodegen generate`. That includes anything changed through Xcode's UI, such as the version or app category. To change a build setting, source root, or dependency, edit `project.yml` and regenerate.

## CLI builds (optional)

```bash
xcodebuild -project Borma.xcodeproj -scheme Borma -configuration Debug build
```

`project.yml` declares no schemes; `xcodebuild` autocreates `Borma`, so this works on a freshly generated project. Signing still needs a team: pick one in Xcode or add `DEVELOPMENT_TEAM=<id>` to the command.

For ad-hoc unsigned testing builds (useful in CI-like contexts; the repo has no CI config):

```bash
xcodebuild -project Borma.xcodeproj -scheme Borma -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

These work for compile checks, but they run unsandboxed, so they can't validate runtime behavior the sandbox affects.

## Dependencies

Single SPM package: `KeyboardShortcuts` (Sindre Sorhus), declared in `project.yml`'s `packages:` section as `from: 2.0.0`. That is a floor up to the next major version, not a pin. SPM resolves on first Xcode open or `xcodebuild` run. `Package.resolved` lives inside `Borma.xcodeproj/` and isn't committed, so a fresh clone takes the newest 2.x.

To add a package, add it to `packages:` and to the target's `dependencies:`, then regenerate.

## See also
- `concurrency.md` — what `-default-isolation MainActor` means for the code.

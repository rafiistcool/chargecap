# Build & Configuration

## Project Structure

```
chargecap/
├── ChargeCap.xcodeproj/          # Xcode project
├── ChargeCap/                    # Main app target
│   ├── ChargeCapApp.swift        # @main entry point
│   ├── Info.plist                # App metadata
│   ├── Assets.xcassets/          # Icons and colors
│   ├── Helpers/
│   │   └── Constants.swift       # Shared constants (intervals, limits)
│   ├── Models/
│   │   ├── BatteryState.swift    # Battery state data model
│   │   └── ChargeControlModels.swift  # Enums: state, command, fan mode
│   ├── Services/
│   │   ├── AppSettings.swift     # UserDefaults-backed settings
│   │   ├── BatteryMonitor.swift  # IOKit battery reading (30s timer)
│   │   ├── ChargeController.swift # Charge limiting state machine
│   │   ├── PrivilegedHelperManager.swift  # XPC client + SafeContinuation
│   │   └── ProManager.swift      # StoreKit 2 in-app purchases
│   └── Views/
│       ├── MenuBarView.swift     # Menu bar dropdown UI
│       └── SettingsView.swift    # Settings window (6 sections)
├── ChargeCapHelper/              # Privileged helper target (runs as root)
│   ├── main.swift                # NSXPCListener entry point
│   ├── HelperTool.swift          # XPC protocol implementation
│   ├── SMC.swift                 # SMCKit — IOKit SMC communication
│   ├── Helper-Info.plist         # Helper bundle info
│   └── Helper-Launchd.plist      # launchd daemon configuration
├── Shared/                       # Code shared between both targets
│   └── ChargeCapHelperProtocol.swift  # XPC protocol + config
├── docs/                         # Documentation
└── README.md
```

## Targets

### ChargeCap (Main App)

| Property | Value |
|----------|-------|
| Bundle ID | `com.chargecap.ChargeCap` |
| Platform | macOS 26+ |
| UI Framework | SwiftUI |
| Type | Menu bar app (`MenuBarExtra`) |
| Development Team | `XGCYZ8NBU4` |

**Linked Frameworks:**
- `IOKit.framework` — Battery monitoring via IOPowerSources and IORegistry
- `ServiceManagement.framework` — `SMAppService.daemon()` for helper registration
- `StoreKit.framework` — In-app purchases (Pro unlock)

### ChargeCapHelper (Privileged Helper)

| Property | Value |
|----------|-------|
| Bundle ID | `com.chargecap.Helper` |
| Platform | macOS |
| Type | Command-line tool (launchd daemon) |
| Runs as | root |
| Development Team | `XGCYZ8NBU4` |

**Linked Frameworks:**
- `IOKit.framework` — SMC driver communication

## Build Phases

### ChargeCap Target

1. **Compile Sources** — All Swift files from `ChargeCap/` and `Shared/`
2. **Link Frameworks** — IOKit, ServiceManagement, StoreKit
3. **Copy Resources** — `Assets.xcassets`
4. **CopyFiles (LaunchServices)** — Copies the `ChargeCapHelper` binary into `Contents/Library/LaunchServices/` inside the app bundle, with code signing on copy
5. **Copy Helper Launchd Plist** — Shell script build phase:
   ```bash
   cp "${SRCROOT}/ChargeCapHelper/Helper-Launchd.plist" \
      "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Library/LaunchDaemons/com.chargecap.Helper.plist"
   ```
   This places the launchd plist where `SMAppService.daemon(plistName:)` expects it

### ChargeCapHelper Target

1. **Preprocess Helper-Info.plist**
2. **Compile Sources** — `main.swift`, `HelperTool.swift`, `SMC.swift`, `ChargeCapHelperProtocol.swift`
3. **Link Frameworks** — `IOKit.framework`

## Key Build Settings

### Both Targets

| Setting | Value |
|---------|-------|
| `SWIFT_VERSION` | 5.0 (Swift 6 language mode awareness) |
| `DEVELOPMENT_TEAM` | `XGCYZ8NBU4` |
| `CODE_SIGN_STYLE` | Automatic |

### App Target Specific

| Setting | Value |
|---------|-------|
| `MACOSX_DEPLOYMENT_TARGET` | 26.0 |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.chargecap.ChargeCap` |

### Helper Target Specific

| Setting | Value |
|---------|-------|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.chargecap.Helper` |
| `PRODUCT_NAME` | `ChargeCapHelper` |

## Code Signing

Both the app and helper must be signed by the same development team (`XGCYZ8NBU4`). The helper binary is code-signed on copy (CopyFiles build phase has `CodeSignOnCopy` enabled).

For distribution, both targets need proper signing with a Developer ID certificate. The helper needs to run as root via launchd, so proper code signing is essential for `SMAppService.daemon()` to accept the registration.

## Adding New Files

### To the main app:
1. Add the `.swift` file to `ChargeCap/` (appropriate subfolder)
2. It should appear automatically in the Compile Sources phase
3. If not, manually add to the ChargeCap target in Xcode

### To the helper:
1. Add the `.swift` file to `ChargeCapHelper/`
2. Add to the ChargeCapHelper target's Compile Sources phase
3. Remember: helper has no SwiftUI, no AppKit — Foundation + IOKit only

### Shared between both:
1. Add to `Shared/`
2. Add to **both** targets' Compile Sources phases
3. Must use only Foundation types (no platform-specific frameworks)

## Dependencies

ChargeCap has **zero external dependencies**. Everything is built on Apple's system frameworks:

| Framework | Used By | Purpose |
|-----------|---------|---------|
| SwiftUI | App | UI |
| AppKit | App | `NSApp` access for window management |
| IOKit | Both | Battery monitoring (app) + SMC control (helper) |
| ServiceManagement | App | `SMAppService.daemon()` helper registration |
| StoreKit | App | In-app purchases |
| Foundation | Both | Core types, XPC, UserDefaults |

# Architecture

## Overview

ChargeCap is a native macOS menu-bar app built with SwiftUI. It monitors battery state and controls charging through the System Management Controller (SMC) via a privileged helper daemon.

```
┌─────────────────────────────────────────────────────┐
│                    ChargeCap.app                    │
│                                                     │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │ MenuBarView  │  │ SettingsView │  │ ProManager│  │
│  └──────┬──────┘  └──────┬───────┘  └───────────┘  │
│         │                │                          │
│  ┌──────▼────────────────▼──────┐   ┌───────────┐  │
│  │      ChargeController        │◄──┤AppSettings│  │
│  │      (state machine)         │   └───────────┘  │
│  └──────┬───────────────────────┘                   │
│         │                                           │
│  ┌──────▼──────┐  ┌─────────────────────────────┐   │
│  │BatteryMonitor│  │ PrivilegedHelperManager     │   │
│  │ (IOKit read) │  │ (XPC client)                │   │
│  └─────────────┘  └──────────┬──────────────────┘   │
│                              │ NSXPCConnection      │
└──────────────────────────────┼──────────────────────┘
                               │ Mach IPC
┌──────────────────────────────▼──────────────────────┐
│               ChargeCapHelper (root)                 │
│                                                      │
│  ┌────────────┐  ┌──────────────────────────────┐    │
│  │ HelperTool  │  │ SMCKit (IOKit driver calls)  │    │
│  │ (XPC server)│──┤ AppleSMCKeysEndpoint/AppleSMC│    │
│  └────────────┘  └──────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

## Layers

### 1. UI Layer — SwiftUI Views

| Component | Role |
|-----------|------|
| `MenuBarView` | Menu bar dropdown: battery %, charging status, health, temperature, cycles, adapter info |
| `SettingsView` | Settings window: charge limit slider, sailing mode, heat protection, fan control, alerts, scheduling, helper install, about/pro |
| `ChargeCapApp` | App entry point: creates `MenuBarExtra`, settings `Window`, wires all services together |

The menu bar icon is dynamic:
- ⛵ Sailboat when sailing mode is active
- ⚡ Bolt.slash when charge limiting is active
- 🔋 Battery icon otherwise
- Optional percentage label beside the icon

The settings window uses `Window(id: "settings")` instead of the `Settings` scene because macOS 26 blocks `NSApp.sendAction(Selector("showSettingsWindow:"))` with the error *"Please use SettingsLink for opening the Settings scene"*. Using a named `Window` scene with `openWindow(id: "settings")` works reliably.

### 2. Logic Layer — ChargeController

`ChargeController` is the brain of the app. It's a `@MainActor ObservableObject` that evaluates the current battery state against user settings and decides what charge command to send.

**States:**
| State | Meaning |
|-------|---------|
| `disabled` | Charge limiting turned off |
| `unavailable` | Helper not installed or not plugged in |
| `idle` | Monitoring, no action needed |
| `chargingToLimit` | Charging normally toward the target limit |
| `limitReached` | At or above target, charging inhibited |
| `heatProtectionPaused` | Temperature above warm threshold, reduced charging |
| `heatProtectionStopped` | Temperature above hot threshold, charging stopped |
| `sailing` | Oscillating between limit ± sailing range |
| `scheduledTopOff` | Charging to 100% before a scheduled time |

**Commands:**
| Command | Effect |
|---------|--------|
| `normal` | Allow charging |
| `inhibit` | Stop charging (write SMC) |
| `pause` | Reduce charging rate |

**Evaluation cycle:**
1. Called whenever `BatteryMonitor.batteryState` changes
2. Checks heat protection thresholds first (safety)
3. Checks scheduled top-off windows
4. Evaluates charge % against target limit ± sailing range
5. Sends enable/disable command via `PrivilegedHelperManager`

### 3. Monitoring Layer — BatteryMonitor

Reads battery telemetry every 30 seconds from two IOKit sources:

**IOPSCopyPowerSourcesInfo (Power Sources API):**
- Current charge percentage
- Charging / discharging status
- Time remaining (to full or empty)
- Power source type (AC/battery)

**IORegistry — AppleSmartBattery service:**
- Cycle count
- Design capacity / max capacity (health calculation)
- Temperature (centidegrees → °C)
- Battery condition (Normal, Check Battery, etc.)
- Adapter wattage
- Model-specific max cycle lookup table

### 4. Settings Layer — AppSettings

Persists user preferences to `UserDefaults` via `@AppStorage`:

| Setting | Default | Notes |
|---------|---------|-------|
| `isChargeLimitingEnabled` | `false` | Pro-gated |
| `targetChargeLimit` | 80% | Clamped to min/max bounds |
| `isSailingModeEnabled` | `true` | Oscillate around target |
| `sailingRange` | 5% | ± range for sailing |
| `isHeatProtectionEnabled` | `false` | Pro-gated |
| `warmTemperatureThreshold` | 35°C | Reduces charge rate |
| `hotTemperatureThreshold` | 40°C | Stops charging |
| `fanControlMode` | `.auto` | Auto / Performance / Quiet |
| `showPercentInMenuBar` | `true` | Show % beside icon |
| `notifyAtChargeLimit` | `true` | Alert at target % |
| `notifyOnHealthDrop` | `true` | Alert on health decline |
| `notifyOnTemperatureAlert` | `true` | Alert on high temp |

### 5. Privileged Layer — PrivilegedHelperManager

Manages the XPC connection to the root-privileged helper daemon. See [Privileged Helper](privileged-helper.md) for full details.

### 6. SMC Layer — SMCKit

Low-level IOKit interface to Apple's System Management Controller. See [SMC Reference](smc-reference.md) for full details.

## Data Flow

```
User adjusts charge limit slider in SettingsView
  → AppSettings.targetChargeLimit updated (persisted)
  → ChargeController.evaluate() triggered
  → Reads BatteryMonitor.batteryState.currentCharge
  → Determines command (e.g., inhibit if charge >= limit)
  → Calls PrivilegedHelperManager.disableCharging()
  → XPC call to ChargeCapHelper
  → HelperTool.setChargingEnabled(false)
  → SMCKit.writeData(CHTE key, 0x01) on Apple Silicon
  → IOConnectCallStructMethod to SMC driver
  → Hardware stops charging
```

## Monetization

ChargeCap uses a freemium model managed by `ProManager`:

- **Free**: Battery info display, charge alerts, manual monitoring
- **Pro ($4.99)**: Automatic charge limiting, sailing mode, heat protection, scheduling

Pro-gated features show a lock icon and are disabled in the UI until unlocked. StoreKit 2 handles purchases and restoration.

## App Lifecycle

On launch:
1. `ChargeCapApp` creates all service instances
2. `BatteryMonitor` starts 30-second refresh timer
3. `PrivilegedHelperManager` checks helper installation status
4. `ChargeController` begins evaluation cycle
5. `MenuBarExtra` appears in the menu bar

On quit:
1. `AppDelegate.applicationShouldTerminate()` fires
2. Calls `helperManager.resetModifiedKeys()` — restores all SMC registers to original values
3. App exits cleanly, leaving battery in its natural state

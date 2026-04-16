# Troubleshooting

Common issues, error codes, and debugging techniques for ChargeCap.

## Charging Control Errors

### "No supported charging key found (CHTE=false, CHWA=false, CH0B=false)"

**Cause:** SMC key detection failed — none of the known charging control keys were found.

**Possible reasons:**
- The SMC connection failed silently before key probing
- Running on unsupported hardware
- Key detection used wrong method (e.g., reading with wrong data type instead of `getKeyInfo`)

**Fix:** Ensure `SMCKit.keyExists()` uses the `getKeyInfo` selector (9), not `readData` with a guessed type. Reading `CHTE` (a `ui32` key) with `ui8` type returns `keyNotFound` even though the key exists.

### "SMC key not found: 1128804418"

**Cause:** Attempted to write to SMC key `CH0B` (1128804418 = `0x43483042` = "CH0B" as FourCharCode) on Apple Silicon. This key only exists on Intel Macs.

**Fix:** Use `CHTE` on Apple Silicon, `CH0B` on Intel. See [SMC Reference](smc-reference.md).

### "InhibitCharging failed: 0xe00002c2"

**Cause:** `kIOReturnNotPermitted` from `AppleSmartBatteryManager`. This IOKit service requires the `com.apple.smartbattery` entitlement, which is reserved for Apple's own software. Third-party apps cannot obtain this entitlement.

**Fix:** Do not use `AppleSmartBatteryManager`. Use SMC key writes instead (CHTE/CH0B), which work from any root process.

### "SMC driver not found"

**Cause:** Neither `AppleSMCKeysEndpoint` nor `AppleSMC` IOKit services were found.

**Possible reasons:**
- Running in a VM (no real SMC hardware)
- IOKit service not loaded
- Permissions issue

### "Failed to open SMC driver: 0x..."

**Cause:** `IOServiceOpen()` failed. The driver was found but couldn't be opened.

**Common return codes:**
| Code | Meaning |
|------|---------|
| `0xe00002c2` | `kIOReturnNotPrivileged` — not running as root |
| `0xe00002bc` | `kIOReturnNotPermitted` — entitlement missing |
| `0xe00002be` | `kIOReturnBusy` — another process has exclusive access |

### "Not privileged to access SMC"

**Cause:** The helper is not running as root. SMC write operations require root privileges.

**Fix:** Reinstall the helper via Settings → "Reinstall Helper". Verify with:
```bash
ps aux | grep ChargeCapHelper
```
The process should show `root` as the user.

## Helper Installation Errors

### "CFErrorDomainLaunchd error 2"

**Cause:** `SMJobBless` is broken on macOS 26. This error occurs when using the deprecated `SMJobBless` API.

**Fix:** ChargeCap now uses `SMAppService.daemon(plistName:).register()` instead. This is handled automatically — no action needed if running the latest code.

### Helper installs but version mismatch persists

**Cause:** `SMAppService.register()` is a no-op if the daemon is already registered. It does NOT update the binary.

**Fix:** The app must call `unregister()` before `register()` to force a binary update:
```swift
try? service.unregister()
try service.register()
```

Use the "Reinstall Helper" button in Settings (when the helper is already installed, the button shows "Reinstall" and passes `force: true`).

### Helper not appearing in process list

**Verify the plist is in the right location:**
```bash
# Inside the built app bundle:
ls -la "ChargeCap.app/Contents/Library/LaunchDaemons/"
# Should contain: com.chargecap.Helper.plist
```

**Verify the helper binary exists:**
```bash
ls -la "ChargeCap.app/Contents/Library/LaunchServices/"
# Should contain: ChargeCapHelper
```

**Check launchd registration:**
```bash
sudo launchctl list | grep chargecap
```

## Settings Window Issues

### "Please use SettingsLink for opening the Settings scene"

**Cause:** macOS 26 blocks programmatic opening of the `Settings` scene via `NSApp.sendAction(Selector("showSettingsWindow:"))`.

**Fix:** ChargeCap uses a `Window(id: "settings")` scene instead of `Settings`, opened with `openWindow(id: "settings")`. This is already implemented in the current code.

### Settings window doesn't reopen after closing

**Cause:** If using the `Settings` scene (deprecated approach), macOS 26 prevents programmatic reopening.

**Fix:** Ensure the app uses `Window(id: "settings")` scene with a `Button` that calls `openWindow(id: "settings")` in `MenuBarView`.

### Settings window closes after helper installation

**Cause:** The macOS authorization dialog (for helper installation) steals focus. When it dismisses, the `Settings` scene may not return to the foreground.

**Fix:** The `Window` scene approach handles this correctly because it's a standard window, not a settings-specific scene.

## XPC Communication Issues

### "SWIFT TASK CONTINUATION MISUSE: getVersion() tried to resume its continuation more than once"

**Cause:** When using a task-group timeout pattern, both the timeout and the XPC reply try to resume the same continuation. This is undefined behavior in Swift concurrency.

**Fix:** Use `SafeContinuation` wrapper (see [Privileged Helper](privileged-helper.md#safecontinuation-pattern)). This wraps `CheckedContinuation` with `NSLock` to guarantee exactly-one resume.

### XPC connection drops silently

**Cause:** The helper process crashed or was unloaded by launchd.

**Diagnosis:**
```bash
# Check if helper is running
ps aux | grep ChargeCapHelper

# Check system log for crashes
log show --predicate 'process == "ChargeCapHelper"' --last 5m
```

**Fix:** Reinstall the helper. The `NSXPCConnection` invalidation handler will detect the drop and update `isInstalled` state.

## SMC Race Condition (Historical)

### Symptom

Intermittent "driver not found" or "failed to open" errors despite the SMC driver being available.

### Root Cause

The original code did `open()` + `defer { close() }` in every XPC method. With concurrent XPC calls from the app, one thread's `close()` would invalidate the connection while another thread was using it.

### Fix

Keep the SMC connection open permanently (opened once on first use, never closed). Use `NSLock` to serialize access:

```swift
static func open() throws {
    lock.lock()
    defer { lock.unlock() }
    if connection != 0 { return }  // Already open — reuse
    // ... open driver once
}
```

## Debugging Techniques

### File-Based Logging (Helper)

The helper runs as a separate root process, so its output doesn't appear in Xcode's console. For debugging:

```swift
func log(_ message: String) {
    let entry = "\(Date()): \(message)\n"
    if let data = entry.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: "/tmp/chargecap-helper.log") {
            if let handle = FileHandle(forWritingAtPath: "/tmp/chargecap-helper.log") {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: "/tmp/chargecap-helper.log",
                                           contents: data)
        }
    }
}
```

Then `tail -f /tmp/chargecap-helper.log` in Terminal.

> **Note:** Remove file logging before shipping — it's for development only.

### Reading SMC Keys Manually

To check what SMC keys exist on a Mac, you can use the open-source `smc` tool:

```bash
# Install via brew or build from source
# Read a key:
sudo smc -k CHTE -r

# If "no data" → key doesn't exist on this hardware
# If hex output → key exists
```

### Checking Helper Status

```bash
# Is the helper running?
ps aux | grep ChargeCapHelper

# What's launchd's view?
sudo launchctl list | grep chargecap

# System log for helper
log show --predicate 'process == "ChargeCapHelper"' --last 10m

# Unregister manually (nuclear option)
sudo launchctl bootout system/com.chargecap.Helper
```

## Known Limitations

| Limitation | Details |
|------------|---------|
| Apple Silicon charge limits | CHWA only supports 80% or 100%. Arbitrary limits (e.g., 70%) require software-managed enable/disable cycling |
| No true pause on Apple Silicon | `CHTE` fully stops/starts charging. There's no "reduce rate" like Intel's `CH0C` |
| VM not supported | No SMC hardware in virtual machines |
| Requires root | SMC writes require the helper to run as root via launchd |
| macOS 26+ only | Uses SwiftUI features and `SMAppService` APIs from macOS 13+, targeting macOS 26 |

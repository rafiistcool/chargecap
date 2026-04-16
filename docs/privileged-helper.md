# Privileged Helper

ChargeCap requires root privileges to write SMC registers that control battery charging. This is accomplished through a privileged helper daemon (`ChargeCapHelper`) that runs as root and communicates with the main app via XPC (cross-process communication).

## Architecture

```
ChargeCap.app (user context)
  │
  │ NSXPCConnection (Mach IPC)
  │ Service: "com.chargecap.Helper.mach"
  │
  ▼
ChargeCapHelper (root context)
  │
  │ IOConnectCallStructMethod
  │
  ▼
SMC Hardware
```

## Installation with SMAppService

### Why Not SMJobBless?

`SMJobBless` was the traditional API for installing privileged helpers. It was deprecated in macOS 13 and is **completely broken on macOS 26** — it returns `CFErrorDomainLaunchd error 2` regardless of configuration. ChargeCap uses `SMAppService.daemon()` instead.

### How SMAppService.daemon Works

```swift
let service = SMAppService.daemon(plistName: "com.chargecap.Helper.plist")
try service.register()
```

This tells the system to:
1. Find the plist at `Contents/Library/LaunchDaemons/com.chargecap.Helper.plist` inside the app bundle
2. Read the `BundleProgram` key to locate the helper binary
3. Copy/register the daemon with `launchd`
4. Start the helper process as root

### Plist Configuration

**`Helper-Launchd.plist`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.chargecap.Helper</string>
    <key>BundleProgram</key>
    <string>Contents/Library/LaunchServices/ChargeCapHelper</string>
    <key>MachServices</key>
    <dict>
        <key>com.chargecap.Helper.mach</key>
        <true/>
    </dict>
</dict>
</plist>
```

Key fields:
- **Label**: Unique daemon identifier, must match the helper's bundle identifier
- **BundleProgram**: Path to the helper binary *relative to the app bundle*. The binary lives in `Contents/Library/LaunchServices/` (placed there by a CopyFiles build phase)
- **MachServices**: Registers a Mach service name for XPC communication

### Reinstalling the Helper

`SMAppService.register()` is a no-op if the daemon is already registered — it does NOT update the binary. To force an update (e.g., after a version bump):

```swift
func registerDaemon() throws {
    let service = SMAppService.daemon(plistName: "com.chargecap.Helper.plist")
    try? service.unregister()  // Remove old registration
    try service.register()     // Register with new binary
}
```

The app exposes this through an "Install Helper" / "Reinstall Helper" button in Settings. The `installIfNeeded(force:)` method accepts a `force` parameter that skips version checking.

## XPC Protocol

### Shared Protocol Definition

```swift
@objc protocol ChargeCapHelperProtocol {
    func getVersion(withReply reply: @escaping (String) -> Void)
    func setChargingEnabled(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void)
    func writeSMCByte(key: String, value: UInt8, withReply reply: @escaping (Bool, String?) -> Void)
    func readSMCByte(key: String, withReply reply: @escaping (UInt8, String?) -> Void)
    func readSMCUInt32(key: String, withReply reply: @escaping (UInt32, String?) -> Void)
    func resetModifiedKeys(withReply reply: @escaping () -> Void)
}
```

This protocol is in `Shared/ChargeCapHelperProtocol.swift` and compiled into both the app and helper targets.

### Connection Setup

```swift
let connection = NSXPCConnection(machServiceName: "com.chargecap.Helper.mach",
                                  options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: ChargeCapHelperProtocol.self)
connection.resume()
```

The `.privileged` option tells XPC that the remote service runs as root.

### Version Checking

The app and helper share a version constant (`ChargeCapHelperConfiguration.version`). On connection, the app calls `getVersion()` and compares. If mismatched, it prompts for reinstallation.

## SafeContinuation Pattern

XPC uses callback-based APIs (`withReply:`), but ChargeCap's async Swift code needs `async/await`. The naive approach uses `withCheckedContinuation`, but this creates a critical bug:

### The Problem

```swift
// DANGEROUS — continuation can leak
try await withThrowingTaskGroup(of: String.self) { group in
    group.addTask {
        return await withCheckedContinuation { cont in
            helper.getVersion { version in cont.resume(returning: version) }
        }
    }
    group.addTask {
        try await Task.sleep(for: .seconds(5))
        throw TimeoutError()
    }
    // When timeout wins, the XPC continuation is never resumed
    // → SWIFT TASK CONTINUATION MISUSE crash
}
```

When the timeout wins the race, the XPC reply arrives later and tries to resume an already-cancelled continuation.

### The Solution — SafeContinuation

```swift
final class SafeContinuation<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, any Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: value)
    }

    func resume(throwing error: any Error) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}
```

This guarantees exactly-one resume. The timeout and the XPC reply can both call `resume()` safely — whichever arrives second is silently dropped.

### Usage Pattern

```swift
func setChargingEnabled(_ enabled: Bool) async throws {
    let helper = try getHelper()
    return try await withCheckedThrowingContinuation { rawCont in
        let safe = SafeContinuation<Bool>(rawCont)

        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            safe.resume(throwing: HelperError.connectionFailed)
        }

        helper.setChargingEnabled(enabled) { success, error in
            if success {
                safe.resume(returning: true)
            } else {
                safe.resume(throwing: HelperError.chargingControlFailed(
                    error ?? "Unknown error"))
            }
        }
    }
}
```

## Helper Lifecycle

### Startup (`main.swift`)

```swift
let listener = NSXPCListener(machServiceName: "com.chargecap.Helper.mach")
let delegate = HelperDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
```

The helper starts, registers as a Mach service listener, and enters an infinite run loop waiting for XPC connections.

### Connection Handling

Each incoming XPC connection is assigned a `HelperTool` instance as its exported object. The `HelperTool` singleton processes all SMC operations.

### Shutdown

The helper runs indefinitely as a launchd daemon. It is stopped when:
- The user unregisters it via `SMAppService.unregister()`
- The system shuts down
- `launchctl` removes it manually

On app quit, the app calls `resetModifiedKeys()` to restore all SMC registers to their original values before the helper stops responding.

## Error Handling

### HelperError Enum

```swift
enum HelperError: LocalizedError {
    case connectionFailed
    case versionMismatch(installed: String, expected: String)
    case writeFailed(key: String, detail: String)
    case readFailed(key: String, detail: String)
    case chargingControlFailed(String)
}
```

### Common Failure Modes

| Error | Cause | Fix |
|-------|-------|-----|
| `connectionFailed` | Helper not installed or crashed | Install/reinstall helper |
| `versionMismatch` | App updated but helper is old | Reinstall helper |
| `chargingControlFailed` | SMC key not found or write rejected | Check platform compatibility |
| `writeFailed` / `readFailed` | Invalid key or privilege issue | Verify helper runs as root |

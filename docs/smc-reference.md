# SMC Reference

The System Management Controller (SMC) is a microcontroller embedded in every Mac that manages hardware-level functions: fan speeds, temperatures, power, LEDs, and — critically for ChargeCap — battery charging.

## How SMC Communication Works

### IOKit Interface

All SMC communication goes through Apple's IOKit framework:

```
App/Helper → IOConnectCallStructMethod → SMC Driver → SMC Hardware
```

1. **Find the driver**: `IOServiceMatching()` locates the SMC kernel extension
2. **Open a connection**: `IOServiceOpen()` returns an `io_connect_t` handle
3. **Call the driver**: `IOConnectCallStructMethod()` sends/receives 80-byte structs
4. **Selector 2** (`handleYPCEvent`) is the single entry point; the actual operation is encoded in the `data8` field of the struct

### Driver Names by Platform

| Platform | IOKit Service Name |
|----------|-------------------|
| Apple Silicon (M1–M4+) | `AppleSMCKeysEndpoint` |
| Intel | `AppleSMC` |

ChargeCap tries `AppleSMCKeysEndpoint` first, then falls back to `AppleSMC`.

### SMCParamStruct (80 bytes)

The communication protocol uses an 80-byte C struct:

```swift
struct SMCParamStruct {
    var key: UInt32           // FourCharCode (e.g., "CHTE" → 0x43485445)
    var vers: SMCVersion      // Not used for read/write
    var pLimitData: SMCPLimitData
    var keyInfo: SMCKeyInfoData  // dataSize, dataType, dataAttributes
    var padding: UInt16
    var result: UInt8         // 0 = success, 132 = key not found
    var status: UInt8
    var data8: UInt8          // Operation selector (see below)
    var data32: UInt32
    var bytes: SMCBytes       // 32-byte data payload
}
```

### Operation Selectors (`data8` field)

| Value | Name | Purpose |
|-------|------|---------|
| 2 | `handleYPCEvent` | IOKit method selector (always used) |
| 5 | `readKey` | Read an SMC register |
| 6 | `writeKey` | Write an SMC register |
| 9 | `getKeyInfo` | Query key metadata (type, size, existence) |

### FourCharCode

SMC keys are 4-character ASCII strings packed into a `UInt32`:

```swift
"CHTE" → 'C'=0x43, 'H'=0x48, 'T'=0x54, 'E'=0x45 → 0x43485445
```

## Charging Control Keys

### Apple Silicon — CHTE (Tahoe)

The primary charging control key on Apple Silicon Macs (M1, M2, M3, M4+).

| Property | Value |
|----------|-------|
| Key | `CHTE` |
| Data Type | `ui32` (UInt32, 4 bytes) |
| Enable charging | Write `0x00000000` |
| Disable charging | Write `0x01000000` |

"Tahoe" is Apple's internal codename for the newer SMC key set used on Apple Silicon.

### Apple Silicon — CHWA (Alternative)

Used by the [bclm](https://github.com/zackelia/bclm) project. Controls Apple's built-in charge limit feature.

| Property | Value |
|----------|-------|
| Key | `CHWA` |
| Data Type | `ui8` (UInt8, 1 byte) |
| Allow 100% charge | Write `0x00` |
| Limit to 80% charge | Write `0x01` |

> **Note:** CHWA is a binary toggle (80% or 100% only). It cannot set arbitrary charge limits. CHTE provides more direct enable/disable control.

### Intel — CH0B + CH0C (Legacy)

Used on Intel Macs for direct charging control.

| Property | Value |
|----------|-------|
| Keys | `CH0B`, `CH0C` |
| Data Type | `ui8` (UInt8, 1 byte) |
| Enable charging | Write `0x00` to both |
| Disable charging | Write `0x02` to both |

### Intel — BCLM (Battery Charge Level Max)

Sets maximum charge percentage on Intel Macs. Not available on Apple Silicon.

| Property | Value |
|----------|-------|
| Key | `BCLM` |
| Data Type | `ui8` (UInt8, 1 byte) |
| Value | Percentage (0–100) |

### Force Discharge Keys

These keys force the Mac to run on battery even when plugged in:

| Key | Platform | Enable | Disable |
|-----|----------|--------|---------|
| `CH0I` | Intel / some AS | `0x01` | `0x00` |
| `CHIE` | Apple Silicon | `0x08` | `0x00` |
| `CH0J` | Some models | `0x01` | `0x00` |

### Other Useful Keys

| Key | Type | Purpose |
|-----|------|---------|
| `ACLC` | `ui8` | LED control (charging indicator light) |
| `B0RM` | `ui16` | Battery remaining capacity (mAh) |
| `B0FC` | `ui16` | Battery full charge capacity (mAh) |
| `TB0T` | `sp78` | Battery temperature (fixed-point) |

## Key Detection

Not all keys exist on all hardware. ChargeCap detects available keys using the `getKeyInfo` SMC command (selector 9):

```swift
// Query whether a key exists without needing to know its type
static func keyExists(_ code: String) -> Bool {
    var input = SMCParamStruct()
    input.key = FourCharCode(fromString: code)
    input.data8 = SMCParamStruct.Selector.getKeyInfo.rawValue
    return (try? callDriver(&input)) != nil
}
```

**Important:** Do NOT detect keys by attempting a read with a guessed type. If you read `CHTE` (a `ui32` key) with `ui8` type (size 1), the SMC returns `keyNotFound` even though the key exists. Always use `getKeyInfo` for detection.

ChargeCap's detection priority:
1. `CHTE` → Apple Silicon primary (UInt32)
2. `CHWA` → Apple Silicon fallback (UInt8)
3. `CH0B` → Intel fallback (UInt8)

## Connection Management

### Thread Safety

SMC operations are not thread-safe. ChargeCap uses `NSLock` to serialize all driver calls:

```swift
private static var connection: io_connect_t = 0
private static let lock = NSLock()

static func open() throws {
    lock.lock()
    defer { lock.unlock() }
    if connection != 0 { return }  // Already open
    // ... open driver
}
```

### Persistent Connection

The SMC connection is opened once and kept alive for the lifetime of the helper process. This avoids a race condition where concurrent XPC calls would each do `open()` + `defer { close() }`, and one thread's `close()` would invalidate another thread's connection mid-operation.

### Key Restoration

`HelperTool` maintains a `modifiedKeys` dictionary that records the original value of any key before it's written. On app quit, `resetModifiedKeys()` restores all keys to their original state, leaving the battery in its natural charging mode.

## Platform Comparison

| Feature | Apple Silicon | Intel |
|---------|--------------|-------|
| SMC driver | `AppleSMCKeysEndpoint` | `AppleSMC` |
| Disable charging | `CHTE = 0x01000000` | `CH0B = 0x02` |
| Enable charging | `CHTE = 0x00000000` | `CH0B = 0x00` |
| Charge limit key | `CHWA` (80% only) | `BCLM` (0-100%) |
| Arbitrary limits | Not via SMC (software-managed) | `BCLM` register |
| Force discharge | `CHIE = 0x08` | `CH0I = 0x01` |

## References

- [actuallymentor/battery](https://github.com/actuallymentor/battery) — Shell-based battery management, CHTE key discovery, comprehensive key probing
- [zackelia/bclm](https://github.com/zackelia/bclm) — Swift SMC tool, CHWA key for Apple Silicon
- Apple IOKit framework headers — IOConnectCallStructMethod, IOServiceMatching

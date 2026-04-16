import Foundation

final class HelperTool: NSObject, ChargeCapHelperProtocol {
    static let shared = HelperTool()

    private enum ModifiedValue {
        case uint8(UInt8)
        case uint32(UInt32)
    }

    private var modifiedKeys: [String: ModifiedValue] = [:]

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(ChargeCapHelperConfiguration.version)
    }

    func setChargingEnabled(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            try SMCKit.open()

            let hasCHTE = smcKeyExists("CHTE")
            let hasCH0B = smcKeyExists("CH0B")
            let hasCHWA = smcKeyExists("CHWA")

            if hasCHTE {
                // Apple Silicon ("Tahoe"): CHTE is UInt32
                // CHTE inhibits charging with UInt32 value 0x01000000
                // (big-endian payload bytes 0x01,0x00,0x00,0x00).
                let value: UInt32 = enabled ? 0x00000000 : 0x01000000
                try writeSMCUInt32WithTracking(key: "CHTE", value: value)
            } else if hasCHWA {
                // CHWA is Apple's 80% optimization toggle (1=optimize, 0=allow full charging).
                // It does not provide an immediate "disable charging now" capability.
                guard enabled else {
                    reply(false, "This hardware supports only Apple's optimized charging behavior, not immediate charge inhibit")
                    return
                }
                try writeSMCByteWithTracking(key: "CHWA", value: 0x00)
            } else if hasCH0B {
                // Intel: CH0B + CH0C are UInt8
                let val: UInt8 = enabled ? 0x00 : 0x02
                try writeSMCByteWithTracking(key: "CH0B", value: val)
                try? writeSMCByteWithTracking(key: "CH0C", value: val)
            } else {
                reply(false, "No supported charging key found (CHTE=\(hasCHTE), CHWA=\(hasCHWA), CH0B=\(hasCH0B))")
                return
            }
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func writeSMCByte(key: String, value: UInt8, withReply reply: @escaping (Bool, String?) -> Void) {
        guard key.utf8.count == 4 else {
            reply(false, "Invalid SMC key '\(key)': must be exactly 4 characters")
            return
        }

        do {
            try SMCKit.open()

            let smcKey = SMCKit.getKey(key, type: DataTypes.UInt8)
            let bytes: SMCBytes = (
                value, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0
            )

            if modifiedKeys[key] == nil {
                let currentValue = try SMCKit.readData(smcKey).0
                modifiedKeys[key] = .uint8(currentValue)
            }

            try SMCKit.writeData(smcKey, data: bytes)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func readSMCByte(key: String, withReply reply: @escaping (UInt8, String?) -> Void) {
        guard key.utf8.count == 4 else {
            reply(0, "Invalid SMC key '\(key)': must be exactly 4 characters")
            return
        }

        do {
            let value = try readSMCByteSync(key: key)
            reply(value, nil)
        } catch {
            reply(0, error.localizedDescription)
        }
    }

    func readSMCUInt32(key: String, withReply reply: @escaping (UInt32, String?) -> Void) {
        guard key.utf8.count == 4 else {
            reply(0, "Invalid SMC key '\(key)': must be exactly 4 characters")
            return
        }

        do {
            try SMCKit.open()

            let smcKey = SMCKit.getKey(key, type: DataTypes.UInt32)
            let data = try SMCKit.readData(smcKey)
            let value =
                (UInt32(data.0) << 24) |
                (UInt32(data.1) << 16) |
                (UInt32(data.2) << 8) |
                UInt32(data.3)
            reply(value, nil)
        } catch {
            reply(0, error.localizedDescription)
        }
    }

    func readSMCTemperature(key: String, withReply reply: @escaping (Double, String?) -> Void) {
        guard key.utf8.count == 4 else {
            reply(0, "Invalid SMC key '\(key)': must be exactly 4 characters")
            return
        }

        do {
            try SMCKit.open()

            // Temperature keys use sp78: signed 7.8 fixed-point, 2 bytes
            let smcKey = SMCKit.getKey(key, type: DataTypes.SP78)
            let data = try SMCKit.readData(smcKey)
            let celsius = Double(fromSP78: (data.0, data.1))
            reply(celsius, nil)
        } catch {
            reply(0, error.localizedDescription)
        }
    }

    func readSMCFloat(key: String, withReply reply: @escaping (Float, String?) -> Void) {
        guard key.utf8.count == 4 else {
            reply(0, "Invalid SMC key '\(key)': must be exactly 4 characters")
            return
        }

        do {
            try SMCKit.open()

            // Try flt first (Apple Silicon), fall back to fpe2 (Intel)
            let smcKey = SMCKit.getKey(key, type: DataTypes.FLT)
            let data = try SMCKit.readData(smcKey)
            let value = Float(fromSMCBytes: (data.0, data.1, data.2, data.3))
            reply(value, nil)
        } catch {
            // Fallback: try fpe2 encoding (unsigned 14.2 fixed-point)
            do {
                try SMCKit.open()
                let smcKey = SMCKit.getKey(key, type: DataTypes.FPE2)
                let data = try SMCKit.readData(smcKey)
                let raw = (UInt16(data.0) << 8) | UInt16(data.1)
                let value = Float(raw) / 4.0
                reply(value, nil)
            } catch {
                reply(0, error.localizedDescription)
            }
        }
    }

    func resetModifiedKeys(withReply reply: @escaping () -> Void) {
        for (key, value) in modifiedKeys {
            switch value {
            case .uint8(let byte):
                _ = try? writeSMCByteSync(key: key, value: byte)
            case .uint32(let uint32):
                _ = try? writeSMCUInt32Sync(key: key, value: uint32)
            }
        }

        modifiedKeys.removeAll()
        reply()
    }

    private func readSMCByteSync(key: String) throws -> UInt8 {
        guard key.utf8.count == 4 else {
            throw SMCKit.SMCError.keyNotFound(key)
        }

        try SMCKit.open()

        let smcKey = SMCKit.getKey(key, type: DataTypes.UInt8)
        return try SMCKit.readData(smcKey).0
    }

    private func writeSMCByteSync(key: String, value: UInt8) throws {
        guard key.utf8.count == 4 else {
            throw SMCKit.SMCError.keyNotFound(key)
        }

        try SMCKit.open()

        let smcKey = SMCKit.getKey(key, type: DataTypes.UInt8)
        let bytes: SMCBytes = (
            value, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
        try SMCKit.writeData(smcKey, data: bytes)
    }

    private func readSMCUInt32Sync(key: String) throws -> UInt32 {
        guard key.utf8.count == 4 else {
            throw SMCKit.SMCError.keyNotFound(key)
        }

        try SMCKit.open()

        let smcKey = SMCKit.getKey(key, type: DataTypes.UInt32)
        let data = try SMCKit.readData(smcKey)
        return
            (UInt32(data.0) << 24) |
            (UInt32(data.1) << 16) |
            (UInt32(data.2) << 8) |
            UInt32(data.3)
    }

    private func writeSMCUInt32Sync(key: String, value: UInt32) throws {
        guard key.utf8.count == 4 else {
            throw SMCKit.SMCError.keyNotFound(key)
        }

        try SMCKit.open()

        let smcKey = SMCKit.getKey(key, type: DataTypes.UInt32)
        try SMCKit.writeData(smcKey, data: smcBytes(from: value))
    }

    private func writeSMCByteWithTracking(key: String, value: UInt8) throws {
        if modifiedKeys[key] == nil {
            modifiedKeys[key] = .uint8(try readSMCByteSync(key: key))
        }
        try writeSMCByteSync(key: key, value: value)
    }

    private func writeSMCUInt32WithTracking(key: String, value: UInt32) throws {
        if modifiedKeys[key] == nil {
            modifiedKeys[key] = .uint32(try readSMCUInt32Sync(key: key))
        }
        try writeSMCUInt32Sync(key: key, value: value)
    }

    private func smcBytes(from value: UInt32) -> SMCBytes {
        // SMCKit UInt32 values are written in big-endian byte order.
        let byte0 = UInt8((value >> 24) & 0xFF)
        let byte1 = UInt8((value >> 16) & 0xFF)
        let byte2 = UInt8((value >> 8) & 0xFF)
        let byte3 = UInt8(value & 0xFF)
        return (
            byte0, byte1, byte2, byte3, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private func smcKeyExists(_ keyName: String) -> Bool {
        return SMCKit.keyExists(keyName)
    }
}

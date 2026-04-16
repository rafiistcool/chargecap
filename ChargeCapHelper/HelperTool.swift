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
                try captureOriginalUInt32Value(for: "CHTE")
                let key = SMCKit.getKey("CHTE", type: DataTypes.UInt32)
                let value: UInt32 = enabled ? 0x00000000 : 0x01000000
                try SMCKit.writeData(key, data: smcBytes(from: value))
            } else if hasCHWA {
                // Apple Silicon alt (bclm approach): CHWA is UInt8, 1=limit to 80%, 0=allow 100%
                guard enabled else {
                    reply(false, "CHWA only supports Apple's 80% charge limit and cannot disable charging")
                    return
                }
                try captureOriginalByteValue(for: "CHWA")
                let key = SMCKit.getKey("CHWA", type: DataTypes.UInt8)
                let val: UInt8 = 0x00
                let bytes: SMCBytes = (
                    val, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0
                )
                try SMCKit.writeData(key, data: bytes)
            } else if hasCH0B {
                // Intel: CH0B + CH0C are UInt8
                try captureOriginalByteValue(for: "CH0B")
                try captureOriginalByteValue(for: "CH0C")
                let val: UInt8 = enabled ? 0x00 : 0x02
                let keyB = SMCKit.getKey("CH0B", type: DataTypes.UInt8)
                let bytes: SMCBytes = (
                    val, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0
                )
                try SMCKit.writeData(keyB, data: bytes)
                let keyC = SMCKit.getKey("CH0C", type: DataTypes.UInt8)
                try? SMCKit.writeData(keyC, data: bytes)
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
            reply(UInt32(fromBytes: (data.0, data.1, data.2, data.3)), nil)
        } catch {
            reply(0, error.localizedDescription)
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
        return UInt32(fromBytes: (data.0, data.1, data.2, data.3))
    }

    private func writeSMCUInt32Sync(key: String, value: UInt32) throws {
        guard key.utf8.count == 4 else {
            throw SMCKit.SMCError.keyNotFound(key)
        }

        try SMCKit.open()

        let smcKey = SMCKit.getKey(key, type: DataTypes.UInt32)
        try SMCKit.writeData(smcKey, data: smcBytes(from: value))
    }

    private func captureOriginalByteValue(for key: String) throws {
        guard modifiedKeys[key] == nil else { return }
        let currentValue = try readSMCByteSync(key: key)
        modifiedKeys[key] = .uint8(currentValue)
    }

    private func captureOriginalUInt32Value(for key: String) throws {
        guard modifiedKeys[key] == nil else { return }
        let currentValue = try readSMCUInt32Sync(key: key)
        modifiedKeys[key] = .uint32(currentValue)
    }

    private func smcBytes(from value: UInt32) -> SMCBytes {
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

import Foundation
import IOKit

final class HelperTool: NSObject, ChargeCapHelperProtocol {
    static let shared = HelperTool()

    private var modifiedKeys: [String: UInt8] = [:]

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(ChargeCapHelperConfiguration.version)
    }

    func setChargingEnabled(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            try SMCKit.open()

            // Apple Silicon ("Tahoe"): use CHTE (UInt32)
            // Intel ("Legacy"): use CH0B + CH0C (UInt8)
            if smcKeyExists("CHTE") {
                let key = SMCKit.getKey("CHTE", type: DataTypes.UInt32)
                let val: UInt8 = enabled ? 0x00 : 0x01
                let bytes: SMCBytes = (
                    val, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0
                )
                try SMCKit.writeData(key, data: bytes)
            } else if smcKeyExists("CH0B") {
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
                reply(false, "No supported charging control key found (tried CHTE, CH0B)")
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
                modifiedKeys[key] = currentValue
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
            _ = try? writeSMCByteSync(key: key, value: value)
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

    private func smcKeyExists(_ keyName: String) -> Bool {
        let key = SMCKit.getKey(keyName, type: DataTypes.UInt8)
        return (try? SMCKit.readData(key)) != nil
    }
}

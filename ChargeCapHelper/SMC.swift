import Foundation
import IOKit

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

extension UInt32 {
    init(fromBytes bytes: (UInt8, UInt8, UInt8, UInt8)) {
        let byte0 = UInt32(bytes.0) << 24
        let byte1 = UInt32(bytes.1) << 16
        let byte2 = UInt32(bytes.2) << 8
        let byte3 = UInt32(bytes.3)
        self = byte0 | byte1 | byte2 | byte3
    }
}

extension Double {
    init(fromSP78 bytes: (UInt8, UInt8)) {
        let sign = bytes.0 & 0x80 == 0 ? 1.0 : -1.0
        self = sign * (Double(bytes.0 & 0x7F) + Double(bytes.1) / 256.0)
    }
}

extension FourCharCode {
    init(fromString str: String) {
        precondition(str.count == 4)
        self = str.utf8.reduce(0) { sum, character in
            sum << 8 | UInt32(character)
        }
    }
}

struct SMCParamStruct {
    enum Selector: UInt8 {
        case handleYPCEvent = 2
        case readKey = 5
        case writeKey = 6
        case getKeyInfo = 9
    }

    enum Result: UInt8 {
        case success = 0
        case keyNotFound = 132
    }

    struct SMCVersion {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

struct DataType: Equatable {
    let type: FourCharCode
    let size: IOByteCount
}

enum DataTypes {
    static let UInt8 = DataType(type: FourCharCode(fromString: "ui8 "), size: 1)
    static let UInt32 = DataType(type: FourCharCode(fromString: "ui32"), size: 4)
}

struct SMCKey {
    let code: FourCharCode
    let info: DataType
}

enum SMCKit {
    enum SMCError: Error {
        case driverNotFound
        case failedToOpen
        case keyNotFound(String)
        case notPrivileged
        case unknown(kern_return_t, UInt8)
    }

    private static var connection: io_connect_t = 0

    static func open() throws {
        if connection != 0 { return }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service == 0 {
            throw SMCError.driverNotFound
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        if result != kIOReturnSuccess {
            throw SMCError.failedToOpen
        }
    }

    @discardableResult
    static func close() -> Bool {
        guard connection != 0 else { return true }
        let result = IOServiceClose(connection)
        connection = 0
        return result == kIOReturnSuccess
    }

    static func getKey(_ code: String, type: DataType) -> SMCKey {
        SMCKey(code: FourCharCode(fromString: code), info: type)
    }

    static func readData(_ key: SMCKey) throws -> SMCBytes {
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = UInt32(key.info.size)
        input.data8 = SMCParamStruct.Selector.readKey.rawValue

        return try callDriver(&input).bytes
    }

    static func writeData(_ key: SMCKey, data: SMCBytes) throws {
        var input = SMCParamStruct()
        input.key = key.code
        input.bytes = data
        input.keyInfo.dataSize = UInt32(key.info.size)
        input.data8 = SMCParamStruct.Selector.writeKey.rawValue

        _ = try callDriver(&input)
    }

    private static func callDriver(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        precondition(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct must be 80 bytes")

        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCParamStruct.Selector.handleYPCEvent.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )

        switch (result, output.result) {
        case (kIOReturnSuccess, SMCParamStruct.Result.success.rawValue):
            return output
        case (kIOReturnSuccess, SMCParamStruct.Result.keyNotFound.rawValue):
            throw SMCError.keyNotFound(String(describing: input.key))
        case (kIOReturnNotPrivileged, _):
            throw SMCError.notPrivileged
        default:
            throw SMCError.unknown(result, output.result)
        }
    }
}

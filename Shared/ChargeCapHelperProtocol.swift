import Foundation

enum ChargeCapHelperConfiguration {
    static let version = "2"
    static let helperIdentifier = "com.chargecap.Helper"
    static let machServiceName = "com.chargecap.Helper.mach"
}

@objc(ChargeCapHelperProtocol)
protocol ChargeCapHelperProtocol {
    func getVersion(withReply reply: @escaping (String) -> Void)
    func setChargingEnabled(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void)
    func writeSMCByte(key: String, value: UInt8, withReply reply: @escaping (Bool, String?) -> Void)
    func readSMCByte(key: String, withReply reply: @escaping (UInt8, String?) -> Void)
    func readSMCUInt32(key: String, withReply reply: @escaping (UInt32, String?) -> Void)
    func resetModifiedKeys(withReply reply: @escaping () -> Void)
}

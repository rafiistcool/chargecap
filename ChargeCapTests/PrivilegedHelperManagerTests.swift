import XCTest
@testable import ChargeCap

// MARK: - Mock Helper for XPC tests

final class MockChargeCapHelper: NSObject, ChargeCapHelperProtocol {

    var versionToReturn: String = ChargeCapHelperConfiguration.version
    var chargingEnabledResult: (Bool, String?) = (true, nil)
    var writeSMCByteResult: (Bool, String?) = (true, nil)
    var readSMCByteResult: (UInt8, String?) = (0, nil)
    var readSMCUInt32Result: (UInt32, String?) = (0, nil)
    var readSMCTemperatureResult: (Double, String?) = (0.0, nil)
    var readSMCFloatResult: (Float, String?) = (0.0, nil)
    var resetModifiedKeysCalled = false

    // Track calls
    var setChargingEnabledCalls: [Bool] = []
    var writeSMCByteCalls: [(key: String, value: UInt8)] = []
    var readSMCByteCalls: [String] = []
    var readSMCFloatCalls: [String] = []
    var readSMCUInt32Calls: [String] = []
    var readSMCTemperatureCalls: [String] = []

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(versionToReturn)
    }

    func setChargingEnabled(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        setChargingEnabledCalls.append(enabled)
        reply(chargingEnabledResult.0, chargingEnabledResult.1)
    }

    func writeSMCByte(key: String, value: UInt8, withReply reply: @escaping (Bool, String?) -> Void) {
        writeSMCByteCalls.append((key: key, value: value))
        reply(writeSMCByteResult.0, writeSMCByteResult.1)
    }

    func readSMCByte(key: String, withReply reply: @escaping (UInt8, String?) -> Void) {
        readSMCByteCalls.append(key)
        reply(readSMCByteResult.0, readSMCByteResult.1)
    }

    func readSMCUInt32(key: String, withReply reply: @escaping (UInt32, String?) -> Void) {
        readSMCUInt32Calls.append(key)
        reply(readSMCUInt32Result.0, readSMCUInt32Result.1)
    }

    func readSMCTemperature(key: String, withReply reply: @escaping (Double, String?) -> Void) {
        readSMCTemperatureCalls.append(key)
        reply(readSMCTemperatureResult.0, readSMCTemperatureResult.1)
    }

    func readSMCFloat(key: String, withReply reply: @escaping (Float, String?) -> Void) {
        readSMCFloatCalls.append(key)
        reply(readSMCFloatResult.0, readSMCFloatResult.1)
    }

    func resetModifiedKeys(withReply reply: @escaping () -> Void) {
        resetModifiedKeysCalled = true
        reply()
    }
}

// MARK: - HelperError Tests

final class HelperErrorTests: XCTestCase {

    func testInstallationFailed_errorDescription() {
        let error = PrivilegedHelperManager.HelperError.installationFailed("disk full")
        XCTAssertEqual(error.errorDescription, "Helper install failed: disk full")
    }

    func testConnectionUnavailable_errorDescription() {
        let error = PrivilegedHelperManager.HelperError.connectionUnavailable
        XCTAssertEqual(error.errorDescription, "Privileged helper unavailable")
    }

    func testVersionMismatch_errorDescription() {
        let error = PrivilegedHelperManager.HelperError.versionMismatch(expected: "5", actual: "3")
        XCTAssertEqual(error.errorDescription, "Helper version mismatch (expected 5, got 3)")
    }

    func testWriteFailed_errorDescription() {
        let error = PrivilegedHelperManager.HelperError.writeFailed(key: "CH0B", description: "permission denied")
        XCTAssertEqual(error.errorDescription, "Failed to write CH0B: permission denied")
    }

    func testReadFailed_errorDescription() {
        let error = PrivilegedHelperManager.HelperError.readFailed(key: "TC0C", description: "not found")
        XCTAssertEqual(error.errorDescription, "Failed to read TC0C: not found")
    }

    func testChargingControlFailed_errorDescription() {
        let error = PrivilegedHelperManager.HelperError.chargingControlFailed(description: "SMC error")
        XCTAssertEqual(error.errorDescription, "Charging control failed: SMC error")
    }
}

// MARK: - SafeContinuation Tests

final class SafeContinuationTests: XCTestCase {

    func testResumeReturning_returnsValue() async throws {
        let value: Int = try await withCheckedThrowingContinuation { raw in
            let safe = PrivilegedHelperManager.SafeContinuation(raw)
            safe.resume(returning: 42)
        }
        XCTAssertEqual(value, 42)
    }

    func testResumeThrowing_throwsError() async {
        do {
            let _: Int = try await withCheckedThrowingContinuation { raw in
                let safe = PrivilegedHelperManager.SafeContinuation(raw)
                safe.resume(throwing: PrivilegedHelperManager.HelperError.connectionUnavailable)
            }
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is PrivilegedHelperManager.HelperError)
        }
    }

    func testDoubleResume_secondIsIgnored() async throws {
        let value: Int = try await withCheckedThrowingContinuation { raw in
            let safe = PrivilegedHelperManager.SafeContinuation(raw)
            safe.resume(returning: 42)
            // Second resume should be safely ignored (no crash)
            safe.resume(returning: 99)
        }
        XCTAssertEqual(value, 42)
    }

    func testDoubleResume_returnThenThrow_throwIsIgnored() async throws {
        let value: Int = try await withCheckedThrowingContinuation { raw in
            let safe = PrivilegedHelperManager.SafeContinuation(raw)
            safe.resume(returning: 42)
            safe.resume(throwing: PrivilegedHelperManager.HelperError.connectionUnavailable)
        }
        XCTAssertEqual(value, 42)
    }

    func testDoubleResume_throwThenReturn_returnIsIgnored() async {
        do {
            let _: Int = try await withCheckedThrowingContinuation { raw in
                let safe = PrivilegedHelperManager.SafeContinuation(raw)
                safe.resume(throwing: PrivilegedHelperManager.HelperError.connectionUnavailable)
                safe.resume(returning: 42)
            }
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is PrivilegedHelperManager.HelperError)
        }
    }
}

// MARK: - PrivilegedHelperManager XPC Method Tests (via mock proxy)

@MainActor
final class PrivilegedHelperManagerXPCTests: XCTestCase {

    private var manager: PrivilegedHelperManager!
    private var mockHelper: MockChargeCapHelper!

    override func setUp() {
        super.setUp()
        manager = PrivilegedHelperManager()
        mockHelper = MockChargeCapHelper()
        manager._proxyOverride = mockHelper
    }

    override func tearDown() {
        manager._proxyOverride = nil
        manager = nil
        mockHelper = nil
        super.tearDown()
    }

    // MARK: - readSMCFloatValue

    func testReadSMCFloatValue_success() async throws {
        mockHelper.readSMCFloatResult = (3.14, nil)
        let value = try await manager.readSMCFloatValue(key: "F0Ac")
        XCTAssertEqual(value, 3.14, accuracy: 0.001)
        XCTAssertEqual(mockHelper.readSMCFloatCalls, ["F0Ac"])
    }

    func testReadSMCFloatValue_error() async {
        mockHelper.readSMCFloatResult = (0, "key not found")
        do {
            _ = try await manager.readSMCFloatValue(key: "XXXX")
            XCTFail("Expected error")
        } catch {
            guard case PrivilegedHelperManager.HelperError.readFailed(let key, let desc) = error else {
                XCTFail("Wrong error type: \(error)")
                return
            }
            XCTAssertEqual(key, "XXXX")
            XCTAssertEqual(desc, "key not found")
        }
    }

    // MARK: - readSMCByteValue

    func testReadSMCByteValue_success() async throws {
        mockHelper.readSMCByteResult = (2, nil)
        let value = try await manager.readSMCByteValue(key: "FNum")
        XCTAssertEqual(value, 2)
        XCTAssertEqual(mockHelper.readSMCByteCalls, ["FNum"])
    }

    func testReadSMCByteValue_error() async {
        mockHelper.readSMCByteResult = (0, "read error")
        do {
            _ = try await manager.readSMCByteValue(key: "FNum")
            XCTFail("Expected error")
        } catch {
            guard case PrivilegedHelperManager.HelperError.readFailed(let key, _) = error else {
                XCTFail("Wrong error type")
                return
            }
            XCTAssertEqual(key, "FNum")
        }
    }

    // MARK: - readSMCTemperatureValue

    func testReadSMCTemperatureValue_success() async throws {
        mockHelper.readSMCTemperatureResult = (55.5, nil)
        let value = try await manager.readSMCTemperatureValue(key: "TC0C")
        XCTAssertEqual(value, 55.5, accuracy: 0.01)
        XCTAssertEqual(mockHelper.readSMCTemperatureCalls, ["TC0C"])
    }

    func testReadSMCTemperatureValue_error() async {
        mockHelper.readSMCTemperatureResult = (0, "sensor offline")
        do {
            _ = try await manager.readSMCTemperatureValue(key: "TC0C")
            XCTFail("Expected error")
        } catch {
            guard case PrivilegedHelperManager.HelperError.readFailed(let key, _) = error else {
                XCTFail("Wrong error type")
                return
            }
            XCTAssertEqual(key, "TC0C")
        }
    }

    // MARK: - enableCharging / disableCharging / pauseCharging

    func testEnableCharging_success() async throws {
        mockHelper.chargingEnabledResult = (true, nil)
        try await manager.enableCharging()
        XCTAssertEqual(mockHelper.setChargingEnabledCalls, [true])
    }

    func testDisableCharging_success() async throws {
        mockHelper.chargingEnabledResult = (true, nil)
        try await manager.disableCharging()
        XCTAssertEqual(mockHelper.setChargingEnabledCalls, [false])
    }

    func testPauseCharging_callsDisableCharging() async throws {
        mockHelper.chargingEnabledResult = (true, nil)
        try await manager.pauseCharging()
        XCTAssertEqual(mockHelper.setChargingEnabledCalls, [false])
    }

    func testEnableCharging_failure_throwsError() async {
        mockHelper.chargingEnabledResult = (false, "SMC write failed")
        do {
            try await manager.enableCharging()
            XCTFail("Expected error")
        } catch {
            guard case PrivilegedHelperManager.HelperError.chargingControlFailed(let desc) = error else {
                XCTFail("Wrong error type: \(error)")
                return
            }
            XCTAssertEqual(desc, "SMC write failed")
        }
    }

    func testDisableCharging_failure_throwsError() async {
        mockHelper.chargingEnabledResult = (false, nil)
        do {
            try await manager.disableCharging()
            XCTFail("Expected error")
        } catch {
            guard case PrivilegedHelperManager.HelperError.chargingControlFailed(let desc) = error else {
                XCTFail("Wrong error type: \(error)")
                return
            }
            XCTAssertEqual(desc, "Unknown error")
        }
    }

    // MARK: - batteryRate

    func testBatteryRate_success() async throws {
        mockHelper.readSMCUInt32Result = (1234, nil)
        let rate = try await manager.batteryRate()
        XCTAssertEqual(rate, 1234)
        XCTAssertEqual(mockHelper.readSMCUInt32Calls, ["BRSC"])
    }

    func testBatteryRate_error() async {
        mockHelper.readSMCUInt32Result = (0, "key missing")
        do {
            _ = try await manager.batteryRate()
            XCTFail("Expected error")
        } catch {
            guard case PrivilegedHelperManager.HelperError.readFailed(let key, _) = error else {
                XCTFail("Wrong error type")
                return
            }
            XCTAssertEqual(key, "BRSC")
        }
    }

    // MARK: - batteryTemperatureFromSMC

    func testBatteryTemperatureFromSMC_success() async throws {
        mockHelper.readSMCTemperatureResult = (35.5, nil)
        let temp = try await manager.batteryTemperatureFromSMC()
        XCTAssertEqual(temp, 35.5, accuracy: 0.01)
        XCTAssertEqual(mockHelper.readSMCTemperatureCalls, ["TB0T"])
    }

    // MARK: - refreshStatus

    func testRefreshStatus_success_setsInstalled() async {
        mockHelper.versionToReturn = ChargeCapHelperConfiguration.version
        await manager.refreshStatus()
        XCTAssertTrue(manager.isInstalled)
        XCTAssertNil(manager.lastErrorDescription)
    }

    func testRefreshStatus_versionMismatch_setsNotInstalled() async {
        mockHelper.versionToReturn = "0"
        await manager.refreshStatus()
        XCTAssertFalse(manager.isInstalled)
        XCTAssertNotNil(manager.lastErrorDescription)
    }

    // MARK: - resetModifiedKeys

    func testResetModifiedKeys_callsHelper() async {
        await manager.resetModifiedKeys()
        XCTAssertTrue(mockHelper.resetModifiedKeysCalled)
    }
}

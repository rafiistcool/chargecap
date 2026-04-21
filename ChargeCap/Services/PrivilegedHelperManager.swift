import Foundation
import ServiceManagement

@MainActor
final class PrivilegedHelperManager: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var lastErrorDescription: String?

    private var _connection: NSXPCConnection?

    /// Override point for unit tests – set a mock proxy to bypass real XPC.
    var _proxyOverride: ChargeCapHelperProtocol?

    private var connection: NSXPCConnection {
        if let existing = _connection { return existing }

        let conn = NSXPCConnection(
            machServiceName: ChargeCapHelperConfiguration.machServiceName,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: ChargeCapHelperProtocol.self)
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.handleConnectionFailure()
            }
        }
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.handleConnectionFailure()
            }
        }
        conn.resume()
        _connection = conn
        return conn
    }

    func refreshStatus() async {
        do {
            _ = try await getVersion()
            isInstalled = true
            lastErrorDescription = nil
        } catch {
            isInstalled = false
            lastErrorDescription = error.localizedDescription
        }
    }

    func installIfNeeded(force: Bool = false) async throws {
        if !force {
            do {
                _ = try await getVersion()
                isInstalled = true
                lastErrorDescription = nil
                return
            } catch {
                isInstalled = false
            }
        }

        do {
            try registerDaemon()
        } catch {
            lastErrorDescription = error.localizedDescription
            throw error
        }

        // Old connection is stale after registration; force a fresh one.
        invalidateConnection()

        try await Task.sleep(for: .seconds(2))

        do {
            _ = try await getVersion()
            isInstalled = true
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
            throw error
        }
    }

    func enableCharging() async throws {
        try await setChargingEnabled(true)
    }

    func disableCharging() async throws {
        try await setChargingEnabled(false)
    }

    func pauseCharging() async throws {
        try await disableCharging()
    }

    func batteryRate() async throws -> UInt32 {
        try await readSMCUInt32(key: "BRSC")
    }

    func batteryTemperatureFromSMC() async throws -> Double {
        try await readSMCTemperature(key: "TB0T")
    }

    func readSMCFloatValue(key: String) async throws -> Float {
        try await invokeHelper { helper, finish in
            helper.readSMCFloat(key: key) { value, errorDescription in
                if let errorDescription {
                    finish(.failure(HelperError.readFailed(key: key, description: errorDescription)))
                } else {
                    finish(.success(value))
                }
            }
        }
    }

    func readSMCTemperatureValue(key: String) async throws -> Double {
        try await readSMCTemperature(key: key)
    }

    func readSMCByteValue(key: String) async throws -> UInt8 {
        try await invokeHelper { helper, finish in
            helper.readSMCByte(key: key) { value, errorDescription in
                if let errorDescription {
                    finish(.failure(HelperError.readFailed(key: key, description: errorDescription)))
                } else {
                    finish(.success(value))
                }
            }
        }
    }

    func resetModifiedKeys() async {
        do {
            let _: Void = try await invokeHelper(timeout: Self.resetTimeout) { helper, finish in
                helper.resetModifiedKeys {
                    finish(.success(()))
                }
            }
        } catch {
            return
        }
    }

    func invalidateConnection() {
        _connection?.invalidate()
        _connection = nil
    }

    private func registerDaemon() throws {
        let service = SMAppService.daemon(plistName: "com.chargecap.Helper.plist")
        // Unregister first to ensure launchd picks up the new binary.
        try? service.unregister()
        try service.register()
    }

    private static let xpcTimeout: TimeInterval = 5
    private static let resetTimeout: TimeInterval = 2

    /// Wraps a continuation to guarantee exactly one resume, preventing leaks.
    final class SafeContinuation<T: Sendable>: @unchecked Sendable {
        private var continuation: CheckedContinuation<T, Error>?
        private let lock = NSLock()

        init(_ continuation: CheckedContinuation<T, Error>) {
            self.continuation = continuation
        }

        func resume(returning value: T) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }

        func resume(throwing error: Error) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(throwing: error)
        }

        func resume(with result: Result<T, Error>) {
            switch result {
            case .success(let value):
                resume(returning: value)
            case .failure(let error):
                resume(throwing: error)
            }
        }
    }

    private func getVersion() async throws -> String {
        try await invokeHelper { helper, finish in
            helper.getVersion { version in
                if version == ChargeCapHelperConfiguration.version {
                    finish(.success(version))
                } else {
                    finish(.failure(HelperError.versionMismatch(expected: ChargeCapHelperConfiguration.version, actual: version)))
                }
            }
        }
    }

    func writeSMCByte(key: String, value: UInt8) async throws {
        try await invokeHelper { helper, finish in
            helper.writeSMCByte(key: key, value: value) { success, errorDescription in
                if success {
                    finish(.success(()))
                } else {
                    finish(.failure(HelperError.writeFailed(key: key, description: errorDescription ?? "Unknown SMC write error")))
                }
            }
        }
    }

    private func setChargingEnabled(_ enabled: Bool) async throws {
        try await invokeHelper { helper, finish in
            helper.setChargingEnabled(enabled) { success, errorDescription in
                if success {
                    finish(.success(()))
                } else {
                    finish(.failure(HelperError.chargingControlFailed(description: errorDescription ?? "Unknown error")))
                }
            }
        }
    }

    private func readSMCUInt32(key: String) async throws -> UInt32 {
        try await invokeHelper { helper, finish in
            helper.readSMCUInt32(key: key) { value, errorDescription in
                if let errorDescription {
                    finish(.failure(HelperError.readFailed(key: key, description: errorDescription)))
                } else {
                    finish(.success(value))
                }
            }
        }
    }

    private func readSMCTemperature(key: String) async throws -> Double {
        try await invokeHelper { helper, finish in
            helper.readSMCTemperature(key: key) { value, errorDescription in
                if let errorDescription {
                    finish(.failure(HelperError.readFailed(key: key, description: errorDescription)))
                } else {
                    finish(.success(value))
                }
            }
        }
    }

    private func invokeHelper<T: Sendable>(
        timeout: TimeInterval? = nil,
        _ request: @escaping (ChargeCapHelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { raw in
            let continuation = SafeContinuation(raw)
            let timeoutInterval = timeout ?? Self.xpcTimeout

            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.handleConnectionFailure(description: HelperError.connectionUnavailable.errorDescription)
                }
                continuation.resume(throwing: HelperError.connectionUnavailable)
            }

            let finish: (Result<T, Error>) -> Void = { result in
                timeoutWorkItem.cancel()
                continuation.resume(with: result)
            }

            let helper: ChargeCapHelperProtocol
            if let proxyOverride = _proxyOverride {
                helper = proxyOverride
            } else {
                let remoteProxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                    timeoutWorkItem.cancel()
                    Task { @MainActor in
                        self?.handleConnectionFailure(description: error.localizedDescription)
                    }
                    continuation.resume(throwing: HelperError.connectionUnavailable)
                } as? ChargeCapHelperProtocol

                guard let remoteProxy else {
                    timeoutWorkItem.cancel()
                    Task { @MainActor in
                        self.handleConnectionFailure(description: HelperError.connectionUnavailable.errorDescription)
                    }
                    continuation.resume(throwing: HelperError.connectionUnavailable)
                    return
                }

                helper = remoteProxy
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutInterval, execute: timeoutWorkItem)
            request(helper, finish)
        }
    }

    private func handleConnectionFailure(description: String? = nil) {
        let staleConnection = _connection
        _connection = nil
        isInstalled = false
        if let description {
            lastErrorDescription = description
        } else if lastErrorDescription == nil {
            lastErrorDescription = HelperError.connectionUnavailable.errorDescription
        }
        staleConnection?.interruptionHandler = nil
        staleConnection?.invalidationHandler = nil
        staleConnection?.invalidate()
    }

    enum HelperError: LocalizedError {
        case installationFailed(String)
        case connectionUnavailable
        case versionMismatch(expected: String, actual: String)
        case writeFailed(key: String, description: String)
        case readFailed(key: String, description: String)
        case chargingControlFailed(description: String)

        var errorDescription: String? {
            switch self {
            case .installationFailed(let description):
                return "Helper install failed: \(description)"
            case .connectionUnavailable:
                return "Privileged helper unavailable"
            case .versionMismatch(let expected, let actual):
                return "Helper version mismatch (expected \(expected), got \(actual))"
            case .writeFailed(let key, let description):
                return "Failed to write \(key): \(description)"
            case .readFailed(let key, let description):
                return "Failed to read \(key): \(description)"
            case .chargingControlFailed(let description):
                return "Charging control failed: \(description)"
            }
        }
    }
}

// MARK: - SMCReadable Conformance

extension PrivilegedHelperManager: SMCReadable {}

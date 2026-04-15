import Foundation
import ServiceManagement

@MainActor
final class PrivilegedHelperManager: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var lastErrorDescription: String?

    private var _connection: NSXPCConnection?

    private var connection: NSXPCConnection {
        if let existing = _connection { return existing }

        let conn = NSXPCConnection(
            machServiceName: ChargeCapHelperConfiguration.machServiceName,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: ChargeCapHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.isInstalled = false
                self?._connection = nil
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
        try await writeSMCByte(key: "CH0B", value: 0x00)
        try? await writeSMCByte(key: "CH0C", value: 0x00)
    }

    func disableCharging() async throws {
        try await writeSMCByte(key: "CH0B", value: 0x02)
        try? await writeSMCByte(key: "CH0C", value: 0x02)
    }

    func pauseCharging() async throws {
        try await disableCharging()
    }

    func batteryRate() async throws -> UInt32 {
        try await readSMCUInt32(key: "BRSC")
    }

    func batteryTemperatureFromSMC() async throws -> Double {
        let rawValue = try await readSMCUInt32(key: "TB0T")
        let highByte = UInt8((rawValue >> 24) & 0xFF)
        let lowByte = UInt8((rawValue >> 16) & 0xFF)
        let sign = highByte & 0x80 == 0 ? 1.0 : -1.0
        return sign * (Double(highByte & 0x7F) + Double(lowByte) / 256.0)
    }

    func resetModifiedKeys() async {
        guard let helper = helperProxy else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var hasResumed = false

            func finish() -> Void {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume()
            }

            helper.resetModifiedKeys {
                Task { @MainActor in
                    finish()
                }
            }

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                finish()
            }
        }
    }

    private func invalidateConnection() {
        _connection?.invalidate()
        _connection = nil
    }

    private var helperProxy: ChargeCapHelperProtocol? {
        let conn = connection
        var proxyError: Error?
        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            proxyError = error
        } as? ChargeCapHelperProtocol

        if let proxyError {
            Task { @MainActor in
                self.isInstalled = false
                self.lastErrorDescription = proxyError.localizedDescription
            }
        }

        return proxy
    }

    private func registerDaemon() throws {
        let service = SMAppService.daemon(plistName: "com.chargecap.Helper.plist")
        // Unregister first to ensure launchd picks up the new binary.
        try? service.unregister()
        try service.register()
    }

    private static let xpcTimeout: TimeInterval = 5

    /// Wraps a continuation to guarantee exactly one resume, preventing leaks.
    private final class SafeContinuation<T: Sendable>: @unchecked Sendable {
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
    }

    private func getVersion() async throws -> String {
        guard let helper = helperProxy else {
            throw HelperError.connectionUnavailable
        }

        return try await withCheckedThrowingContinuation { raw in
            let continuation = SafeContinuation(raw)

            DispatchQueue.global().asyncAfter(deadline: .now() + Self.xpcTimeout) {
                continuation.resume(throwing: HelperError.connectionUnavailable)
            }

            helper.getVersion { version in
                if version == ChargeCapHelperConfiguration.version {
                    continuation.resume(returning: version)
                } else {
                    continuation.resume(throwing: HelperError.versionMismatch(expected: ChargeCapHelperConfiguration.version, actual: version))
                }
            }
        }
    }

    private func writeSMCByte(key: String, value: UInt8) async throws {
        guard let helper = helperProxy else {
            throw HelperError.connectionUnavailable
        }

        try await withCheckedThrowingContinuation { (raw: CheckedContinuation<Void, Error>) in
            let continuation = SafeContinuation(raw)

            DispatchQueue.global().asyncAfter(deadline: .now() + Self.xpcTimeout) {
                continuation.resume(throwing: HelperError.connectionUnavailable)
            }

            helper.writeSMCByte(key: key, value: value) { success, errorDescription in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HelperError.writeFailed(key: key, description: errorDescription ?? "Unknown SMC write error"))
                }
            }
        }
    }

    private func readSMCUInt32(key: String) async throws -> UInt32 {
        guard let helper = helperProxy else {
            throw HelperError.connectionUnavailable
        }

        return try await withCheckedThrowingContinuation { raw in
            let continuation = SafeContinuation(raw)

            DispatchQueue.global().asyncAfter(deadline: .now() + Self.xpcTimeout) {
                continuation.resume(throwing: HelperError.connectionUnavailable)
            }

            helper.readSMCUInt32(key: key) { value, errorDescription in
                if let errorDescription {
                    continuation.resume(throwing: HelperError.readFailed(key: key, description: errorDescription))
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    enum HelperError: LocalizedError {
        case installationFailed(String)
        case connectionUnavailable
        case versionMismatch(expected: String, actual: String)
        case writeFailed(key: String, description: String)
        case readFailed(key: String, description: String)

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
            }
        }
    }
}

import Foundation
import ServiceManagement
import Security

@MainActor
final class PrivilegedHelperManager: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var lastErrorDescription: String?

    private lazy var connection: NSXPCConnection = {
        let connection = NSXPCConnection(
            machServiceName: ChargeCapHelperConfiguration.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeCapHelperProtocol.self)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.isInstalled = false
            }
        }
        connection.resume()
        return connection
    }()

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

    func installIfNeeded() async throws {
        do {
            _ = try await getVersion()
            isInstalled = true
            lastErrorDescription = nil
            return
        } catch {
            isInstalled = false
        }

        try blessHelper()
        try await Task.sleep(for: .seconds(1))
        _ = try await getVersion()
        isInstalled = true
        lastErrorDescription = nil
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

    private var helperProxy: ChargeCapHelperProtocol? {
        connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.isInstalled = false
                self?.lastErrorDescription = error.localizedDescription
            }
        } as? ChargeCapHelperProtocol
    }

    private func blessHelper() throws {
        var authItem = kSMRightBlessPrivilegedHelper.withCString {
            AuthorizationItem(name: $0, valueLength: 0, value: nil, flags: 0)
        }
        var authRights = withUnsafeMutablePointer(to: &authItem) {
            AuthorizationRights(count: 1, items: $0)
        }

        let authFlags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(&authRights, nil, authFlags, &authRef)

        guard status == errAuthorizationSuccess else {
            throw HelperError.authorizationFailed(status)
        }

        var error: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            ChargeCapHelperConfiguration.helperIdentifier as CFString,
            authRef,
            &error
        )

        if let authorizationRef = authRef {
            AuthorizationFree(authorizationRef, [])
        }

        guard success else {
            let errorDescription = error?.takeRetainedValue().localizedDescription ?? "Unknown SMJobBless failure"
            throw HelperError.installationFailed(errorDescription)
        }
    }

    private func getVersion() async throws -> String {
        guard let helper = helperProxy else {
            throw HelperError.connectionUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
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

        try await withCheckedThrowingContinuation { continuation in
            helper.writeSMCByte(key: key, value: value) { success, errorDescription in
                if success {
                    continuation.resume()
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

        return try await withCheckedThrowingContinuation { continuation in
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
        case authorizationFailed(OSStatus)
        case installationFailed(String)
        case connectionUnavailable
        case versionMismatch(expected: String, actual: String)
        case writeFailed(key: String, description: String)
        case readFailed(key: String, description: String)

        var errorDescription: String? {
            switch self {
            case .authorizationFailed(let status):
                return SecCopyErrorMessageString(status, nil) as String? ?? "Authorization failed (\(status))"
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

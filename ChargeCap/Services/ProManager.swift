import Foundation
import StoreKit

// MARK: - Store Service Protocol

/// Outcome of a purchase attempt, independent of StoreKit types.
enum ProPurchaseOutcome: Equatable {
    case verified
    case verificationFailed
    case pending
    case userCancelled
    case unknown
}

/// Abstracts App Store operations so ProManager can be tested without live StoreKit.
@MainActor
protocol ProStoreService: AnyObject {
    /// Fetch the display price for a product.  Returns `nil` when the product is unavailable.
    func fetchDisplayPrice(for id: String) async throws -> String?

    /// Attempt to purchase the previously-fetched product.
    func purchaseProduct(id: String) async throws -> ProPurchaseOutcome

    /// Whether the user holds a verified entitlement for the given product.
    func hasVerifiedEntitlement(for productID: String) async -> Bool

    /// Synchronise receipts with the App Store.
    func sync() async throws
}

// MARK: - ProManager

@MainActor
final class ProManager: ObservableObject {
    @Published private(set) var productDisplayPrice: String?
    @Published private(set) var hasUnlockedPro: Bool
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseState: PurchaseState = .idle

    private let overrideDefaultsKey = "proOverrideEnabled"
    private let defaults: UserDefaults
    private let store: ProStoreService

    init(defaults: UserDefaults = .standard, store: ProStoreService? = nil) {
        self.defaults = defaults
        self.store = store ?? LiveProStoreService()
        #if DEBUG
        self.hasUnlockedPro = defaults.bool(forKey: overrideDefaultsKey)
        #else
        self.hasUnlockedPro = false
        #endif

        Task {
            await refreshProducts()
            await refreshEntitlements()
        }
    }

    enum PurchaseState: Equatable {
        case idle
        case purchased
        case pending
        case cancelled
        case failed(String)
    }

    func refreshProducts() async {
        do {
            productDisplayPrice = try await store.fetchDisplayPrice(for: Constants.Pro.productID)
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func refreshEntitlements() async {
        #if DEBUG
        var isUnlocked = defaults.bool(forKey: overrideDefaultsKey)
        #else
        var isUnlocked = false
        #endif

        if await store.hasVerifiedEntitlement(for: Constants.Pro.productID) {
            isUnlocked = true
        }

        hasUnlockedPro = isUnlocked
    }

    func purchasePro() async {
        guard productDisplayPrice != nil else {
            await refreshProducts()
            guard productDisplayPrice != nil else {
                purchaseState = .failed("Product unavailable")
                return
            }

            await performPurchase()
            return
        }

        await performPurchase()
    }

    func restorePurchases() async {
        do {
            try await store.sync()
            await refreshEntitlements()
            purchaseState = hasUnlockedPro ? .purchased : .idle
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    #if DEBUG
    func setDebugProOverride(_ enabled: Bool) {
        defaults.set(enabled, forKey: overrideDefaultsKey)
        hasUnlockedPro = enabled
    }
    #endif

    private func performPurchase() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let outcome = try await store.purchaseProduct(id: Constants.Pro.productID)
            applyPurchaseOutcome(outcome)
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func applyPurchaseOutcome(_ outcome: ProPurchaseOutcome) {
        switch outcome {
        case .verified:
            hasUnlockedPro = true
            purchaseState = .purchased
        case .verificationFailed:
            purchaseState = .failed("Purchase verification failed")
        case .pending:
            purchaseState = .pending
        case .userCancelled:
            purchaseState = .cancelled
        case .unknown:
            purchaseState = .failed("Unknown purchase result")
        }
    }
}

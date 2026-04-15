import Foundation
import StoreKit

@MainActor
final class ProManager: ObservableObject {
    @Published private(set) var product: Product?
    @Published private(set) var hasUnlockedPro: Bool
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseState: PurchaseState = .idle

    private let overrideDefaultsKey = "proOverrideEnabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasUnlockedPro = defaults.bool(forKey: overrideDefaultsKey)

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
            product = try await Product.products(for: [Constants.Pro.productID]).first
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func refreshEntitlements() async {
        var isUnlocked = defaults.bool(forKey: overrideDefaultsKey)

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Constants.Pro.productID {
                isUnlocked = true
                break
            }
        }

        hasUnlockedPro = isUnlocked
    }

    func purchasePro() async {
        guard let product else {
            await refreshProducts()
            guard let product else {
                purchaseState = .failed("Product unavailable")
                return
            }

            await purchase(product)
            return
        }

        await purchase(product)
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
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

    private func purchase(_ product: Product) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                guard case .verified(let transaction) = verificationResult else {
                    purchaseState = .failed("Purchase verification failed")
                    return
                }

                await transaction.finish()
                hasUnlockedPro = true
                purchaseState = .purchased
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .cancelled
            @unknown default:
                purchaseState = .failed("Unknown purchase result")
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }
}

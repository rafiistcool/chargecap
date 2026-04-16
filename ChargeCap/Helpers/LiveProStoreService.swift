import Foundation
import StoreKit

/// Real App Store–backed implementation of ``ProStoreService``.
@MainActor
final class LiveProStoreService: ProStoreService {
    private var cachedProducts: [String: Product] = [:]

    func fetchDisplayPrice(for id: String) async throws -> String? {
        let products = try await Product.products(for: [id])
        for product in products {
            cachedProducts[product.id] = product
        }
        return cachedProducts[id]?.displayPrice
    }

    func purchaseProduct(id: String) async throws -> ProPurchaseOutcome {
        guard let product = cachedProducts[id] else {
            return .unknown
        }

        let result = try await product.purchase()

        switch result {
        case .success(let verificationResult):
            guard case .verified(let transaction) = verificationResult else {
                return .verificationFailed
            }
            await transaction.finish()
            return .verified
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .unknown
        }
    }

    func hasVerifiedEntitlement(for productID: String) async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == productID {
                return true
            }
        }
        return false
    }

    func sync() async throws {
        try await AppStore.sync()
    }
}

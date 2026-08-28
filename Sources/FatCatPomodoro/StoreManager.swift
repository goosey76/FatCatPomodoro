import Foundation
import StoreKit

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()

    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var isUnlocked: Bool = false

    private var updateListenerTask: Task<Void, Error>? = nil
    
    private let lifetimeProductId = "com.fatcat.FatCatPomodoro.lifetime"
    private let monthlyProductId = "com.fatcat.FatCatPomodoro.monthly"

    private init() {
        // Start listening to transactions immediately
        updateListenerTask = listenForTransactions()
        
        Task {
            await fetchProducts()
            await updateEntitlements()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    func fetchProducts() async {
        do {
            let products = try await Product.products(for: [lifetimeProductId, monthlyProductId])
            for product in products {
                switch product.id {
                case lifetimeProductId:
                    lifetimeProduct = product
                case monthlyProductId:
                    monthlyProduct = product
                default:
                    break
                }
            }
        } catch {
            print("Failed to fetch products: \(error)")
        }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateEntitlements()
            await transaction.finish()
            
            // Log to Jarvi
            let eventName = product.id == lifetimeProductId ? "IAP_PURCHASE_LIFETIME" : "IAP_PURCHASE_MONTHLY"
            JarviManager.shared.sendFatcatEvent(eventName, title: "Purchased \(product.displayName)")

        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateEntitlements()
        } catch {
            print("Failed to restore purchases: \(error)")
        }
    }

    private func updateEntitlements() async {
        var hasUnlock = false
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.productID == lifetimeProductId || transaction.productID == monthlyProductId {
                    hasUnlock = true
                }
            } catch {
                print("Transaction verification failed: \(error)")
            }
        }
        
        isUnlocked = hasUnlock
    }

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updateEntitlements()
                    await transaction.finish()
                } catch {
                    print("Transaction update verification failed: \(error)")
                }
            }
        }
    }

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

enum StoreError: Error {
    case failedVerification
}

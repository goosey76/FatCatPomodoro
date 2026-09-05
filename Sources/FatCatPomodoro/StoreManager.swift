import Foundation
import StoreKit
import AppKit

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()

    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var hasActiveEntitlement: Bool = false
    
    var isUnlocked: Bool {
        hasActiveEntitlement
    }

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

    func purchase(_ product: Product, confirmIn window: NSWindow? = nil) async throws {
        // Since macOS 15.2, StoreKit routes every purchase through a "UI anchor"
        // lookup that needs a foreground-active key window. This app is .accessory
        // with a non-activating overlay panel, so no valid anchor exists and the
        // legacy purchase() silently fails. Anchoring explicitly to a real window
        // via purchase(confirmIn:) is the documented fix.
        let result: Product.PurchaseResult
        if #available(macOS 15.2, *), let window {
            result = try await product.purchase(confirmIn: window)
        } else {
            result = try await product.purchase()
        }

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            // Finish BEFORE querying entitlements: currentEntitlements may not
            // report a transaction until it has been finished.
            await transaction.finish()
            await updateEntitlements()

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

    /// Public hook for SwiftUI StoreKit views (ProductView) to refresh entitlement
    /// state immediately after they complete a purchase.
    func refresh() async {
        await updateEntitlements()
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

        // Fallback: currentEntitlements can lag right after a purchase (notably in
        // the Xcode StoreKit test environment). Check the latest transaction for
        // each product directly before concluding the user owns nothing.
        if !hasUnlock {
            for productId in [lifetimeProductId, monthlyProductId] {
                guard let latest = await Transaction.latest(for: productId),
                      case .verified(let transaction) = latest else { continue }
                let expired = transaction.expirationDate.map { $0 <= Date() } ?? false
                if transaction.revocationDate == nil && !expired {
                    hasUnlock = true
                }
            }
        }

        hasActiveEntitlement = hasUnlock
    }

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    // Finish first — currentEntitlements may not report an
                    // unfinished transaction.
                    await transaction.finish()
                    await self.updateEntitlements()
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

import Foundation
import Observation
import StoreKit

/// The Pro products.
///
/// One entitlement, two durations, one subscription group at the same service
/// level — so switching between monthly and yearly is a plan change rather than
/// a different product with different features.
enum ProProduct {
    static let monthly = "com.idlery.odomind.pro.monthly"
    static let yearly = "com.idlery.odomind.pro.yearly"
    static let all: [String] = [monthly, yearly]

    /// The subscription group these belong to in App Store Connect. Recorded
    /// here so `docs/PRO-SETUP.md` and the code cannot drift.
    static let groupReferenceName = "Odomind Pro"
}

/// What Odomind knows about the owner's entitlement right now.
enum ProStatus: Equatable {
    /// StoreKit has not answered yet. Never used to deny anything: a slow
    /// answer must not look like an expired subscription.
    case unknown
    case notSubscribed
    case subscribed(expiresOn: Date?, isInGracePeriod: Bool)

    var isActive: Bool {
        if case .subscribed = self { return true }
        return false
    }
}

/// The single place that decides whether Pro is on.
///
/// StoreKit is the authority. Nothing here writes an entitlement to disk, and
/// there is no debug flag that turns Pro on in a release build — an
/// entitlement that can be set by anything other than a verified transaction
/// is not an entitlement.
@MainActor
@Observable
final class EntitlementService {
    private(set) var status: ProStatus = .unknown
    private(set) var products: [Product] = []
    private(set) var loadFailure: String?
    private(set) var isPurchasing = false

    private var updatesTask: Task<Void, Never>?

    /// Launch-argument override, compiled into DEBUG builds only.
    ///
    /// Used by UI tests to photograph the Pro screens without a sandbox
    /// account. `#if DEBUG` is doing real work here: this cannot exist in the
    /// build that ships, so it can never be a bypass.
    #if DEBUG
    static let simulateProArgument = "-odomind-simulate-pro"
    private var isSimulatingPro: Bool {
        ProcessInfo.processInfo.arguments.contains(AppModel.uiTestingArgument)
            && ProcessInfo.processInfo.arguments.contains(Self.simulateProArgument)
    }
    #else
    private var isSimulatingPro: Bool { false }
    #endif

    init() {
        updatesTask = Task { [weak self] in
            // Renewals, refunds, revocations and Ask-to-Buy approvals all
            // arrive here, including ones that happened while the app was
            // closed.
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func start() async {
        if isSimulatingPro {
            status = .subscribed(expiresOn: nil, isInGracePeriod: false)
            return
        }
        await loadProducts()
        await refreshEntitlement()
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: ProProduct.all)
            // Cheapest-per-period first is a pricing argument, not an order.
            // Monthly then yearly matches how the choice is usually read.
            products = loaded.sorted { left, right in
                left.price < right.price
            }
            loadFailure = products.isEmpty
                ? "Odomind could not load subscription details from the App Store."
                : nil
        } catch {
            products = []
            loadFailure = "Odomind could not reach the App Store. Check your connection and try again."
        }
    }

    /// Re-reads the entitlement from StoreKit.
    ///
    /// Called at launch and when the app returns to the foreground.
    /// `currentEntitlements` is served from the device's own signed receipt
    /// data, so a temporary loss of connectivity does not revoke Pro.
    func refreshEntitlement() async {
        if isSimulatingPro { return }

        var active: ProStatus = .notSubscribed
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ProProduct.all.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }

            let inGrace = await isInBillingGracePeriod(productID: transaction.productID)
            active = .subscribed(expiresOn: transaction.expirationDate, isInGracePeriod: inGrace)
        }
        status = active
    }

    /// Billing-retry with grace keeps access on while Apple retries the
    /// payment. Treating that as an expiry would cut someone off over a card
    /// that is about to go through.
    private func isInBillingGracePeriod(productID: String) async -> Bool {
        guard let product = products.first(where: { $0.id == productID }) ?? (try? await Product.products(for: [productID]))?.first,
              let subscription = product.subscription,
              let statuses = try? await subscription.status
        else { return false }

        return statuses.contains { $0.state == .inBillingRetryPeriod || $0.state == .inGracePeriod }
    }

    enum PurchaseOutcome: Equatable {
        case purchased
        case pending
        case cancelled
        case failed(String)
    }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        guard !isPurchasing else { return .cancelled }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("The App Store returned a receipt Odomind could not verify.")
                }
                await transaction.finish()
                await refreshEntitlement()
                return .purchased
            case .pending:
                // Ask to Buy, or a payment awaiting approval. Nothing is
                // unlocked; `Transaction.updates` will deliver it if approved.
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("The App Store returned an unexpected result.")
            }
        } catch {
            return .failed(friendlyMessage(for: error))
        }
    }

    func restore() async -> PurchaseOutcome {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            return status.isActive ? .purchased : .failed("No active Odomind Pro subscription was found on this Apple Account.")
        } catch {
            return .failed(friendlyMessage(for: error))
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        await refreshEntitlement()
    }

    /// Apple's errors are actionable; the raw ones are not, and some carry
    /// infrastructure detail that has no business on screen.
    private func friendlyMessage(for error: Error) -> String {
        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .networkError:
                return "Odomind could not reach the App Store. Check your connection and try again."
            case .userCancelled:
                return "Purchase cancelled."
            case .notAvailableInStorefront:
                return "Odomind Pro is not available in your App Store region yet."
            case .notEntitled:
                return "This Apple Account is not entitled to make this purchase."
            default:
                return "The App Store could not complete this right now. Please try again."
            }
        }
        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .productUnavailable:
                return "This subscription is not available right now."
            case .purchaseNotAllowed:
                return "Purchases are not allowed on this device. Check Screen Time restrictions."
            default:
                return "The App Store could not complete this right now. Please try again."
            }
        }
        return "The App Store could not complete this right now. Please try again."
    }
}

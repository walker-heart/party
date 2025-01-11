import StoreKit
import SwiftUI

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()
    
    @Published private(set) var subscriptions: [Product] = []
    @Published private(set) var purchasedSubscriptions: [Product] = []
    @Published var isSubscribed = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let productIds = ["premium_monthly"]
    private var transactionListener: Task<Void, Error>?
    
    private init() {
        // Start listening for transactions as soon as the app launches
        transactionListener = Task {
            await setupTransactionListener()
        }
        
        // Load products and check subscription status
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Print environment information
            #if DEBUG
            print("Running in DEBUG mode")
            if let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene {
                print("Debug mode - will check App Store Connect or StoreKit Configuration")
            } else {
                print("No window scene found - will use App Store Connect")
            }
            #else
            print("Running in RELEASE mode - using App Store Connect")
            #endif
            
            print("Attempting to load products with IDs: \(productIds)")
            
            // Request products from App Store Connect or StoreKit Configuration
            let storeProducts = try await Product.products(for: productIds)
            print("Raw products received: \(storeProducts.map { product in "\(product.id) (\(product.type))" })")
            
            // Filter for auto-renewable subscriptions
            subscriptions = storeProducts.filter { $0.type == .autoRenewable }
            
            if subscriptions.isEmpty {
                let errorMsg: String
                #if DEBUG
                errorMsg = "No subscription products found. Verify:\n1. StoreKit configuration file is selected in scheme\n2. Product IDs match configuration"
                #else
                errorMsg = "No subscription products found. Verify:\n1. Products are approved in App Store Connect\n2. Using Sandbox account\n3. Product IDs match App Store Connect"
                #endif
                errorMessage = errorMsg
                print("\nDEBUG INFO:")
                print(errorMsg)
                print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
            } else {
                print("\nSuccessfully loaded \(subscriptions.count) subscriptions:")
                for product in subscriptions {
                    print("- ID: \(product.id)")
                    print("  Price: \(product.displayPrice)")
                    print("  Type: \(product.type)")
                    print("  Subscription Period: \(product.subscription?.subscriptionPeriod.debugDescription ?? "N/A")")
                }
            }
        } catch {
            let debugMsg = """
            Failed to load products: \(error)
            Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")
            Product IDs: \(productIds)
            Error Details: \(error.localizedDescription)
            """
            
            print("\nDEBUG INFO:")
            print(debugMsg)
            
            #if DEBUG
            errorMessage = debugMsg
            #else
            errorMessage = "Unable to connect to the App Store. Please try again later."
            #endif
        }
        
        isLoading = false
    }
    
    func purchase(_ product: Product) async throws {
        isLoading = true
        errorMessage = nil
        
        defer {
            isLoading = false
        }
        
        do {
            print("Starting purchase for product: \(product.id)")
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    print("Purchase verified: \(transaction.id)")
                    await transaction.finish()
                    await updateSubscriptionStatus()
                    print("Successfully purchased: \(product.id)")
                case .unverified(_, let error):
                    print("Purchase verification failed: \(error)")
                    throw StoreError.failedVerification
                }
            case .userCancelled:
                print("Purchase cancelled by user")
                throw StoreError.userCancelled
            case .pending:
                print("Purchase pending further action")
                throw StoreError.pending
            @unknown default:
                print("Unknown purchase result")
                throw StoreError.unknown
            }
        } catch {
            if let storeError = error as? StoreError {
                errorMessage = storeError.errorDescription
            } else {
                #if DEBUG
                errorMessage = "Purchase failed: \(error.localizedDescription)"
                #else
                errorMessage = "Purchase failed. Please try again later."
                #endif
            }
            print("Purchase failed with error: \(error)")
            throw error
        }
    }
    
    private func setupTransactionListener() async {
        print("Setting up transaction listener")
        for await result in Transaction.updates {
            do {
                switch result {
                case .verified(let transaction):
                    print("Received verified transaction: \(transaction.id)")
                    if transaction.productID == "premium_monthly" {
                        if transaction.revocationDate == nil {
                            if transaction.isUpgraded {
                                print("Subscription was upgraded")
                            }
                            await updateSubscriptionStatus()
                        } else {
                            print("Subscription was revoked")
                            isSubscribed = false
                        }
                    }
                    await transaction.finish()
                case .unverified(let transaction, let error):
                    print("Unverified transaction: \(transaction.id), Error: \(error)")
                    await transaction.finish()
                }
            } catch {
                print("Transaction error: \(error)")
            }
        }
    }
    
    func updateSubscriptionStatus() async {
        print("Updating subscription status")
        var hasActiveSubscription = false
        
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                print("Checking entitlement: \(transaction.id)")
                if transaction.productID == "premium_monthly" {
                    if transaction.revocationDate == nil {
                        if let expirationDate = transaction.expirationDate {
                            let isValid = expirationDate > Date()
                            print("Subscription valid until: \(expirationDate), Currently valid: \(isValid)")
                            if isValid {
                                hasActiveSubscription = true
                                break
                            }
                        }
                    }
                }
            case .unverified(_, let error):
                print("Unverified entitlement: \(error)")
                continue
            }
        }
        
        isSubscribed = hasActiveSubscription
        print("Subscription status updated - Is subscribed: \(hasActiveSubscription)")
    }
    
    func manageSubscriptions() async {
        guard let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            print("No window scene found")
            return
        }
        
        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            #if DEBUG
            errorMessage = "Failed to show subscription management: \(error.localizedDescription)"
            #else
            errorMessage = "Unable to open subscription management. Please try again later."
            #endif
            print("Failed to show subscription management: \(error)")
        }
    }
}

enum StoreError: LocalizedError {
    case failedVerification
    case userCancelled
    case pending
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Transaction verification failed"
        case .userCancelled:
            return "Transaction was cancelled"
        case .pending:
            return "Transaction is pending"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}